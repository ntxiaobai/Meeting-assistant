export type ProviderKind = "aliyun" | "deepgram" | "claude" | "gemini" | "openai" | "custom_llm";
export type ProviderSecretField = "api_key" | "access_key_id" | "access_key_secret" | "app_key";
export type AsrProvider = "aliyun" | "deepgram";
export type AttachmentFileType = "txt" | "pdf";
export type SpeakerRole = "me" | "other" | "unknown";
export type SegmentSource = "microphone" | "system";
export type TranslationSource = "asr" | "llm";
export type SessionLifecycleState = "starting" | "running" | "stopped" | "error";
export type LocaleCode = "zh-CN" | "en-US";
export type ThemeMode = "light" | "dark" | "system";
export type PlatformStyle = "macos" | "windows" | "linux";
export type LlmProviderKind = "anthropic" | "openai" | "custom";
export type LlmApiFormat = "anthropic" | "openai";

export interface LlmSettings {
  provider: LlmProviderKind;
  model: string;
  baseUrl?: string;
  apiFormat: LlmApiFormat;
}

export interface ProviderStatus {
  aliyun: boolean;
  deepgram: boolean;
  claude: boolean;
  gemini: boolean;
  openai: boolean;
  customLlm: boolean;
}

export interface AudioDeviceInfo {
  id: string;
  name: string;
  isDefault: boolean;
}

export interface AudioDeviceList {
  microphones: AudioDeviceInfo[];
  systemLoopbackAvailable: boolean;
  note?: string;
}

export interface WindowModeState {
  alwaysOnTop: boolean;
  transparent: boolean;
  undecorated: boolean;
  clickThrough: boolean;
  opacity: number;
}

export interface LiveOverlayLayout {
  opacity: number;
  x: number;
  y: number;
  width: number;
  height: number;
  anchorScreen?: string;
}

export interface WindowAvailability {
  liveOverlay: boolean;
}

export interface BootstrapState {
  providerStatus: ProviderStatus;
  audioDevices: AudioDeviceList;
  teleprompter: WindowModeState;
  liveOverlayLayout: LiveOverlayLayout;
  platform: string;
  platformStyle: PlatformStyle;
  locale: LocaleCode;
  themeMode: ThemeMode;
  onboardingCompleted: boolean;
  llmSettings: LlmSettings;
  windows: WindowAvailability;
}

export interface UserPreferences {
  locale: LocaleCode;
  themeMode: ThemeMode;
  onboardingCompleted: boolean;
  llmSettings: LlmSettings;
  teleprompterMode: WindowModeState;
  liveOverlayLayout: LiveOverlayLayout;
}

export interface SaveUserPreferencesInput {
  locale: LocaleCode;
  themeMode: ThemeMode;
  onboardingCompleted: boolean;
}

export interface AttachmentRecord {
  id: string;
  profileId: string;
  filePath: string;
  fileType: AttachmentFileType;
  extractedText: string;
  createdAt: string;
}

export interface MeetingProfile {
  id: string;
  name: string;
  meetingType: string;
  domain: string;
  language: string;
  selfIntro: string;
  contextNotes: string;
  attachments: AttachmentRecord[];
  createdAt: string;
  updatedAt: string;
}

export interface MeetingProfileUpsert {
  id?: string;
  name: string;
  meetingType: string;
  domain: string;
  language: string;
  selfIntro: string;
  contextNotes: string;
}

export interface ExtractAttachmentInput {
  profileId: string;
  filePath: string;
  fileType: AttachmentFileType;
}

export interface SaveProviderKeyInput {
  provider: ProviderKind;
  apiKey: string;
}

export interface SaveProviderSecretInput {
  provider: ProviderKind;
  field: ProviderSecretField;
  value: string;
}

export interface StartSessionInput {
  profileId: string;
  microphoneId?: string;
  sourceLanguage: string;
  targetLanguage: string;
  asrProvider?: AsrProvider;
}

export interface SessionStartResult {
  sessionId: string;
  degradedMode: boolean;
  message: string;
  provider: AsrProvider;
}

export interface TeleprompterModeInput {
  alwaysOnTop: boolean;
  transparent: boolean;
  undecorated: boolean;
  clickThrough: boolean;
  opacity: number;
}

export interface SaveLiveOverlayLayoutInput {
  opacity: number;
  x: number;
  y: number;
  width: number;
  height: number;
  anchorScreen?: string;
}

export interface SessionStateEvent {
  sessionId: string;
  state: SessionLifecycleState;
  message: string;
  degradedMode: boolean;
  provider: AsrProvider;
}

export interface TranscriptSegmentEvent {
  id: string;
  sessionId: string;
  speaker: SpeakerRole;
  text: string;
  isFinal: boolean;
  timestampMs: number;
  provider: AsrProvider;
  source: SegmentSource;
}

export interface TranslationSegmentEvent {
  id: string;
  transcriptId: string;
  text: string;
  isFinal: boolean;
  timestampMs: number;
  provider: AsrProvider;
  source: TranslationSource;
}

export interface HintDeltaEvent {
  id: string;
  sessionId: string;
  delta: string;
  done: boolean;
  source: string;
}

export interface RuntimeErrorEvent {
  code: string;
  message: string;
  recoverable: boolean;
  provider?: AsrProvider;
  source: string;
}

export const Events = {
  SESSION_STATE: "session://state",
  TRANSCRIPT_SEGMENT: "transcript://segment",
  TRANSLATION_SEGMENT: "translation://segment",
  HINT_DELTA: "hint://delta",
  RUNTIME_ERROR: "runtime://error",
  OVERLAY_MODE: "overlay://mode",
  OVERLAY_LAYOUT: "overlay://layout",
} as const;
