import { Card, CardTitle } from "../../../components/ui/card";
import { Select } from "../../../components/ui/select";
import { useI18n } from "../../../i18n/provider";
import type { AsrProvider, AudioDeviceInfo } from "../../../types/ipc-types";

interface AudioStepProps {
  microphones: AudioDeviceInfo[];
  selectedMicId?: string;
  asrProvider: AsrProvider;
  degradedNote?: string;
  onMicChange: (value?: string) => void;
  onAsrProviderChange: (provider: AsrProvider) => void;
}

export function AudioStep({
  microphones,
  selectedMicId,
  asrProvider,
  degradedNote,
  onMicChange,
  onAsrProviderChange,
}: AudioStepProps) {
  const { t } = useI18n();

  return (
    <Card>
      <CardTitle>{t("wizard.step2")}</CardTitle>
      <div className="section-list compact-gap">
        <label className="field-label">{t("toolbar.microphone")}</label>
        <Select value={selectedMicId ?? ""} onChange={(event) => onMicChange(event.target.value || undefined)}>
          <option value="">Default</option>
          {microphones.map((mic) => (
            <option key={mic.id} value={mic.id}>
              {mic.isDefault ? `${mic.name} (default)` : mic.name}
            </option>
          ))}
        </Select>
      </div>
      <div className="section-list compact-gap">
        <label className="field-label">{t("toolbar.provider")}</label>
        <Select
          value={asrProvider}
          onChange={(event) => onAsrProviderChange(event.target.value as AsrProvider)}
        >
          <option value="aliyun">Aliyun Tingwu</option>
          <option value="deepgram">Deepgram</option>
        </Select>
      </div>
      {degradedNote ? <p className="warning-banner">{degradedNote}</p> : null}
    </Card>
  );
}
