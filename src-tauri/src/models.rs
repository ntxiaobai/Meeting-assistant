use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BootstrapState {
    pub provider_status: ProviderStatus,
    pub audio_devices: AudioDeviceList,
    pub teleprompter: WindowModeState,
    pub live_overlay_layout: LiveOverlayLayout,
    pub platform: String,
    pub platform_style: PlatformStyle,
    pub locale: LocaleCode,
    pub theme_mode: ThemeMode,
    pub onboarding_completed: bool,
    pub llm_settings: LlmSettings,
    pub windows: WindowAvailability,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct WindowAvailability {
    pub live_overlay: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ProviderStatus {
    pub aliyun: bool,
    pub deepgram: bool,
    pub claude: bool,
    pub gemini: bool,
    pub openai: bool,
    pub custom_llm: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserPreferences {
    #[serde(default)]
    pub locale: LocaleCode,
    #[serde(default)]
    pub theme_mode: ThemeMode,
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
            locale: LocaleCode::default(),
            theme_mode: ThemeMode::System,
            onboarding_completed: false,
            llm_settings: LlmSettings::default(),
            teleprompter_mode: WindowModeState::default(),
            live_overlay_layout: LiveOverlayLayout::default(),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Eq, PartialEq)]
pub enum LocaleCode {
    #[serde(rename = "zh-CN")]
    ZhCn,
    #[serde(rename = "en-US")]
    EnUs,
}

impl Default for LocaleCode {
    fn default() -> Self {
        let lang = std::env::var("LANG").unwrap_or_default().to_lowercase();
        if lang.starts_with("zh") {
            Self::ZhCn
        } else {
            Self::EnUs
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ThemeMode {
    Light,
    Dark,
    System,
}

impl Default for ThemeMode {
    fn default() -> Self {
        Self::System
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum LlmProviderKind {
    Anthropic,
    Openai,
    Custom,
}

impl Default for LlmProviderKind {
    fn default() -> Self {
        Self::Anthropic
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum LlmApiFormat {
    Anthropic,
    Openai,
}

impl Default for LlmApiFormat {
    fn default() -> Self {
        Self::Anthropic
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LlmSettings {
    #[serde(default)]
    pub provider: LlmProviderKind,
    #[serde(default = "default_llm_model")]
    pub model: String,
    #[serde(default)]
    pub base_url: Option<String>,
    #[serde(default)]
    pub api_format: LlmApiFormat,
}

impl Default for LlmSettings {
    fn default() -> Self {
        Self {
            provider: LlmProviderKind::Anthropic,
            model: default_llm_model(),
            base_url: None,
            api_format: LlmApiFormat::Anthropic,
        }
    }
}

fn default_llm_model() -> String {
    "claude-3-5-sonnet-latest".to_string()
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum PlatformStyle {
    Macos,
    Windows,
    Linux,
}

impl PlatformStyle {
    pub fn from_os_name(os: &str) -> Self {
        match os {
            "macos" => Self::Macos,
            "windows" => Self::Windows,
            _ => Self::Linux,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveUserPreferencesInput {
    pub locale: LocaleCode,
    pub theme_mode: ThemeMode,
    pub onboarding_completed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveLlmSettingsInput {
    pub provider: LlmProviderKind,
    pub model: String,
    pub base_url: Option<String>,
    pub api_format: LlmApiFormat,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingProfile {
    pub id: String,
    pub name: String,
    pub meeting_type: String,
    pub domain: String,
    pub language: String,
    pub self_intro: String,
    pub context_notes: String,
    pub attachments: Vec<AttachmentRecord>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MeetingProfileUpsert {
    pub id: Option<String>,
    pub name: String,
    pub meeting_type: String,
    pub domain: String,
    pub language: String,
    pub self_intro: String,
    pub context_notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AttachmentRecord {
    pub id: String,
    pub profile_id: String,
    pub file_path: String,
    pub file_type: AttachmentFileType,
    pub extracted_text: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AttachmentFileType {
    Txt,
    Pdf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExtractAttachmentInput {
    pub profile_id: String,
    pub file_path: String,
    pub file_type: AttachmentFileType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteProfileInput {
    pub id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveProviderKeyInput {
    pub provider: ProviderKind,
    pub api_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveProviderSecretInput {
    pub provider: ProviderKind,
    pub field: ProviderSecretField,
    pub value: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ProviderKind {
    Aliyun,
    Deepgram,
    Claude,
    Gemini,
    Openai,
    CustomLlm,
}

impl ProviderKind {
    pub fn as_key(&self) -> &'static str {
        match self {
            Self::Aliyun => "aliyun",
            Self::Deepgram => "deepgram",
            Self::Claude => "claude",
            Self::Gemini => "gemini",
            Self::Openai => "openai",
            Self::CustomLlm => "custom_llm",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ProviderSecretField {
    ApiKey,
    AccessKeyId,
    AccessKeySecret,
    AppKey,
}

impl ProviderSecretField {
    pub fn as_key(&self) -> &'static str {
        match self {
            Self::ApiKey => "api_key",
            Self::AccessKeyId => "access_key_id",
            Self::AccessKeySecret => "access_key_secret",
            Self::AppKey => "app_key",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct AudioDeviceList {
    pub microphones: Vec<AudioDeviceInfo>,
    pub system_loopback_available: bool,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AudioDeviceInfo {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StartSessionInput {
    pub profile_id: String,
    pub microphone_id: Option<String>,
    pub source_language: String,
    pub target_language: String,
    pub asr_provider: Option<AsrProvider>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionStartResult {
    pub session_id: String,
    pub degraded_mode: bool,
    pub message: String,
    pub provider: AsrProvider,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum AsrProvider {
    Aliyun,
    Deepgram,
}

impl Default for AsrProvider {
    fn default() -> Self {
        Self::Aliyun
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionLifecycleState {
    Starting,
    Running,
    Stopped,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionStateEvent {
    pub session_id: String,
    pub state: SessionLifecycleState,
    pub message: String,
    pub degraded_mode: bool,
    pub provider: AsrProvider,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpeakerRole {
    Me,
    Other,
    Unknown,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SegmentSource {
    Microphone,
    System,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum TranslationSource {
    Asr,
    Llm,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptSegmentEvent {
    pub id: String,
    pub session_id: String,
    pub speaker: SpeakerRole,
    pub text: String,
    pub is_final: bool,
    pub timestamp_ms: i64,
    pub provider: AsrProvider,
    pub source: SegmentSource,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TranslationSegmentEvent {
    pub id: String,
    pub transcript_id: String,
    pub text: String,
    pub is_final: bool,
    pub timestamp_ms: i64,
    pub provider: AsrProvider,
    pub source: TranslationSource,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HintDeltaEvent {
    pub id: String,
    pub session_id: String,
    pub delta: String,
    pub done: bool,
    pub source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeErrorEvent {
    pub code: String,
    pub message: String,
    pub recoverable: bool,
    pub provider: Option<AsrProvider>,
    pub source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveOverlayLayout {
    pub opacity: f64,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub anchor_screen: Option<String>,
}

impl LiveOverlayLayout {
    pub fn clamp(mut self) -> Self {
        self.opacity = self.opacity.clamp(0.35, 1.0);
        self.width = self.width.clamp(560, 1920);
        self.height = self.height.clamp(260, 1080);
        self
    }
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
pub struct SaveLiveOverlayLayoutInput {
    pub opacity: f64,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub anchor_screen: Option<String>,
}

impl From<SaveLiveOverlayLayoutInput> for LiveOverlayLayout {
    fn from(value: SaveLiveOverlayLayoutInput) -> Self {
        Self {
            opacity: value.opacity,
            x: value.x,
            y: value.y,
            width: value.width,
            height: value.height,
            anchor_screen: value.anchor_screen,
        }
        .clamp()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TeleprompterModeInput {
    pub always_on_top: bool,
    pub transparent: bool,
    pub undecorated: bool,
    pub click_through: bool,
    pub opacity: f64,
}

pub type LiveOverlayModeInput = TeleprompterModeInput;
pub type LiveOverlayModeState = WindowModeState;

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
