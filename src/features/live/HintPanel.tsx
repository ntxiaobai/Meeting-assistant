import { Card, CardTitle } from "../../components/ui/card";
import { useI18n } from "../../i18n/provider";
import type { RuntimeErrorEvent, SessionStateEvent } from "../../types/ipc-types";

interface HintPanelProps {
  hintText: string;
  sessionState: SessionStateEvent | null;
  runtimeErrors: RuntimeErrorEvent[];
  degradedNote?: string;
}

export function HintPanel({
  hintText,
  sessionState,
  runtimeErrors,
  degradedNote,
}: HintPanelProps) {
  const { t } = useI18n();

  return (
    <Card className="hint-card">
      <CardTitle>{t("hint.title")}</CardTitle>
      {sessionState ? (
        <p className="status-banner">
          <strong>{sessionState.state.toUpperCase()}</strong> - {sessionState.message}
        </p>
      ) : null}

      {degradedNote ? <p className="warning-banner">{degradedNote}</p> : null}

      <pre className="hint-output">{hintText || t("hint.empty")}</pre>

      {runtimeErrors.length > 0 ? (
        <div className="section-list compact-gap">
          <h4 className="sub-title">Runtime alerts</h4>
          {runtimeErrors.map((error, idx) => (
            <p key={`${error.code}-${idx}`} className="error-line">
              [{error.code}] {error.message}
            </p>
          ))}
        </div>
      ) : null}
    </Card>
  );
}
