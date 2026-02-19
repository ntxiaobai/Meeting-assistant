import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type {
  AttachmentRecord,
  BootstrapState,
  ExtractAttachmentInput,
  HintDeltaEvent,
  MeetingProfile,
  MeetingProfileUpsert,
  RuntimeErrorEvent,
  SaveProviderKeyInput,
  SaveLiveOverlayLayoutInput,
  LlmSettings,
  SaveUserPreferencesInput,
  SaveProviderSecretInput,
  SessionStartResult,
  SessionStateEvent,
  StartSessionInput,
  TeleprompterModeInput,
  TranscriptSegmentEvent,
  TranslationSegmentEvent,
  UserPreferences,
  LiveOverlayLayout,
  WindowAvailability,
  WindowModeState,
} from "../types/ipc-types";

async function invokeTyped<T>(command: string, args?: Record<string, unknown>): Promise<T> {
  return invoke<T>(command, args);
}

export async function getBootstrapState(): Promise<BootstrapState> {
  return invokeTyped<BootstrapState>("get_bootstrap_state");
}

export async function getUserPreferences(): Promise<UserPreferences> {
  return invokeTyped<UserPreferences>("get_user_preferences");
}

export async function saveUserPreferences(input: SaveUserPreferencesInput): Promise<UserPreferences> {
  return invokeTyped<UserPreferences>("save_user_preferences", { input });
}

export async function getLlmSettings(): Promise<LlmSettings> {
  return invokeTyped<LlmSettings>("get_llm_settings");
}

export async function saveLlmSettings(input: LlmSettings): Promise<LlmSettings> {
  return invokeTyped<LlmSettings>("save_llm_settings", { input });
}

export async function listMeetingProfiles(): Promise<MeetingProfile[]> {
  return invokeTyped<MeetingProfile[]>("list_meeting_profiles");
}

export async function saveMeetingProfile(input: MeetingProfileUpsert): Promise<MeetingProfile> {
  return invokeTyped<MeetingProfile>("save_meeting_profile", { input });
}

export async function deleteMeetingProfile(id: string): Promise<void> {
  return invokeTyped<void>("delete_meeting_profile", { input: { id } });
}

export async function extractAttachmentText(input: ExtractAttachmentInput): Promise<AttachmentRecord> {
  return invokeTyped<AttachmentRecord>("extract_attachment_text", { input });
}

export async function saveProviderKey(input: SaveProviderKeyInput): Promise<void> {
  return invokeTyped<void>("save_provider_key", { input });
}

export async function saveProviderSecret(input: SaveProviderSecretInput): Promise<void> {
  return invokeTyped<void>("save_provider_secret", { input });
}

export async function startLiveSession(input: StartSessionInput): Promise<SessionStartResult> {
  return invokeTyped<SessionStartResult>("start_live_session", { input });
}

export async function stopLiveSession(): Promise<void> {
  return invokeTyped<void>("stop_live_session");
}

export async function showLiveOverlay(): Promise<WindowAvailability> {
  return invokeTyped<WindowAvailability>("show_live_overlay");
}

export async function hideLiveOverlay(): Promise<WindowAvailability> {
  return invokeTyped<WindowAvailability>("hide_live_overlay");
}

export async function setLiveOverlayMode(input: TeleprompterModeInput): Promise<WindowModeState> {
  return invokeTyped<WindowModeState>("set_live_overlay_mode", { input });
}

export async function setTeleprompterMode(input: TeleprompterModeInput): Promise<WindowModeState> {
  return invokeTyped<WindowModeState>("set_teleprompter_mode", { input });
}

export async function getLiveOverlayLayout(): Promise<LiveOverlayLayout> {
  return invokeTyped<LiveOverlayLayout>("get_live_overlay_layout");
}

export async function saveLiveOverlayLayout(
  input: SaveLiveOverlayLayoutInput,
): Promise<LiveOverlayLayout> {
  return invokeTyped<LiveOverlayLayout>("save_live_overlay_layout", { input });
}

export async function startLiveOverlayDrag(): Promise<void> {
  return invokeTyped<void>("start_live_overlay_drag");
}

type EventPayloadMap = {
  "session://state": SessionStateEvent;
  "transcript://segment": TranscriptSegmentEvent;
  "translation://segment": TranslationSegmentEvent;
  "hint://delta": HintDeltaEvent;
  "runtime://error": RuntimeErrorEvent;
  "overlay://mode": WindowModeState;
  "overlay://layout": LiveOverlayLayout;
};

export async function onTypedEvent<K extends keyof EventPayloadMap>(
  eventName: K,
  handler: (payload: EventPayloadMap[K]) => void,
): Promise<() => void> {
  return listen<EventPayloadMap[K]>(eventName, (event) => {
    handler(event.payload);
  });
}

export type { EventPayloadMap };
