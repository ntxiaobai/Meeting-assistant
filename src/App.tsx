import { useEffect, useMemo, useState } from "react";
import { Card } from "./components/ui/card";
import { OnboardingWizard } from "./features/onboarding/OnboardingWizard";
import {
  getBootstrapState,
  listMeetingProfiles,
  onTypedEvent,
  saveUserPreferences,
  startLiveSession,
  stopLiveSession,
} from "./lib/tauri-ipc";
import { useLiveStore } from "./features/live/live-store";
import { ProfileManager } from "./features/profiles/ProfileManager";
import { TranscriptList } from "./features/live/TranscriptList";
import { ProviderSettings } from "./features/settings/ProviderSettings";
import { TeleprompterControls } from "./features/teleprompter/TeleprompterControls";
import { HintPanel } from "./features/live/HintPanel";
import { SessionToolbar } from "./features/live/SessionToolbar";
import { useQuestionTrigger } from "./features/live/useQuestionTrigger";
import type {
  AsrProvider,
  BootstrapState,
  LocaleCode,
  MeetingProfile,
  SessionLifecycleState,
  ThemeMode,
} from "./types/ipc-types";
import { Events } from "./types/ipc-types";
import { I18nProvider, useI18n } from "./i18n/provider";
import { Select } from "./components/ui/select";
import { Button } from "./components/ui/button";

function AppContent({ onLocaleResolved }: { onLocaleResolved: (locale: LocaleCode) => void }) {
  const [bootstrap, setBootstrap] = useState<BootstrapState | null>(null);
  const [profiles, setProfiles] = useState<MeetingProfile[]>([]);
  const [selectedProfileId, setSelectedProfileId] = useState("");
  const [selectedMicId, setSelectedMicId] = useState<string | undefined>(undefined);
  const [asrProvider, setAsrProvider] = useState<AsrProvider>("aliyun");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isWorking, setIsWorking] = useState(false);
  const [degradedNote, setDegradedNote] = useState<string | undefined>(undefined);
  const [showWizard, setShowWizard] = useState(false);
  const [locale, setLocale] = useState<LocaleCode>("en-US");
  const [themeMode, setThemeMode] = useState<ThemeMode>("system");

  const live = useLiveStore();
  const { isQuestion } = useQuestionTrigger();
  const { t } = useI18n();

  const selectedProfile = useMemo(
    () => profiles.find((profile) => profile.id === selectedProfileId),
    [profiles, selectedProfileId],
  );

  const latestTranscript = live.transcripts[live.transcripts.length - 1];
  const latestLooksLikeQuestion = latestTranscript
    ? isQuestion(latestTranscript.text)
    : false;

  useEffect(() => {
    void initialize();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    let isMounted = true;
    const unlistenFns: Array<() => void> = [];

    void (async () => {
      try {
        const unlistenSession = await onTypedEvent(Events.SESSION_STATE, (payload) => {
          if (!isMounted) {
            return;
          }
          live.pushSessionState(payload);
        });
        const unlistenTranscript = await onTypedEvent(Events.TRANSCRIPT_SEGMENT, (payload) => {
          if (!isMounted) {
            return;
          }
          live.pushTranscript(payload);
        });
        const unlistenTranslation = await onTypedEvent(Events.TRANSLATION_SEGMENT, (payload) => {
          if (!isMounted) {
            return;
          }
          live.pushTranslation(payload);
        });
        const unlistenHint = await onTypedEvent(Events.HINT_DELTA, (payload) => {
          if (!isMounted) {
            return;
          }
          live.pushHintDelta(payload);
        });
        const unlistenError = await onTypedEvent(Events.RUNTIME_ERROR, (payload) => {
          if (!isMounted) {
            return;
          }
          live.pushRuntimeError(payload);
          setErrorMessage(`[${payload.code}] ${payload.message}`);
        });

        unlistenFns.push(
          unlistenSession,
          unlistenTranscript,
          unlistenTranslation,
          unlistenHint,
          unlistenError,
        );
      } catch (error) {
        setErrorMessage(String(error));
      }
    })();

    return () => {
      isMounted = false;
      for (const off of unlistenFns) {
        off();
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const sync = () => {
      applyRootAppearance(themeMode, bootstrap?.platformStyle ?? "linux", media.matches);
    };
    sync();
    media.addEventListener("change", sync);
    return () => media.removeEventListener("change", sync);
  }, [themeMode, bootstrap?.platformStyle]);

  async function initialize() {
    setIsWorking(true);
    try {
      await Promise.all([refreshBootstrap(), refreshProfiles()]);
    } catch (error) {
      setErrorMessage(String(error));
    } finally {
      setIsWorking(false);
    }
  }

  async function refreshBootstrap() {
    const next = await getBootstrapState();
    setBootstrap(next);
    setLocale(next.locale);
    onLocaleResolved(next.locale);
    setThemeMode(next.themeMode);
    setShowWizard(!next.onboardingCompleted);

    if (!next.audioDevices.systemLoopbackAvailable) {
      setDegradedNote(next.audioDevices.note ?? "System loopback unavailable. Using microphone only.");
    }

    if (!selectedMicId) {
      const defaultMic = next.audioDevices.microphones.find((mic) => mic.isDefault);
      setSelectedMicId(defaultMic?.id);
    }
  }

  async function refreshProfiles() {
    const next = await listMeetingProfiles();
    setProfiles(next);

    const stillSelected = next.some((profile) => profile.id === selectedProfileId);
    if (!stillSelected) {
      setSelectedProfileId(next[0]?.id ?? "");
    }
  }

  function handleError(message: string) {
    setErrorMessage(message);
  }

  async function persistPreferences(next: {
    locale: LocaleCode;
    themeMode: ThemeMode;
    onboardingCompleted: boolean;
  }) {
    await saveUserPreferences({
      locale: next.locale,
      themeMode: next.themeMode,
      onboardingCompleted: next.onboardingCompleted,
    });
    setLocale(next.locale);
    onLocaleResolved(next.locale);
    setThemeMode(next.themeMode);
    setBootstrap((prev) =>
      prev
        ? {
            ...prev,
            locale: next.locale,
            themeMode: next.themeMode,
            onboardingCompleted: next.onboardingCompleted,
          }
        : prev,
    );
  }

  async function handleStartSession() {
    if (!selectedProfileId) {
      setErrorMessage("Please select a meeting profile before starting.");
      return;
    }

    const language = selectedProfile?.language || "en-US";

    setIsWorking(true);
    try {
      const result = await startLiveSession({
        profileId: selectedProfileId,
        microphoneId: selectedMicId,
        sourceLanguage: language,
        targetLanguage: "zh-CN",
        asrProvider,
      });
      if (result.degradedMode) {
        setDegradedNote(result.message);
      }
    } catch (error) {
      setErrorMessage(String(error));
    } finally {
      setIsWorking(false);
    }
  }

  async function handleStopSession() {
    setIsWorking(true);
    try {
      await stopLiveSession();
    } catch (error) {
      setErrorMessage(String(error));
    } finally {
      setIsWorking(false);
    }
  }

  const stateLabel: SessionLifecycleState | "idle" = live.sessionState?.state ?? "idle";

  if (!bootstrap) {
    return <main className="app-shell"><p className="muted">Loading...</p></main>;
  }

  return (
    <main className={`app-shell app-shell-${bootstrap.platformStyle}`}>
      <div className="window-chrome">
        {bootstrap.platformStyle === "macos" ? (
          <div className="traffic-lights" aria-hidden>
            <span className="dot dot-red" />
            <span className="dot dot-yellow" />
            <span className="dot dot-green" />
          </div>
        ) : (
          <div className="fluent-caption">
            <span className="fluent-app-icon" />
            <span>{t("app.title")}</span>
          </div>
        )}
      </div>

      <header className="top-bar">
        <div>
          <h1>{t("app.title")}</h1>
          <p className="muted">{t("app.subtitle")}</p>
        </div>
        <Card className="status-box">
          <p className="mono">STATE: {stateLabel.toUpperCase()}</p>
          {latestLooksLikeQuestion ? <p className="warning-inline">Question intent detected.</p> : null}
          <div className="section-list compact-gap">
            <Select
              value={locale}
              onChange={(event) => {
                const next = event.target.value as LocaleCode;
                void persistPreferences({
                  locale: next,
                  themeMode,
                  onboardingCompleted: bootstrap.onboardingCompleted,
                }).catch((error) => setErrorMessage(String(error)));
              }}
            >
              <option value="zh-CN">{t("locale.zh-CN")}</option>
              <option value="en-US">{t("locale.en-US")}</option>
            </Select>
            <Select
              value={themeMode}
              onChange={(event) => {
                const next = event.target.value as ThemeMode;
                void persistPreferences({
                  locale,
                  themeMode: next,
                  onboardingCompleted: bootstrap.onboardingCompleted,
                }).catch((error) => setErrorMessage(String(error)));
              }}
            >
              <option value="system">{t("theme.system")}</option>
              <option value="light">{t("theme.light")}</option>
              <option value="dark">{t("theme.dark")}</option>
            </Select>
          </div>
        </Card>
      </header>

      {showWizard ? (
        <OnboardingWizard
          locale={locale}
          themeMode={themeMode}
          platformStyle={bootstrap.platformStyle}
          microphones={bootstrap.audioDevices.microphones}
          selectedMicId={selectedMicId}
          asrProvider={asrProvider}
          degradedNote={degradedNote}
          providerStatus={bootstrap.providerStatus}
          llmSettings={bootstrap.llmSettings}
          profiles={profiles}
          selectedProfileId={selectedProfileId}
          overlayMode={bootstrap.teleprompter}
          onLocaleChange={(next) => {
            void persistPreferences({
              locale: next,
              themeMode,
              onboardingCompleted: bootstrap.onboardingCompleted,
            }).catch((error) => setErrorMessage(String(error)));
          }}
          onThemeModeChange={(next) => {
            void persistPreferences({
              locale,
              themeMode: next,
              onboardingCompleted: bootstrap.onboardingCompleted,
            }).catch((error) => setErrorMessage(String(error)));
          }}
          onMicChange={setSelectedMicId}
          onAsrProviderChange={setAsrProvider}
          onProviderSaved={refreshBootstrap}
          onProfileSelect={setSelectedProfileId}
          onProfilesChanged={refreshProfiles}
          onOverlayModeChanged={(mode) => {
            setBootstrap((prev) => (prev ? { ...prev, teleprompter: mode } : prev));
          }}
          onError={handleError}
          onComplete={async () => {
            await persistPreferences({
              locale,
              themeMode,
              onboardingCompleted: true,
            });
            setShowWizard(false);
          }}
        />
      ) : (
        <>
          <div className="button-row">
            <Button
              variant="secondary"
              onClick={() => {
                setShowWizard(true);
              }}
            >
              {t("settings.openWizard")}
            </Button>
          </div>

          <SessionToolbar
            microphones={bootstrap.audioDevices.microphones}
            selectedMicId={selectedMicId}
            onMicChange={setSelectedMicId}
            asrProvider={asrProvider}
            onAsrProviderChange={setAsrProvider}
            selectedProfileId={selectedProfileId}
            sessionState={live.sessionState}
            isWorking={isWorking}
            onStart={handleStartSession}
            onStop={handleStopSession}
          />

          {errorMessage ? <p className="error-banner">{errorMessage}</p> : null}

          <section className="content-grid">
            <ProfileManager
              profiles={profiles}
              selectedProfileId={selectedProfileId}
              onSelectProfile={setSelectedProfileId}
              onProfilesChanged={refreshProfiles}
              onError={handleError}
            />

            <TranscriptList transcripts={live.transcripts} translations={live.translations} />

            <aside className="right-column">
              <ProviderSettings
                providerStatus={bootstrap.providerStatus}
                llmSettings={bootstrap.llmSettings}
                onSaved={refreshBootstrap}
                onError={handleError}
              />

              <TeleprompterControls
                mode={bootstrap.teleprompter}
                onModeChanged={(mode) => {
                  setBootstrap((prev) => (prev ? { ...prev, teleprompter: mode } : prev));
                }}
                onError={handleError}
              />

              <HintPanel
                hintText={live.hintText}
                sessionState={live.sessionState}
                runtimeErrors={live.runtimeErrors}
                degradedNote={degradedNote}
              />
            </aside>
          </section>
        </>
      )}
    </main>
  );
}

function App() {
  const [locale, setLocale] = useState<LocaleCode>("en-US");

  useEffect(() => {
    void getBootstrapState()
      .then((state) => {
        setLocale(state.locale);
      })
      .catch(() => {
        const fallback = navigator.language.toLowerCase().startsWith("zh") ? "zh-CN" : "en-US";
        setLocale(fallback);
      });
  }, []);

  return (
    <I18nProvider locale={locale}>
      <AppContent onLocaleResolved={setLocale} />
    </I18nProvider>
  );
}

function applyRootAppearance(
  themeMode: ThemeMode,
  platformStyle: "macos" | "windows" | "linux",
  systemPrefersDark: boolean,
) {
  const root = document.documentElement;
  root.classList.remove("platform-macos", "platform-windows", "platform-linux");
  root.classList.add(`platform-${platformStyle}`);

  const updateTheme = () => {
    const resolvedTheme =
      themeMode === "system"
        ? (systemPrefersDark ? "dark" : "light")
        : themeMode;
    root.classList.remove("theme-light", "theme-dark");
    root.classList.add(`theme-${resolvedTheme}`);
  };

  updateTheme();
}

export default App;
