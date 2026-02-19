use std::{collections::HashMap, sync::mpsc as std_mpsc, thread::JoinHandle as StdJoinHandle};

use anyhow::{anyhow, Result};
use chrono::Utc;
use tauri::{AppHandle, Emitter};
use tokio::{
    sync::{mpsc, watch, Mutex},
    task::JoinHandle,
};
use uuid::Uuid;

use crate::{
    asr::provider::{self, AsrConnectInput, AsrEventKind},
    audio::mic_capture,
    events::{
        EVENT_HINT_DELTA, EVENT_RUNTIME_ERROR, EVENT_SESSION_STATE, EVENT_TRANSCRIPT_SEGMENT,
        EVENT_TRANSLATION_SEGMENT,
    },
    llm::LlmService,
    models::{
        AsrProvider, HintDeltaEvent, MeetingProfile, RuntimeErrorEvent, SegmentSource,
        SessionLifecycleState, SessionStartResult, SessionStateEvent, SpeakerRole,
        StartSessionInput, TranscriptSegmentEvent, TranslationSegmentEvent, TranslationSource,
    },
    secrets::AliyunSecrets,
};

struct RunningSession {
    session_id: String,
    provider: AsrProvider,
    stop_tx: watch::Sender<bool>,
    tasks: Vec<JoinHandle<()>>,
    mic_stop_tx: std_mpsc::Sender<()>,
    mic_thread: StdJoinHandle<()>,
}

#[derive(Default)]
pub struct SessionManager {
    running: Mutex<Option<RunningSession>>,
}

pub struct StartSessionContext {
    pub app: AppHandle,
    pub input: StartSessionInput,
    pub profile: MeetingProfile,
    pub deepgram_key: Option<String>,
    pub aliyun_secrets: Option<AliyunSecrets>,
    pub llm_service: Option<LlmService>,
    pub http_client: reqwest::Client,
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            running: Mutex::new(None),
        }
    }

    pub async fn start(&self, context: StartSessionContext) -> Result<SessionStartResult> {
        let mut guard = self.running.lock().await;
        if guard.is_some() {
            return Err(anyhow!("a live session is already running"));
        }

        let session_id = Uuid::new_v4().to_string();
        let preferred_provider = context.input.asr_provider.unwrap_or_default();
        emit_session_state(
            &context.app,
            SessionStateEvent {
                session_id: session_id.clone(),
                state: SessionLifecycleState::Starting,
                message: "Starting microphone live session".to_string(),
                degraded_mode: true,
                provider: preferred_provider,
            },
        )?;

        let (sample_rate, channels) =
            mic_capture::resolve_capture_format(context.input.microphone_id.as_deref())?;

        let asr_connection = provider::connect_with_fallback(AsrConnectInput {
            preferred_provider,
            deepgram_key: context.deepgram_key.clone(),
            aliyun_secrets: context.aliyun_secrets.clone(),
            source_language: context.input.source_language.clone(),
            target_language: context.input.target_language.clone(),
            sample_rate,
            channels,
            http_client: context.http_client.clone(),
        })
        .await?;
        let active_provider = asr_connection.provider;

        if let Some(reason) = asr_connection.fallback_reason.clone() {
            emit_runtime_error(
                &context.app,
                RuntimeErrorEvent {
                    code: "ASR_PROVIDER_FALLBACK".to_string(),
                    message: reason,
                    recoverable: true,
                    provider: Some(active_provider),
                    source: "asr".to_string(),
                },
            );
        }

        let (stop_tx, stop_rx) = watch::channel(false);
        let (audio_tx, mut audio_rx) = mpsc::channel::<Vec<i16>>(128);

        let mic_worker =
            mic_capture::spawn_capture_worker(context.input.microphone_id.clone(), audio_tx, 0.015);

        let (mic_stop_tx, mic_thread) = match mic_worker {
            Ok(worker) => worker,
            Err(error) => {
                let _ = asr_connection.sender.close().await;
                return Err(error);
            }
        };

        let forward_app = context.app.clone();
        let forward_session_id = session_id.clone();
        let mut forward_stop_rx = stop_rx.clone();
        let asr_sender_for_audio = asr_connection.sender.clone();

        let forward_task = tokio::spawn(async move {
            loop {
                tokio::select! {
                    changed = forward_stop_rx.changed() => {
                        if changed.is_err() || *forward_stop_rx.borrow() {
                            let _ = asr_sender_for_audio.close().await;
                            break;
                        }
                    }
                    chunk = audio_rx.recv() => {
                        let Some(chunk) = chunk else {
                            let _ = asr_sender_for_audio.close().await;
                            break;
                        };

                        if let Err(error) = asr_sender_for_audio.send_pcm(&chunk).await {
                            emit_runtime_error(
                                &forward_app,
                                RuntimeErrorEvent {
                                    code: "ASR_SEND_FAILED".to_string(),
                                    message: format!("failed to send audio: {error}"),
                                    recoverable: true,
                                    provider: Some(active_provider),
                                    source: "audio".to_string(),
                                },
                            );
                            let _ = emit_session_state(
                                &forward_app,
                                SessionStateEvent {
                                    session_id: forward_session_id.clone(),
                                    state: SessionLifecycleState::Error,
                                    message: "Audio forwarding failed".to_string(),
                                    degraded_mode: true,
                                    provider: active_provider,
                                },
                            );
                            break;
                        }
                    }
                }
            }
        });

        let llm_service = context.llm_service.clone();
        let transcript_app = context.app.clone();
        let transcript_session_id = session_id.clone();
        let mut transcript_stop_rx = stop_rx.clone();
        let profile_context = assemble_profile_context(&context.profile);
        let mut asr_rx = asr_connection.receiver;

        let transcript_task = tokio::spawn(async move {
            let mut sentence_to_transcript_id: HashMap<i64, String> = HashMap::new();
            let mut latest_transcript_id: Option<String> = None;

            loop {
                tokio::select! {
                    changed = transcript_stop_rx.changed() => {
                        if changed.is_err() || *transcript_stop_rx.borrow() {
                            break;
                        }
                    }
                    item = asr_rx.recv() => {
                        let Some(item) = item else {
                            break;
                        };

                        match item.kind {
                            AsrEventKind::Transcript => {
                                let transcript_id = Uuid::new_v4().to_string();
                                if let Some(index) = item.sentence_index {
                                    sentence_to_transcript_id.insert(index, transcript_id.clone());
                                }

                                latest_transcript_id = Some(transcript_id.clone());
                                let transcript_event = TranscriptSegmentEvent {
                                    id: transcript_id.clone(),
                                    session_id: transcript_session_id.clone(),
                                    speaker: SpeakerRole::Me,
                                    text: item.text.clone(),
                                    is_final: item.is_final,
                                    timestamp_ms: Utc::now().timestamp_millis(),
                                    provider: active_provider,
                                    source: SegmentSource::Microphone,
                                };

                                if transcript_app
                                    .emit(EVENT_TRANSCRIPT_SEGMENT, &transcript_event)
                                    .is_err()
                                {
                                    break;
                                }

                                if item.is_final {
                                    if let Some(service) = llm_service.clone() {
                                        process_final_transcript(
                                            transcript_app.clone(),
                                            transcript_session_id.clone(),
                                            transcript_id,
                                            item.text,
                                            profile_context.clone(),
                                            service,
                                            active_provider,
                                            active_provider == AsrProvider::Deepgram,
                                        )
                                        .await;
                                    }
                                }
                            }
                            AsrEventKind::Translation => {
                                let transcript_id = item
                                    .sentence_index
                                    .and_then(|index| sentence_to_transcript_id.get(&index).cloned())
                                    .or_else(|| latest_transcript_id.clone())
                                    .unwrap_or_else(|| Uuid::new_v4().to_string());
                                let translation_event = TranslationSegmentEvent {
                                    id: Uuid::new_v4().to_string(),
                                    transcript_id,
                                    text: item.text,
                                    is_final: item.is_final,
                                    timestamp_ms: Utc::now().timestamp_millis(),
                                    provider: active_provider,
                                    source: TranslationSource::Asr,
                                };
                                if transcript_app
                                    .emit(EVENT_TRANSLATION_SEGMENT, &translation_event)
                                    .is_err()
                                {
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        });

        let mut running_message = "Session running in microphone-only mode".to_string();
        if active_provider == AsrProvider::Aliyun {
            running_message.push_str(" (Aliyun Tingwu)");
        } else {
            running_message.push_str(" (Deepgram fallback)");
        }

        let state_event = SessionStateEvent {
            session_id: session_id.clone(),
            state: SessionLifecycleState::Running,
            message: running_message,
            degraded_mode: true,
            provider: active_provider,
        };
        emit_session_state(&context.app, state_event)?;

        *guard = Some(RunningSession {
            session_id: session_id.clone(),
            provider: active_provider,
            stop_tx,
            tasks: vec![forward_task, transcript_task],
            mic_stop_tx,
            mic_thread,
        });

        Ok(SessionStartResult {
            session_id,
            degraded_mode: true,
            message: "System loopback is unavailable in MVP. Using microphone only.".to_string(),
            provider: active_provider,
        })
    }

    pub async fn stop(&self, app: &AppHandle) -> Result<()> {
        let mut guard = self.running.lock().await;
        let Some(running) = guard.take() else {
            return Ok(());
        };
        drop(guard);

        let _ = running.stop_tx.send(true);
        let _ = running.mic_stop_tx.send(());

        for task in running.tasks {
            task.abort();
        }

        let mic_thread = running.mic_thread;
        let _ = tokio::task::spawn_blocking(move || {
            let _ = mic_thread.join();
        })
        .await;

        emit_session_state(
            app,
            SessionStateEvent {
                session_id: running.session_id,
                state: SessionLifecycleState::Stopped,
                message: "Session stopped".to_string(),
                degraded_mode: true,
                provider: running.provider,
            },
        )?;

        Ok(())
    }
}

async fn process_final_transcript(
    app: AppHandle,
    session_id: String,
    transcript_id: String,
    transcript_text: String,
    profile_context: String,
    llm_service: LlmService,
    asr_provider: AsrProvider,
    allow_llm_translation: bool,
) {
    if allow_llm_translation {
        if let Ok(translation) = llm_service.translate_to_chinese(&transcript_text).await {
            let event = TranslationSegmentEvent {
                id: Uuid::new_v4().to_string(),
                transcript_id: transcript_id.clone(),
                text: translation,
                is_final: true,
                timestamp_ms: Utc::now().timestamp_millis(),
                provider: asr_provider,
                source: TranslationSource::Llm,
            };
            let _ = app.emit(EVENT_TRANSLATION_SEGMENT, event);
        }
    }

    if looks_like_question(&transcript_text) {
        match llm_service
            .suggest_answer(&profile_context, &transcript_text)
            .await
        {
            Ok(hint) => {
                stream_hint(&app, &session_id, &hint).await;
            }
            Err(error) => {
                emit_runtime_error(
                    &app,
                    RuntimeErrorEvent {
                        code: "HINT_ENGINE_FAILED".to_string(),
                        message: format!("failed to generate answer hint: {error}"),
                        recoverable: true,
                        provider: Some(asr_provider),
                        source: "llm".to_string(),
                    },
                );
            }
        }
    }
}

async fn stream_hint(app: &AppHandle, session_id: &str, hint: &str) {
    let hint_id = Uuid::new_v4().to_string();

    for token in hint.split_whitespace() {
        let event = HintDeltaEvent {
            id: hint_id.clone(),
            session_id: session_id.to_string(),
            delta: format!("{token} "),
            done: false,
            source: "llm".to_string(),
        };
        let _ = app.emit(EVENT_HINT_DELTA, event);
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    }

    let done = HintDeltaEvent {
        id: hint_id,
        session_id: session_id.to_string(),
        delta: String::new(),
        done: true,
        source: "llm".to_string(),
    };
    let _ = app.emit(EVENT_HINT_DELTA, done);
}

fn looks_like_question(text: &str) -> bool {
    let lower = text.to_lowercase();
    lower.contains('?')
        || lower.contains("what")
        || lower.contains("why")
        || lower.contains("how")
        || lower.contains("could you")
        || lower.contains("would you")
}

fn assemble_profile_context(profile: &MeetingProfile) -> String {
    let attachments = profile
        .attachments
        .iter()
        .map(|record| record.extracted_text.as_str())
        .collect::<Vec<_>>()
        .join("\n\n");

    format!(
        "Name: {}\nType: {}\nDomain: {}\nLanguage: {}\nSelf Intro: {}\nNotes: {}\nAttachments:\n{}",
        profile.name,
        profile.meeting_type,
        profile.domain,
        profile.language,
        profile.self_intro,
        profile.context_notes,
        attachments
    )
}

fn emit_session_state(app: &AppHandle, event: SessionStateEvent) -> Result<()> {
    app.emit(EVENT_SESSION_STATE, event)?;
    Ok(())
}

fn emit_runtime_error(app: &AppHandle, event: RuntimeErrorEvent) {
    let _ = app.emit(EVENT_RUNTIME_ERROR, event);
}
