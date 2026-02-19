use std::{
    collections::BTreeMap,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
};

use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use futures_util::{SinkExt, StreamExt};
use hmac::{Hmac, Mac};
use serde_json::json;
use sha1::Sha1;
use tokio::sync::{mpsc, Mutex};
use tokio_tungstenite::tungstenite::{self, Message};
use uuid::Uuid;

use crate::{asr::provider::AsrEventKind, secrets::AliyunSecrets};

#[derive(Debug, Clone)]
pub struct AliyunEvent {
    pub kind: AsrEventKind,
    pub text: String,
    pub is_final: bool,
    pub sentence_index: Option<i64>,
}

#[derive(Clone)]
pub struct AliyunSender {
    write: Arc<Mutex<AliyunWriteHalf>>,
    closer: Arc<AliyunCloser>,
}

type AliyunWsStream =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
type AliyunWriteHalf = futures_util::stream::SplitSink<AliyunWsStream, Message>;
type AliyunReadHalf = futures_util::stream::SplitStream<AliyunWsStream>;

struct AliyunCloser {
    closed: AtomicBool,
    app_key: String,
    stream_task_id: String,
    task_id: String,
    http_client: reqwest::Client,
    access_key_id: String,
    access_key_secret: String,
}

impl AliyunSender {
    pub async fn send_pcm(&self, pcm: &[i16]) -> Result<()> {
        let mut payload = Vec::with_capacity(pcm.len() * 2);
        for sample in pcm {
            payload.extend_from_slice(&sample.to_le_bytes());
        }

        let mut write = self.write.lock().await;
        write
            .send(Message::Binary(payload.into()))
            .await
            .context("failed to send audio chunk to Aliyun Tingwu")?;
        Ok(())
    }

    pub async fn close(&self) -> Result<()> {
        if self.closer.closed.swap(true, Ordering::SeqCst) {
            return Ok(());
        }

        let stop_payload =
            build_stop_transcription_payload(&self.closer.app_key, &self.closer.stream_task_id);
        {
            let mut write = self.write.lock().await;
            let _ = write.send(Message::Text(stop_payload.into())).await;
            let _ = write.send(Message::Close(None)).await;
        }

        let _ = stop_task(
            &self.closer.http_client,
            &self.closer.access_key_id,
            &self.closer.access_key_secret,
            &self.closer.task_id,
        )
        .await;

        Ok(())
    }
}

pub async fn connect_live(
    http_client: reqwest::Client,
    secrets: AliyunSecrets,
    source_language: &str,
    target_language: &str,
    sample_rate: u32,
) -> Result<(AliyunSender, mpsc::Receiver<AliyunEvent>)> {
    let task = create_task(
        &http_client,
        &secrets.access_key_id,
        &secrets.access_key_secret,
        &secrets.app_key,
        source_language,
        target_language,
    )
    .await?;

    let request = tungstenite::http::Request::builder()
        .method("GET")
        .uri(&task.meeting_join_url)
        .body(())
        .context("failed to build Aliyun websocket request")?;

    let (stream, _) = tokio_tungstenite::connect_async(request)
        .await
        .context("failed to connect Aliyun meeting websocket")?;

    let (mut write, read) = stream.split();
    let stream_task_id = Uuid::new_v4().to_string();
    let start_payload =
        build_start_transcription_payload(&secrets.app_key, &stream_task_id, sample_rate);
    write
        .send(Message::Text(start_payload.into()))
        .await
        .context("failed to start Aliyun transcription stream")?;

    let sender = AliyunSender {
        write: Arc::new(Mutex::new(write)),
        closer: Arc::new(AliyunCloser {
            closed: AtomicBool::new(false),
            app_key: secrets.app_key.clone(),
            stream_task_id,
            task_id: task.task_id,
            http_client,
            access_key_id: secrets.access_key_id,
            access_key_secret: secrets.access_key_secret,
        }),
    };

    let (tx, rx) = mpsc::channel(256);
    spawn_reader(read, tx);

    Ok((sender, rx))
}

fn spawn_reader(mut read: AliyunReadHalf, tx: mpsc::Sender<AliyunEvent>) {
    tokio::spawn(async move {
        while let Some(message) = read.next().await {
            match message {
                Ok(Message::Text(text)) => {
                    if let Some(events) = parse_event_payload(&text) {
                        for event in events {
                            if tx.send(event).await.is_err() {
                                return;
                            }
                        }
                    }
                }
                Ok(Message::Close(_)) => break,
                Ok(_) => {}
                Err(_) => break,
            }
        }
    });
}

fn parse_event_payload(payload: &str) -> Option<Vec<AliyunEvent>> {
    let value: serde_json::Value = serde_json::from_str(payload).ok()?;
    let name = value
        .get("header")
        .and_then(|header| header.get("name"))
        .and_then(|name| name.as_str())?;

    let payload = value.get("payload")?;
    let mut events = Vec::new();

    match name {
        "TranscriptionResultChanged" | "SentenceBegin" | "SentenceEnd" => {
            let text = payload
                .get("result")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim();
            if text.is_empty() {
                return None;
            }
            let is_final = name == "SentenceEnd";
            let index = payload.get("index").and_then(|v| v.as_i64());
            events.push(AliyunEvent {
                kind: AsrEventKind::Transcript,
                text: text.to_string(),
                is_final,
                sentence_index: index,
            });
        }
        "ResultTranslated" => {
            let partial = payload
                .get("partial")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let mut translated = String::new();
            let mut sentence_index = payload.get("index").and_then(|v| v.as_i64());
            if let Some(items) = payload.get("translate_result").and_then(|v| v.as_array()) {
                for item in items {
                    if sentence_index.is_none() {
                        sentence_index = item.get("index").and_then(|v| v.as_i64());
                    }
                    if let Some(text) = item.get("text").and_then(|v| v.as_str()) {
                        if !translated.is_empty() {
                            translated.push(' ');
                        }
                        translated.push_str(text.trim());
                    }
                }
            }
            if translated.is_empty() {
                return None;
            }
            events.push(AliyunEvent {
                kind: AsrEventKind::Translation,
                text: translated,
                is_final: !partial,
                sentence_index,
            });
        }
        _ => {}
    }

    if events.is_empty() {
        None
    } else {
        Some(events)
    }
}

struct CreateTaskResult {
    task_id: String,
    meeting_join_url: String,
}

async fn create_task(
    http_client: &reqwest::Client,
    access_key_id: &str,
    access_key_secret: &str,
    app_key: &str,
    source_language: &str,
    target_language: &str,
) -> Result<CreateTaskResult> {
    let query = map_query([("type", "realtime".to_string())]);
    let body = json!({
        "AppKey": app_key,
        "TranscriptionEnabled": true,
        "TranslationEnabled": true,
        "SourceLanguage": source_language,
        "TranslationLanguages": [target_language],
    })
    .to_string();

    let response = send_signed_roa_request(
        http_client,
        access_key_id,
        access_key_secret,
        "PUT",
        "/openapi/tingwu/v2/tasks",
        &query,
        &body,
    )
    .await?;

    if !response.status().is_success() {
        let body = response.text().await.unwrap_or_default();
        return Err(anyhow!("Aliyun CreateTask failed: {body}"));
    }

    let value: serde_json::Value = response
        .json()
        .await
        .context("failed to parse Aliyun CreateTask response")?;

    let data = value
        .get("Data")
        .or_else(|| value.get("data"))
        .ok_or_else(|| anyhow!("Aliyun CreateTask response missing Data field: {}", value))?;

    let task_id = data
        .get("TaskId")
        .or_else(|| data.get("taskId"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("Aliyun CreateTask response missing TaskId: {}", value))?
        .to_string();

    let meeting_join_url = data
        .get("MeetingJoinUrl")
        .or_else(|| data.get("meetingJoinUrl"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| {
            anyhow!(
                "Aliyun CreateTask response missing MeetingJoinUrl: {}",
                value
            )
        })?
        .to_string();

    Ok(CreateTaskResult {
        task_id,
        meeting_join_url,
    })
}

async fn stop_task(
    http_client: &reqwest::Client,
    access_key_id: &str,
    access_key_secret: &str,
    task_id: &str,
) -> Result<()> {
    let query = map_query([
        ("operation", "stop".to_string()),
        ("type", "realtime".to_string()),
    ]);
    let body = json!({ "TaskId": task_id }).to_string();

    let response = send_signed_roa_request(
        http_client,
        access_key_id,
        access_key_secret,
        "PUT",
        "/openapi/tingwu/v2/tasks",
        &query,
        &body,
    )
    .await?;

    if response.status().is_success() {
        Ok(())
    } else {
        let body = response.text().await.unwrap_or_default();
        Err(anyhow!("Aliyun stop task failed: {body}"))
    }
}

async fn send_signed_roa_request(
    http_client: &reqwest::Client,
    access_key_id: &str,
    access_key_secret: &str,
    method: &str,
    path: &str,
    query: &BTreeMap<String, String>,
    body: &str,
) -> Result<reqwest::Response> {
    let accept = "application/json";
    let content_type = "application/json";
    let date = http_date_now();
    let content_md5 = BASE64.encode(md5::compute(body.as_bytes()).0);
    let nonce = Uuid::new_v4().to_string();

    let mut acs_headers = BTreeMap::new();
    acs_headers.insert(
        "x-acs-signature-method".to_string(),
        "HMAC-SHA1".to_string(),
    );
    acs_headers.insert("x-acs-signature-nonce".to_string(), nonce);
    acs_headers.insert("x-acs-signature-version".to_string(), "1.0".to_string());
    acs_headers.insert("x-acs-version".to_string(), "2023-09-30".to_string());

    let canonicalized_headers = canonicalized_headers(&acs_headers);
    let canonicalized_resource = canonicalized_resource(path, query);
    let string_to_sign = format!(
        "{method}\n{accept}\n{content_md5}\n{content_type}\n{date}\n{canonicalized_headers}{canonicalized_resource}"
    );

    let signature = sign_hmac_sha1(access_key_secret, &string_to_sign)?;
    let authorization = format!("acs {access_key_id}:{signature}");

    let url = format!("https://tingwu.cn-beijing.aliyuncs.com{canonicalized_resource}");
    let mut request = http_client
        .request(
            reqwest::Method::from_bytes(method.as_bytes()).context("invalid request method")?,
            url,
        )
        .header("accept", accept)
        .header("content-type", content_type)
        .header("content-md5", content_md5)
        .header("date", date)
        .header("authorization", authorization)
        .body(body.to_string());

    for (name, value) in &acs_headers {
        request = request.header(name, value);
    }

    request
        .send()
        .await
        .context("failed to send signed ROA request")
}

fn build_start_transcription_payload(app_key: &str, task_id: &str, sample_rate: u32) -> String {
    json!({
        "header": {
            "appkey": app_key,
            "message_id": Uuid::new_v4().to_string(),
            "task_id": task_id,
            "namespace": "SpeechTranscriber",
            "name": "StartTranscription"
        },
        "payload": {
            "format": "pcm",
            "sample_rate": sample_rate,
            "enable_intermediate_result": true,
            "enable_inverse_text_normalization": true
        }
    })
    .to_string()
}

fn build_stop_transcription_payload(app_key: &str, task_id: &str) -> String {
    json!({
        "header": {
            "appkey": app_key,
            "message_id": Uuid::new_v4().to_string(),
            "task_id": task_id,
            "namespace": "SpeechTranscriber",
            "name": "StopTranscription"
        },
        "payload": {}
    })
    .to_string()
}

fn map_query<const N: usize>(pairs: [(&str, String); N]) -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    for (key, value) in pairs {
        map.insert(key.to_string(), value);
    }
    map
}

fn canonicalized_headers(headers: &BTreeMap<String, String>) -> String {
    let mut out = String::new();
    for (key, value) in headers {
        out.push_str(key);
        out.push(':');
        out.push_str(value);
        out.push('\n');
    }
    out
}

fn canonicalized_resource(path: &str, query: &BTreeMap<String, String>) -> String {
    if query.is_empty() {
        return path.to_string();
    }

    let mut parts = Vec::with_capacity(query.len());
    for (key, value) in query {
        parts.push(format!("{key}={value}"));
    }
    format!("{path}?{}", parts.join("&"))
}

fn sign_hmac_sha1(secret: &str, payload: &str) -> Result<String> {
    let mut mac = Hmac::<Sha1>::new_from_slice(secret.as_bytes())
        .context("failed to create HMAC-SHA1 signer")?;
    mac.update(payload.as_bytes());
    let bytes = mac.finalize().into_bytes();
    Ok(BASE64.encode(bytes))
}

fn http_date_now() -> String {
    chrono::Utc::now()
        .format("%a, %d %b %Y %H:%M:%S GMT")
        .to_string()
}
