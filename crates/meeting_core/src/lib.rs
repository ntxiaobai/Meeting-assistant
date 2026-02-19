use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

type SharedCallback = Arc<dyn Fn(&str, &Value) + Send + Sync>;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeConfig {
    #[serde(default)]
    pub data_dir: Option<String>,
    #[serde(default)]
    pub platform: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LiveOverlayLayout {
    pub opacity: f64,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub anchor_screen: Option<String>,
}

impl Default for LiveOverlayLayout {
    fn default() -> Self {
        Self {
            opacity: 0.86,
            x: 980,
            y: 110,
            width: 920,
            height: 480,
            anchor_screen: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowModeState {
    pub always_on_top: bool,
    pub transparent: bool,
    pub undecorated: bool,
    pub click_through: bool,
    pub opacity: f64,
}

impl Default for WindowModeState {
    fn default() -> Self {
        Self {
            always_on_top: true,
            transparent: true,
            undecorated: true,
            click_through: false,
            opacity: 0.86,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LlmSettings {
    #[serde(default = "default_provider")]
    pub provider: String,
    #[serde(default = "default_model")]
    pub model: String,
    #[serde(default)]
    pub base_url: Option<String>,
    #[serde(default = "default_api_format")]
    pub api_format: String,
}

impl Default for LlmSettings {
    fn default() -> Self {
        Self {
            provider: default_provider(),
            model: default_model(),
            base_url: None,
            api_format: default_api_format(),
        }
    }
}

fn default_provider() -> String {
    "anthropic".to_string()
}

fn default_model() -> String {
    "claude-3-5-sonnet-latest".to_string()
}

fn default_api_format() -> String {
    "anthropic".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserPreferences {
    #[serde(default = "default_locale")]
    pub locale: String,
    #[serde(default = "default_theme_mode")]
    pub theme_mode: String,
    #[serde(default)]
    pub onboarding_completed: bool,
    #[serde(default)]
    pub llm_settings: LlmSettings,
    #[serde(default)]
    pub teleprompter_mode: WindowModeState,
    #[serde(default)]
    pub live_overlay_layout: LiveOverlayLayout,
}

impl Default for UserPreferences {
    fn default() -> Self {
        Self {
            locale: default_locale(),
            theme_mode: default_theme_mode(),
            onboarding_completed: false,
            llm_settings: LlmSettings::default(),
            teleprompter_mode: WindowModeState::default(),
            live_overlay_layout: LiveOverlayLayout::default(),
        }
    }
}

fn default_locale() -> String {
    if std::env::var("LANG")
        .unwrap_or_default()
        .to_lowercase()
        .starts_with("zh")
    {
        "zh-CN".to_string()
    } else {
        "en-US".to_string()
    }
}

fn default_theme_mode() -> String {
    "system".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MeetingProfile {
    pub id: String,
    pub name: String,
    pub meeting_type: String,
    pub domain: String,
    pub language: String,
    pub self_intro: String,
    pub context_notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InvokeRequest {
    pub command: String,
    #[serde(default)]
    pub payload: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InvokeError {
    pub code: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InvokeResponse {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<InvokeError>,
}

struct RuntimeState {
    preferences: UserPreferences,
    profiles: Vec<MeetingProfile>,
    live_overlay_visible: bool,
}

pub struct Runtime {
    config: RuntimeConfig,
    state: Mutex<RuntimeState>,
    callback: Mutex<Option<SharedCallback>>,
}

impl Runtime {
    pub fn new(config_json: &str) -> anyhow::Result<Self> {
        let config = if config_json.trim().is_empty() {
            RuntimeConfig {
                data_dir: None,
                platform: Some(std::env::consts::OS.to_string()),
            }
        } else {
            serde_json::from_str(config_json)?
        };

        Ok(Self {
            config,
            state: Mutex::new(RuntimeState {
                preferences: UserPreferences::default(),
                profiles: Vec::new(),
                live_overlay_visible: false,
            }),
            callback: Mutex::new(None),
        })
    }

    pub fn set_event_callback<F>(&self, callback: F)
    where
        F: Fn(&str, &Value) + Send + Sync + 'static,
    {
        let mut guard = self.callback.lock().expect("callback mutex poisoned");
        *guard = Some(Arc::new(callback));
    }

    pub fn clear_event_callback(&self) {
        let mut guard = self.callback.lock().expect("callback mutex poisoned");
        *guard = None;
    }

    pub fn invoke_json(&self, request_json: &str) -> String {
        let parsed = serde_json::from_str::<InvokeRequest>(request_json);
        let response = match parsed {
            Ok(request) => self.dispatch(request),
            Err(error) => Err(InvokeError {
                code: "invalid_request".to_string(),
                message: format!("invalid request JSON: {error}"),
            }),
        };

        let payload = match response {
            Ok(data) => InvokeResponse {
                ok: true,
                data: Some(data),
                error: None,
            },
            Err(error) => InvokeResponse {
                ok: false,
                data: None,
                error: Some(error),
            },
        };

        serde_json::to_string(&payload).unwrap_or_else(|_| {
            r#"{"ok":false,"error":{"code":"serialization_failure","message":"failed to serialize response"}}"#
                .to_string()
        })
    }

    fn dispatch(&self, request: InvokeRequest) -> Result<Value, InvokeError> {
        match request.command.as_str() {
            "get_bootstrap_state" => self.get_bootstrap_state(),
            "get_user_preferences" => {
                let state = self.state.lock().expect("runtime state mutex poisoned");
                Ok(serde_json::to_value(&state.preferences).unwrap_or_else(|_| json!({})))
            }
            "save_user_preferences" => self.save_user_preferences(request.payload),
            "get_llm_settings" => {
                let state = self.state.lock().expect("runtime state mutex poisoned");
                Ok(serde_json::to_value(&state.preferences.llm_settings).unwrap_or_else(|_| json!({})))
            }
            "save_llm_settings" => self.save_llm_settings(request.payload),
            "list_meeting_profiles" => {
                let state = self.state.lock().expect("runtime state mutex poisoned");
                Ok(serde_json::to_value(&state.profiles).unwrap_or_else(|_| json!([])))
            }
            "save_meeting_profile" => self.save_meeting_profile(request.payload),
            "delete_meeting_profile" => self.delete_meeting_profile(request.payload),
            "extract_attachment_text" => Ok(json!({
                "id": Uuid::new_v4().to_string(),
                "profileId": request.payload.get("profileId").and_then(Value::as_str).unwrap_or_default(),
                "filePath": request.payload.get("filePath").and_then(Value::as_str).unwrap_or_default(),
                "fileType": request.payload.get("fileType").and_then(Value::as_str).unwrap_or("txt"),
                "extractedText": "",
                "createdAt": chrono_like_now(),
            })),
            "save_provider_secret" | "save_provider_key" => Ok(json!({ "saved": true })),
            "list_audio_devices" => Ok(json!({
                "microphones": [],
                "systemLoopbackAvailable": false,
                "note": "FFI core skeleton has no direct audio enumeration yet"
            })),
            "start_live_session" => self.start_live_session(),
            "stop_live_session" => self.stop_live_session(),
            "show_live_overlay" => self.show_live_overlay(),
            "hide_live_overlay" => self.hide_live_overlay(),
            "set_live_overlay_mode" | "set_teleprompter_mode" => {
                self.set_live_overlay_mode(request.payload)
            }
            "get_live_overlay_layout" => {
                let state = self.state.lock().expect("runtime state mutex poisoned");
                Ok(serde_json::to_value(&state.preferences.live_overlay_layout)
                    .unwrap_or_else(|_| json!({})))
            }
            "save_live_overlay_layout" => self.save_live_overlay_layout(request.payload),
            "start_live_overlay_drag" => Ok(json!({ "started": true })),
            _ => Err(InvokeError {
                code: "unknown_command".to_string(),
                message: format!("unsupported command: {}", request.command),
            }),
        }
    }

    fn get_bootstrap_state(&self) -> Result<Value, InvokeError> {
        let state = self.state.lock().expect("runtime state mutex poisoned");
        let platform = self
            .config
            .platform
            .clone()
            .unwrap_or_else(|| std::env::consts::OS.to_string());
        let platform_style = match platform.as_str() {
            "macos" => "macos",
            "windows" => "windows",
            _ => "linux",
        };

        Ok(json!({
            "providerStatus": {
                "aliyun": false,
                "deepgram": false,
                "claude": false,
                "gemini": false,
                "openai": false,
                "customLlm": false
            },
            "audioDevices": {
                "microphones": [],
                "systemLoopbackAvailable": false,
                "note": "FFI runtime skeleton does not enumerate audio devices"
            },
            "teleprompter": state.preferences.teleprompter_mode,
            "liveOverlayLayout": state.preferences.live_overlay_layout,
            "platform": platform,
            "platformStyle": platform_style,
            "locale": state.preferences.locale,
            "themeMode": state.preferences.theme_mode,
            "onboardingCompleted": state.preferences.onboarding_completed,
            "llmSettings": state.preferences.llm_settings,
            "windows": {
                "liveOverlay": state.live_overlay_visible
            }
        }))
    }

    fn save_user_preferences(&self, payload: Value) -> Result<Value, InvokeError> {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct Input {
            locale: String,
            theme_mode: String,
            onboarding_completed: bool,
        }

        let input = serde_json::from_value::<Input>(payload).map_err(invalid_payload)?;
        let mut state = self.state.lock().expect("runtime state mutex poisoned");
        state.preferences.locale = input.locale;
        state.preferences.theme_mode = input.theme_mode;
        state.preferences.onboarding_completed = input.onboarding_completed;
        Ok(serde_json::to_value(&state.preferences).unwrap_or_else(|_| json!({})))
    }

    fn save_llm_settings(&self, payload: Value) -> Result<Value, InvokeError> {
        let parsed = serde_json::from_value::<LlmSettings>(payload).map_err(invalid_payload)?;
        let mut state = self.state.lock().expect("runtime state mutex poisoned");
        state.preferences.llm_settings = parsed.clone();
        Ok(serde_json::to_value(parsed).unwrap_or_else(|_| json!({})))
    }

    fn save_meeting_profile(&self, payload: Value) -> Result<Value, InvokeError> {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct Input {
            id: Option<String>,
            name: String,
            meeting_type: String,
            domain: String,
            language: String,
            self_intro: String,
            context_notes: String,
        }

        let input = serde_json::from_value::<Input>(payload).map_err(invalid_payload)?;
        let mut state = self.state.lock().expect("runtime state mutex poisoned");
        let id = input.id.unwrap_or_else(|| Uuid::new_v4().to_string());
        if let Some(profile) = state.profiles.iter_mut().find(|profile| profile.id == id) {
            profile.name = input.name;
            profile.meeting_type = input.meeting_type;
            profile.domain = input.domain;
            profile.language = input.language;
            profile.self_intro = input.self_intro;
            profile.context_notes = input.context_notes;
            return Ok(serde_json::to_value(profile).unwrap_or_else(|_| json!({})));
        }

        let profile = MeetingProfile {
            id,
            name: input.name,
            meeting_type: input.meeting_type,
            domain: input.domain,
            language: input.language,
            self_intro: input.self_intro,
            context_notes: input.context_notes,
        };
        state.profiles.push(profile.clone());
        Ok(serde_json::to_value(profile).unwrap_or_else(|_| json!({})))
    }

    fn delete_meeting_profile(&self, payload: Value) -> Result<Value, InvokeError> {
        #[derive(Deserialize)]
        struct Input {
            id: String,
        }

        let input = serde_json::from_value::<Input>(payload).map_err(invalid_payload)?;
        let mut state = self.state.lock().expect("runtime state mutex poisoned");
        state.profiles.retain(|profile| profile.id != input.id);
        Ok(json!({ "deleted": true }))
    }

    fn start_live_session(&self) -> Result<Value, InvokeError> {
        let session_id = Uuid::new_v4().to_string();
        self.emit_event(
            "session://state",
            &json!({
                "sessionId": session_id,
                "state": "running",
                "message": "Session started from FFI runtime skeleton",
                "degradedMode": true,
                "provider": "aliyun"
            }),
        );
        Ok(json!({
            "sessionId": session_id,
            "degradedMode": true,
            "message": "FFI runtime skeleton: no real ASR attached yet",
            "provider": "aliyun"
        }))
    }

    fn stop_live_session(&self) -> Result<Value, InvokeError> {
        self.emit_event(
            "session://state",
            &json!({
                "sessionId": "ffi",
                "state": "stopped",
                "message": "Session stopped",
                "degradedMode": true,
                "provider": "aliyun"
            }),
        );
        Ok(json!({ "stopped": true }))
    }

    fn show_live_overlay(&self) -> Result<Value, InvokeError> {
        let mut state = self.state.lock().expect("runtime state mutex poisoned");
        state.live_overlay_visible = true;
        Ok(json!({ "liveOverlay": true }))
    }

    fn hide_live_overlay(&self) -> Result<Value, InvokeError> {
        let mut state = self.state.lock().expect("runtime state mutex poisoned");
        state.live_overlay_visible = false;
        Ok(json!({ "liveOverlay": false }))
    }

    fn set_live_overlay_mode(&self, payload: Value) -> Result<Value, InvokeError> {
        let mut parsed = serde_json::from_value::<WindowModeState>(payload).map_err(invalid_payload)?;
        parsed.opacity = parsed.opacity.clamp(0.35, 1.0);
        let mut state = self.state.lock().expect("runtime state mutex poisoned");
        state.preferences.teleprompter_mode = parsed.clone();
        state.preferences.live_overlay_layout.opacity = parsed.opacity;
        self.emit_event(
            "overlay://mode",
            &serde_json::to_value(&parsed).unwrap_or_else(|_| json!({})),
        );
        Ok(serde_json::to_value(parsed).unwrap_or_else(|_| json!({})))
    }

    fn save_live_overlay_layout(&self, payload: Value) -> Result<Value, InvokeError> {
        let mut parsed =
            serde_json::from_value::<LiveOverlayLayout>(payload).map_err(invalid_payload)?;
        parsed.opacity = parsed.opacity.clamp(0.35, 1.0);
        parsed.width = parsed.width.clamp(560, 1920);
        parsed.height = parsed.height.clamp(260, 1080);
        let mut state = self.state.lock().expect("runtime state mutex poisoned");
        state.preferences.live_overlay_layout = parsed.clone();
        state.preferences.teleprompter_mode.opacity = parsed.opacity;
        self.emit_event(
            "overlay://layout",
            &serde_json::to_value(&parsed).unwrap_or_else(|_| json!({})),
        );
        Ok(serde_json::to_value(parsed).unwrap_or_else(|_| json!({})))
    }

    fn emit_event(&self, event: &str, payload: &Value) {
        let callback = {
            let guard = self.callback.lock().expect("callback mutex poisoned");
            guard.clone()
        };
        if let Some(callback) = callback {
            let event_payload = json!({
                "event": event,
                "payload": payload
            });
            callback(event, &event_payload);
        }
    }
}

fn invalid_payload(error: serde_json::Error) -> InvokeError {
    InvokeError {
        code: "invalid_payload".to_string(),
        message: error.to_string(),
    }
}

fn chrono_like_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or_default();
    format!("{now}")
}

