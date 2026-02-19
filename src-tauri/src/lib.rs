mod asr;
mod attachment;
mod audio;
mod events;
mod llm;
mod models;
mod secrets;
mod session;
mod storage;
mod window;

use chrono::{SecondsFormat, Utc};
use models::{
    AttachmentRecord, BootstrapState, DeleteProfileInput, ExtractAttachmentInput,
    LiveOverlayLayout, LiveOverlayModeInput, LiveOverlayModeState, LlmApiFormat, LlmProviderKind,
    LlmSettings, MeetingProfile, MeetingProfileUpsert, PlatformStyle, ProviderKind,
    ProviderSecretField, SaveLiveOverlayLayoutInput, SaveLlmSettingsInput, SaveProviderKeyInput,
    SaveProviderSecretInput, SaveUserPreferencesInput, SessionStartResult, StartSessionInput,
    TeleprompterModeInput, UserPreferences, WindowAvailability, WindowModeState,
};
use session::live_session::{SessionManager, StartSessionContext};
use storage::StorageService;
use tauri::{
    AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, Position, Size, State,
    WebviewUrl, WebviewWindowBuilder,
};
use uuid::Uuid;

struct AppState {
    storage: StorageService,
    secrets: secrets::SecretService,
    session_manager: SessionManager,
    http_client: reqwest::Client,
    live_overlay_mode: std::sync::Arc<tokio::sync::Mutex<WindowModeState>>,
    live_overlay_layout: std::sync::Arc<tokio::sync::Mutex<LiveOverlayLayout>>,
}

#[tauri::command]
async fn get_bootstrap_state(
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<BootstrapState, String> {
    let audio_devices = audio::list_audio_devices().map_err(to_string_error)?;
    let provider_status = state.secrets.provider_status();
    let live_overlay_mode = state.live_overlay_mode.lock().await.clone();
    let live_overlay_layout = state.live_overlay_layout.lock().await.clone();
    let preferences = state
        .storage
        .get_user_preferences()
        .map_err(to_string_error)?;

    let platform = std::env::consts::OS.to_string();
    let platform_style = PlatformStyle::from_os_name(&platform);
    let live_overlay_visible = app
        .get_webview_window("live_overlay")
        .and_then(|window| window.is_visible().ok())
        .unwrap_or(false);

    Ok(BootstrapState {
        provider_status,
        audio_devices,
        teleprompter: live_overlay_mode,
        live_overlay_layout,
        platform,
        platform_style,
        locale: preferences.locale,
        theme_mode: preferences.theme_mode,
        onboarding_completed: preferences.onboarding_completed,
        llm_settings: preferences.llm_settings,
        windows: WindowAvailability {
            live_overlay: live_overlay_visible,
        },
    })
}

#[tauri::command]
async fn get_user_preferences(state: State<'_, AppState>) -> Result<UserPreferences, String> {
    state
        .storage
        .get_user_preferences()
        .map_err(to_string_error)
}

#[tauri::command]
async fn save_user_preferences(
    state: State<'_, AppState>,
    input: SaveUserPreferencesInput,
) -> Result<UserPreferences, String> {
    let current = state
        .storage
        .get_user_preferences()
        .map_err(to_string_error)?;

    state
        .storage
        .save_user_preferences(UserPreferences {
            locale: input.locale,
            theme_mode: input.theme_mode,
            onboarding_completed: input.onboarding_completed,
            llm_settings: current.llm_settings,
            teleprompter_mode: current.teleprompter_mode,
            live_overlay_layout: current.live_overlay_layout,
        })
        .map_err(to_string_error)
}

#[tauri::command]
async fn get_llm_settings(state: State<'_, AppState>) -> Result<LlmSettings, String> {
    state
        .storage
        .get_user_preferences()
        .map(|prefs| prefs.llm_settings)
        .map_err(to_string_error)
}

#[tauri::command]
async fn save_llm_settings(
    state: State<'_, AppState>,
    input: SaveLlmSettingsInput,
) -> Result<LlmSettings, String> {
    let model = input.model.trim();
    if model.is_empty() {
        return Err("llm model cannot be empty".to_string());
    }

    if input.provider == LlmProviderKind::Custom {
        let base_url = input.base_url.as_deref().unwrap_or_default().trim();
        if base_url.is_empty() {
            return Err("custom llm baseUrl is required".to_string());
        }
    }

    let mut current = state
        .storage
        .get_user_preferences()
        .map_err(to_string_error)?;
    current.llm_settings = LlmSettings {
        provider: input.provider,
        model: model.to_string(),
        base_url: input.base_url.map(|value| value.trim().to_string()),
        api_format: input.api_format,
    };

    state
        .storage
        .save_user_preferences(current.clone())
        .map_err(to_string_error)?;
    Ok(current.llm_settings)
}

#[tauri::command]
async fn list_meeting_profiles(state: State<'_, AppState>) -> Result<Vec<MeetingProfile>, String> {
    state.storage.list_profiles().map_err(to_string_error)
}

#[tauri::command]
async fn save_meeting_profile(
    state: State<'_, AppState>,
    input: MeetingProfileUpsert,
) -> Result<MeetingProfile, String> {
    state.storage.save_profile(input).map_err(to_string_error)
}

#[tauri::command]
async fn delete_meeting_profile(
    state: State<'_, AppState>,
    input: DeleteProfileInput,
) -> Result<(), String> {
    state
        .storage
        .delete_profile(&input.id)
        .map_err(to_string_error)
}

#[tauri::command]
async fn extract_attachment_text(
    state: State<'_, AppState>,
    input: ExtractAttachmentInput,
) -> Result<AttachmentRecord, String> {
    let extracted_text =
        attachment::extract_text(&input.file_path, &input.file_type).map_err(to_string_error)?;

    let attachment = AttachmentRecord {
        id: Uuid::new_v4().to_string(),
        profile_id: input.profile_id,
        file_path: input.file_path,
        file_type: input.file_type,
        extracted_text,
        created_at: now_iso(),
    };

    state
        .storage
        .add_attachment(attachment)
        .map_err(to_string_error)
}

#[tauri::command]
async fn save_provider_key(
    state: State<'_, AppState>,
    input: SaveProviderKeyInput,
) -> Result<(), String> {
    let api_key = input.api_key.trim();
    if api_key.is_empty() {
        return Err("apiKey cannot be empty".to_string());
    }

    state
        .secrets
        .save_provider_key(input.provider, api_key)
        .map_err(to_string_error)
}

#[tauri::command]
async fn save_provider_secret(
    state: State<'_, AppState>,
    input: SaveProviderSecretInput,
) -> Result<(), String> {
    let value = input.value.trim();
    if value.is_empty() {
        return Err("provider secret value cannot be empty".to_string());
    }

    state
        .secrets
        .save_provider_secret(input.provider, input.field, value)
        .map_err(to_string_error)
}

#[tauri::command]
async fn list_audio_devices(state: State<'_, AppState>) -> Result<models::AudioDeviceList, String> {
    let _ = state;
    audio::list_audio_devices().map_err(to_string_error)
}

#[tauri::command]
async fn start_live_session(
    app: AppHandle,
    state: State<'_, AppState>,
    input: StartSessionInput,
) -> Result<SessionStartResult, String> {
    let Some(profile) = state
        .storage
        .find_profile(&input.profile_id)
        .map_err(to_string_error)?
    else {
        return Err(format!("meeting profile not found: {}", input.profile_id));
    };

    let deepgram_key = state
        .secrets
        .get_provider_key(ProviderKind::Deepgram)
        .map_err(to_string_error)?;
    let aliyun_secrets = state
        .secrets
        .get_aliyun_secrets()
        .map_err(to_string_error)?;

    let preferences = state
        .storage
        .get_user_preferences()
        .map_err(to_string_error)?;
    let llm_service =
        build_llm_service(&state, &preferences.llm_settings).map_err(to_string_error)?;

    let context = StartSessionContext {
        app,
        input,
        profile,
        deepgram_key,
        aliyun_secrets,
        llm_service,
        http_client: state.http_client.clone(),
    };

    state
        .session_manager
        .start(context)
        .await
        .map_err(to_string_error)
}

#[tauri::command]
async fn stop_live_session(app: AppHandle, state: State<'_, AppState>) -> Result<(), String> {
    state
        .session_manager
        .stop(&app)
        .await
        .map_err(to_string_error)
}

#[tauri::command]
async fn show_live_overlay(
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<WindowAvailability, String> {
    let mode = state.live_overlay_mode.lock().await.clone();
    let window = ensure_live_overlay_window(&app, &mode).map_err(to_string_error)?;
    let layout = state.live_overlay_layout.lock().await.clone();
    let corrected = apply_overlay_layout(&window, &layout).map_err(to_string_error)?;
    if corrected != layout {
        {
            let mut guard = state.live_overlay_layout.lock().await;
            *guard = corrected.clone();
        }
        persist_live_overlay_layout(&state.storage, corrected.clone()).map_err(to_string_error)?;
        emit_overlay_layout_changed(&app, &corrected);
    }
    window.show().map_err(to_string_error)?;
    window.set_focus().map_err(to_string_error)?;
    Ok(WindowAvailability { live_overlay: true })
}

#[tauri::command]
async fn hide_live_overlay(app: AppHandle) -> Result<WindowAvailability, String> {
    if let Some(window) = app.get_webview_window("live_overlay") {
        window.hide().map_err(to_string_error)?;
    }

    Ok(WindowAvailability {
        live_overlay: false,
    })
}

#[tauri::command]
async fn set_live_overlay_mode(
    app: AppHandle,
    state: State<'_, AppState>,
    input: LiveOverlayModeInput,
) -> Result<LiveOverlayModeState, String> {
    let _ = ensure_live_overlay_window(&app, &state.live_overlay_mode.lock().await.clone())
        .map_err(to_string_error)?;
    let mode =
        window::mode::apply_window_mode(&app, "live_overlay", input).map_err(to_string_error)?;
    {
        let mut guard = state.live_overlay_mode.lock().await;
        *guard = mode.clone();
    }

    let next_layout = {
        let mut layout_guard = state.live_overlay_layout.lock().await;
        layout_guard.opacity = mode.opacity;
        let next = layout_guard.clone();
        persist_live_overlay_layout(&state.storage, next.clone()).map_err(to_string_error)?;
        next
    };
    persist_live_overlay_mode(&state.storage, mode.clone()).map_err(to_string_error)?;
    emit_overlay_mode_changed(&app, &mode);
    emit_overlay_layout_changed(&app, &next_layout);
    Ok(mode)
}

#[tauri::command]
async fn set_teleprompter_mode(
    app: AppHandle,
    state: State<'_, AppState>,
    input: TeleprompterModeInput,
) -> Result<WindowModeState, String> {
    set_live_overlay_mode(app, state, input).await
}

#[tauri::command]
async fn get_live_overlay_layout(
    state: State<'_, AppState>,
) -> Result<LiveOverlayLayout, String> {
    Ok(state.live_overlay_layout.lock().await.clone())
}

#[tauri::command]
async fn save_live_overlay_layout(
    app: AppHandle,
    state: State<'_, AppState>,
    input: SaveLiveOverlayLayoutInput,
) -> Result<LiveOverlayLayout, String> {
    let layout = LiveOverlayLayout::from(input);
    let corrected = if let Some(window) = app.get_webview_window("live_overlay") {
        apply_overlay_layout(&window, &layout).map_err(to_string_error)?
    } else {
        layout
    };

    {
        let mut guard = state.live_overlay_layout.lock().await;
        *guard = corrected.clone();
    }
    persist_live_overlay_layout(&state.storage, corrected.clone()).map_err(to_string_error)?;

    {
        let mut mode = state.live_overlay_mode.lock().await;
        mode.opacity = corrected.opacity;
        persist_live_overlay_mode(&state.storage, mode.clone()).map_err(to_string_error)?;
    }

    emit_overlay_layout_changed(&app, &corrected);
    Ok(corrected)
}

#[tauri::command]
async fn start_live_overlay_drag(app: AppHandle) -> Result<(), String> {
    let window = app
        .get_webview_window("live_overlay")
        .ok_or_else(|| "window not found: live_overlay".to_string())?;
    window.start_dragging().map_err(to_string_error)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let data_dir = resolve_data_dir();
    let storage = StorageService::new(data_dir);
    if let Err(error) = storage.migrate_if_needed() {
        eprintln!("storage migration failed: {error}");
    }
    let preferences = storage.get_user_preferences().unwrap_or_default();

    let app_state = AppState {
        storage,
        secrets: secrets::SecretService::new("com.liuchang.meeting-assistant"),
        session_manager: SessionManager::new(),
        http_client: reqwest::Client::new(),
        live_overlay_mode: std::sync::Arc::new(tokio::sync::Mutex::new(
            preferences.teleprompter_mode,
        )),
        live_overlay_layout: std::sync::Arc::new(tokio::sync::Mutex::new(
            preferences.live_overlay_layout,
        )),
    };

    tauri::Builder::default()
        .manage(app_state)
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            get_bootstrap_state,
            get_user_preferences,
            save_user_preferences,
            get_llm_settings,
            save_llm_settings,
            list_meeting_profiles,
            save_meeting_profile,
            delete_meeting_profile,
            extract_attachment_text,
            save_provider_key,
            save_provider_secret,
            list_audio_devices,
            start_live_session,
            stop_live_session,
            show_live_overlay,
            hide_live_overlay,
            set_live_overlay_mode,
            set_teleprompter_mode,
            get_live_overlay_layout,
            save_live_overlay_layout,
            start_live_overlay_drag
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn ensure_live_overlay_window(
    app: &AppHandle,
    mode: &WindowModeState,
) -> Result<tauri::WebviewWindow, anyhow::Error> {
    if let Some(window) = app.get_webview_window("live_overlay") {
        return Ok(window);
    }

    let window = WebviewWindowBuilder::new(
        app,
        "live_overlay",
        WebviewUrl::App("index.html?window=live_overlay".into()),
    )
    .title("Meeting Assistant Live Overlay")
    .transparent(mode.transparent)
    .decorations(!mode.undecorated)
    .always_on_top(mode.always_on_top)
    .resizable(true)
    .visible(false)
    .build()
    .map_err(|error| anyhow::anyhow!("failed to create live overlay window: {error}"))?;

    if mode.click_through {
        let _ = window.set_ignore_cursor_events(false);
    }

    Ok(window)
}

fn apply_overlay_layout(
    window: &tauri::WebviewWindow,
    layout: &LiveOverlayLayout,
) -> Result<LiveOverlayLayout, anyhow::Error> {
    let corrected = normalize_overlay_layout(window, layout)?;

    window
        .set_size(Size::Physical(PhysicalSize::new(
            corrected.width,
            corrected.height,
        )))
        .map_err(|error| anyhow::anyhow!("failed to set overlay size: {error}"))?;
    window
        .set_position(Position::Physical(PhysicalPosition::new(
            corrected.x,
            corrected.y,
        )))
        .map_err(|error| anyhow::anyhow!("failed to set overlay position: {error}"))?;

    Ok(corrected)
}

fn normalize_overlay_layout(
    window: &tauri::WebviewWindow,
    layout: &LiveOverlayLayout,
) -> Result<LiveOverlayLayout, anyhow::Error> {
    let mut next = layout.clone().clamp();
    let monitors = window
        .available_monitors()
        .map_err(|error| anyhow::anyhow!("failed to query displays: {error}"))?;

    let selected_monitor = layout
        .anchor_screen
        .as_ref()
        .and_then(|name| {
            monitors
                .iter()
                .find(|monitor| monitor.name().map(|value| value == name).unwrap_or(false))
        })
        .cloned()
        .or_else(|| window.current_monitor().ok().flatten())
        .or_else(|| monitors.first().cloned());

    let Some(monitor) = selected_monitor else {
        return Ok(next);
    };

    let work_area = monitor.work_area();
    let min_x = work_area.position.x;
    let min_y = work_area.position.y;
    let max_width = work_area.size.width.max(560);
    let max_height = work_area.size.height.max(260);

    next.width = next.width.clamp(560, max_width);
    next.height = next.height.clamp(260, max_height);

    let max_x = min_x + work_area.size.width as i32 - next.width as i32;
    let max_y = min_y + work_area.size.height as i32 - next.height as i32;

    next.x = next.x.clamp(min_x, max_x.max(min_x));
    next.y = next.y.clamp(min_y, max_y.max(min_y));
    next.anchor_screen = monitor.name().cloned();
    Ok(next)
}

fn persist_live_overlay_mode(storage: &StorageService, mode: WindowModeState) -> anyhow::Result<()> {
    let mut preferences = storage.get_user_preferences()?;
    preferences.teleprompter_mode = mode;
    storage.save_user_preferences(preferences)?;
    Ok(())
}

fn persist_live_overlay_layout(
    storage: &StorageService,
    layout: LiveOverlayLayout,
) -> anyhow::Result<()> {
    let mut preferences = storage.get_user_preferences()?;
    preferences.live_overlay_layout = layout;
    storage.save_user_preferences(preferences)?;
    Ok(())
}

fn emit_overlay_mode_changed(app: &AppHandle, mode: &WindowModeState) {
    let _ = app.emit(events::EVENT_OVERLAY_MODE_CHANGED, mode);
}

fn emit_overlay_layout_changed(app: &AppHandle, layout: &LiveOverlayLayout) {
    let _ = app.emit(events::EVENT_OVERLAY_LAYOUT_CHANGED, layout);
}

fn resolve_data_dir() -> std::path::PathBuf {
    if let Some(dir) = dirs::data_local_dir() {
        return dir.join("meeting-assistant");
    }

    std::env::current_dir()
        .unwrap_or_else(|_| std::path::PathBuf::from("."))
        .join(".meeting-assistant")
}

fn now_iso() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true)
}

fn to_string_error(error: impl std::fmt::Display) -> String {
    error.to_string()
}

fn build_llm_service(
    state: &AppState,
    settings: &LlmSettings,
) -> anyhow::Result<Option<llm::LlmService>> {
    let key_provider = match settings.provider {
        LlmProviderKind::Anthropic => ProviderKind::Claude,
        LlmProviderKind::Openai => ProviderKind::Openai,
        LlmProviderKind::Custom => ProviderKind::CustomLlm,
    };

    let api_key = match state.secrets.get_provider_key(key_provider)? {
        Some(value) => value,
        None => return Ok(None),
    };

    let provider: std::sync::Arc<dyn llm::LlmProvider> = match settings.provider {
        LlmProviderKind::Anthropic => {
            std::sync::Arc::new(llm::claude_client::ClaudeClient::with_config(
                state.http_client.clone(),
                api_key,
                settings
                    .base_url
                    .clone()
                    .unwrap_or_else(|| "https://api.anthropic.com/v1".to_string()),
                settings.model.clone(),
            ))
        }
        LlmProviderKind::Openai => {
            std::sync::Arc::new(llm::openai_client::OpenAiCompatClient::with_config(
                state.http_client.clone(),
                api_key,
                settings
                    .base_url
                    .clone()
                    .unwrap_or_else(|| "https://api.openai.com/v1".to_string()),
                settings.model.clone(),
            ))
        }
        LlmProviderKind::Custom => match settings.api_format {
            LlmApiFormat::Anthropic => {
                std::sync::Arc::new(llm::claude_client::ClaudeClient::with_config(
                    state.http_client.clone(),
                    api_key,
                    settings
                        .base_url
                        .clone()
                        .unwrap_or_else(|| "https://api.anthropic.com/v1".to_string()),
                    settings.model.clone(),
                ))
            }
            LlmApiFormat::Openai => {
                std::sync::Arc::new(llm::openai_client::OpenAiCompatClient::with_config(
                    state.http_client.clone(),
                    api_key,
                    settings
                        .base_url
                        .clone()
                        .unwrap_or_else(|| "https://api.openai.com/v1".to_string()),
                    settings.model.clone(),
                ))
            }
        },
    };

    Ok(Some(llm::LlmService::new(provider)))
}

#[allow(dead_code)]
fn _ensure_provider_key_semantics(provider: ProviderKind, field: ProviderSecretField) -> bool {
    matches!(
        (provider, field),
        (ProviderKind::Aliyun, ProviderSecretField::AccessKeyId)
            | (ProviderKind::Aliyun, ProviderSecretField::AccessKeySecret)
            | (ProviderKind::Aliyun, ProviderSecretField::AppKey)
            | (_, ProviderSecretField::ApiKey)
    )
}
