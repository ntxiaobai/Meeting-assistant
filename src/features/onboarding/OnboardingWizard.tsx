import { useMemo, useState } from "react";
import { Button } from "../../components/ui/button";
import { useI18n } from "../../i18n/provider";
import type {
  AsrProvider,
  AudioDeviceInfo,
  LocaleCode,
  LlmSettings,
  MeetingProfile,
  ProviderStatus,
  ThemeMode,
  WindowModeState,
} from "../../types/ipc-types";
import { AudioStep } from "./steps/AudioStep";
import { LanguageThemeStep } from "./steps/LanguageThemeStep";
import { OverlayStep } from "./steps/OverlayStep";
import { ProfileStep } from "./steps/ProfileStep";
import { ProviderStep } from "./steps/ProviderStep";

interface OnboardingWizardProps {
  locale: LocaleCode;
  themeMode: ThemeMode;
  platformStyle: "macos" | "windows" | "linux";
  microphones: AudioDeviceInfo[];
  selectedMicId?: string;
  asrProvider: AsrProvider;
  degradedNote?: string;
  providerStatus: ProviderStatus;
  llmSettings: LlmSettings;
  profiles: MeetingProfile[];
  selectedProfileId: string;
  overlayMode: WindowModeState;
  onLocaleChange: (locale: LocaleCode) => void;
  onThemeModeChange: (theme: ThemeMode) => void;
  onMicChange: (id?: string) => void;
  onAsrProviderChange: (provider: AsrProvider) => void;
  onProviderSaved: () => Promise<void>;
  onProfileSelect: (id: string) => void;
  onProfilesChanged: () => Promise<void>;
  onOverlayModeChanged: (mode: WindowModeState) => void;
  onError: (message: string) => void;
  onComplete: () => Promise<void>;
}

export function OnboardingWizard(props: OnboardingWizardProps) {
  const { t } = useI18n();
  const [step, setStep] = useState(0);
  const [isFinishing, setIsFinishing] = useState(false);

  const steps = useMemo(
    () => [
      {
        key: "language",
        title: t("wizard.step1"),
        view: (
          <LanguageThemeStep
            locale={props.locale}
            themeMode={props.themeMode}
            platformStyle={props.platformStyle}
            onLocaleChange={props.onLocaleChange}
            onThemeModeChange={props.onThemeModeChange}
          />
        ),
      },
      {
        key: "audio",
        title: t("wizard.step2"),
        view: (
          <AudioStep
            microphones={props.microphones}
            selectedMicId={props.selectedMicId}
            asrProvider={props.asrProvider}
            degradedNote={props.degradedNote}
            onMicChange={props.onMicChange}
            onAsrProviderChange={props.onAsrProviderChange}
          />
        ),
      },
      {
        key: "provider",
        title: t("wizard.step3"),
        view: (
          <ProviderStep
            providerStatus={props.providerStatus}
            llmSettings={props.llmSettings}
            onSaved={props.onProviderSaved}
            onError={props.onError}
          />
        ),
      },
      {
        key: "profile",
        title: t("wizard.step4"),
        view: (
          <ProfileStep
            profiles={props.profiles}
            selectedProfileId={props.selectedProfileId}
            onSelectProfile={props.onProfileSelect}
            onProfilesChanged={props.onProfilesChanged}
            onError={props.onError}
          />
        ),
      },
      {
        key: "overlay",
        title: t("wizard.step5"),
        view: (
          <OverlayStep
            mode={props.overlayMode}
            onModeChanged={props.onOverlayModeChanged}
            onError={props.onError}
          />
        ),
      },
    ],
    [props, t],
  );

  const isLast = step === steps.length - 1;

  return (
    <section className="wizard-shell">
      <header className="wizard-header">
        <h2>
          {t("app.step")} {step + 1} / {steps.length}: {steps[step].title}
        </h2>
      </header>

      <div className="wizard-body">
        <aside className="wizard-step-rail">
          {steps.map((item, index) => (
            <button
              key={item.key}
              type="button"
              className={index === step ? "wizard-step-pill active" : "wizard-step-pill"}
              onClick={() => setStep(index)}
            >
              <span className="mono">{index + 1}</span>
              <span>{item.title}</span>
            </button>
          ))}
        </aside>

        <div className="wizard-content">{steps[step].view}</div>
      </div>

      <footer className="wizard-actions">
        <Button
          variant="secondary"
          onClick={() => setStep((prev) => Math.max(0, prev - 1))}
          disabled={step === 0 || isFinishing}
        >
          {t("common.back")}
        </Button>
        {!isLast ? (
          <Button
            onClick={() => setStep((prev) => Math.min(steps.length - 1, prev + 1))}
            disabled={isFinishing}
          >
            {t("common.next")}
          </Button>
        ) : (
          <Button
            onClick={async () => {
              setIsFinishing(true);
              try {
                await props.onComplete();
              } catch (error) {
                props.onError(String(error));
              } finally {
                setIsFinishing(false);
              }
            }}
            disabled={isFinishing}
          >
            {t("common.finish")}
          </Button>
        )}
      </footer>
    </section>
  );
}
