import { Card, CardTitle } from "../../components/ui/card";
import { useI18n } from "../../i18n/provider";
import type {
  TranscriptSegmentEvent,
  TranslationSegmentEvent,
} from "../../types/ipc-types";

interface TranscriptListProps {
  transcripts: TranscriptSegmentEvent[];
  translations: Record<string, TranslationSegmentEvent>;
}

export function TranscriptList({ transcripts, translations }: TranscriptListProps) {
  const { t } = useI18n();

  return (
    <Card className="live-card">
      <CardTitle>{t("live.title")}</CardTitle>

      <div className="transcript-scroll">
        {transcripts.length === 0 ? (
          <p className="muted">{t("live.empty")}</p>
        ) : (
          transcripts.map((segment) => {
            const translation = translations[segment.id];
            return (
              <article key={segment.id} className={segment.isFinal ? "segment final" : "segment interim"}>
                <header>
                  <span className="speaker">{segment.speaker}</span>
                  <span className="timestamp">
                    {new Date(segment.timestampMs).toLocaleTimeString()}
                  </span>
                </header>
                <p>{segment.text}</p>
                {translation ? <p className="translation">{translation.text}</p> : null}
              </article>
            );
          })
        )}
      </div>
    </Card>
  );
}
