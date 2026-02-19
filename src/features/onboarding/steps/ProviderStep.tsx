import { ProviderSettings } from "../../settings/ProviderSettings";
import type { LlmSettings, ProviderStatus } from "../../../types/ipc-types";

interface ProviderStepProps {
  providerStatus: ProviderStatus;
  llmSettings: LlmSettings;
  onSaved: () => Promise<void>;
  onError: (message: string) => void;
}

export function ProviderStep({ providerStatus, llmSettings, onSaved, onError }: ProviderStepProps) {
  return (
    <ProviderSettings
      providerStatus={providerStatus}
      llmSettings={llmSettings}
      onSaved={onSaved}
      onError={onError}
    />
  );
}
