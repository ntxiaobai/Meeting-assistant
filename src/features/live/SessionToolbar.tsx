import { Button } from "../../components/ui/button";
import { Select } from "../../components/ui/select";
import { useI18n } from "../../i18n/provider";
import type { AsrProvider, AudioDeviceInfo, SessionStateEvent } from "../../types/ipc-types";

interface SessionToolbarProps {
  microphones: AudioDeviceInfo[];
  selectedMicId?: string;
  onMicChange: (micId?: string) => void;
  asrProvider: AsrProvider;
  onAsrProviderChange: (provider: AsrProvider) => void;
  selectedProfileId: string;
  sessionState: SessionStateEvent | null;
  isWorking: boolean;
  onStart: () => Promise<void>;
  onStop: () => Promise<void>;
}

export function SessionToolbar({
  microphones,
  selectedMicId,
  onMicChange,
  asrProvider,
  onAsrProviderChange,
  selectedProfileId,
  sessionState,
  isWorking,
  onStart,
  onStop,
}: SessionToolbarProps) {
  const { t } = useI18n();
  const running = sessionState?.state === "running" || sessionState?.state === "starting";

  return (
    <section className="toolbar">
      <div className="toolbar-group">
        <label className="field-label">{t("toolbar.microphone")}</label>
        <Select
          value={selectedMicId ?? ""}
          onChange={(event) => onMicChange(event.target.value || undefined)}
        >
          <option value="">Default device</option>
          {microphones.map((mic) => (
            <option key={mic.id} value={mic.id}>
              {mic.isDefault ? `${mic.name} (default)` : mic.name}
            </option>
          ))}
        </Select>
      </div>

      <div className="toolbar-group">
        <label className="field-label">{t("toolbar.provider")}</label>
        <Select
          value={asrProvider}
          onChange={(event) => onAsrProviderChange(event.target.value as AsrProvider)}
        >
          <option value="aliyun">Aliyun</option>
          <option value="deepgram">Deepgram</option>
        </Select>
      </div>

      <div className="toolbar-group small">
        <label className="field-label">{t("toolbar.profile")}</label>
        <p className="mono">{selectedProfileId || t("toolbar.notSelected")}</p>
      </div>

      <div className="toolbar-group actions">
        <Button onClick={onStart} disabled={!selectedProfileId || running || isWorking}>
          {t("common.start")}
        </Button>
        <Button onClick={onStop} variant="secondary" disabled={!running || isWorking}>
          {t("common.stop")}
        </Button>
      </div>
    </section>
  );
}
