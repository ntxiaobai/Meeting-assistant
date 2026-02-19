import { Card, CardTitle } from "../../../components/ui/card";
import { TeleprompterControls } from "../../teleprompter/TeleprompterControls";
import { useI18n } from "../../../i18n/provider";
import type { WindowModeState } from "../../../types/ipc-types";

interface OverlayStepProps {
  mode: WindowModeState;
  onModeChanged: (mode: WindowModeState) => void;
  onError: (message: string) => void;
}

export function OverlayStep({ mode, onModeChanged, onError }: OverlayStepProps) {
  const { t } = useI18n();

  return (
    <div className="section-list">
      <Card>
        <CardTitle>{t("wizard.step5")}</CardTitle>
        <p className="muted">{t("overlay.note")}</p>
      </Card>
      <TeleprompterControls mode={mode} onModeChanged={onModeChanged} onError={onError} />
    </div>
  );
}
