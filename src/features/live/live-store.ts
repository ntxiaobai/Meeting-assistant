import { useEffect, useRef, useState } from "react";
import type {
  HintDeltaEvent,
  RuntimeErrorEvent,
  SessionStateEvent,
  TranscriptSegmentEvent,
  TranslationSegmentEvent,
} from "../../types/ipc-types";

const MAX_SEGMENTS = 240;
const FLUSH_INTERVAL_MS = 50;

export function useLiveStore() {
  const [transcripts, setTranscripts] = useState<TranscriptSegmentEvent[]>([]);
  const [translations, setTranslations] = useState<Record<string, TranslationSegmentEvent>>({});
  const [hintText, setHintText] = useState("");
  const [sessionState, setSessionState] = useState<SessionStateEvent | null>(null);
  const [runtimeErrors, setRuntimeErrors] = useState<RuntimeErrorEvent[]>([]);

  const transcriptBuffer = useRef<TranscriptSegmentEvent[]>([]);
  const translationBuffer = useRef<TranslationSegmentEvent[]>([]);
  const recentTranscriptIds = useRef<string[]>([]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      if (transcriptBuffer.current.length > 0) {
        const pending = transcriptBuffer.current.splice(0, transcriptBuffer.current.length);
        setTranscripts((prev) => {
          const merged = [...prev, ...pending];
          const bounded =
            merged.length <= MAX_SEGMENTS ? merged : merged.slice(merged.length - MAX_SEGMENTS);
          recentTranscriptIds.current = bounded.map((item) => item.id);
          return bounded;
        });
      }

      if (translationBuffer.current.length > 0) {
        const pending = translationBuffer.current.splice(0, translationBuffer.current.length);
        setTranslations((prev) => {
          const next = { ...prev };
          for (const item of pending) {
            next[item.transcriptId] = item;
          }
          if (recentTranscriptIds.current.length > 0) {
            const keep = new Set(recentTranscriptIds.current);
            for (const key of Object.keys(next)) {
              if (!keep.has(key)) {
                delete next[key];
              }
            }
          }
          return next;
        });
      }
    }, FLUSH_INTERVAL_MS);

    return () => window.clearInterval(timer);
  }, []);

  function pushTranscript(segment: TranscriptSegmentEvent) {
    transcriptBuffer.current.push(segment);
  }

  function pushTranslation(segment: TranslationSegmentEvent) {
    translationBuffer.current.push(segment);
  }

  function pushSessionState(state: SessionStateEvent) {
    setSessionState(state);
  }

  function pushHintDelta(delta: HintDeltaEvent) {
    setHintText((prev) => {
      if (delta.done) {
        return `${prev}\n`;
      }
      return prev + delta.delta;
    });
  }

  function pushRuntimeError(error: RuntimeErrorEvent) {
    setRuntimeErrors((prev) => {
      const next = [error, ...prev];
      return next.slice(0, 8);
    });
  }

  function resetSessionView() {
    setTranscripts([]);
    setTranslations({});
    setHintText("");
    setRuntimeErrors([]);
    setSessionState(null);
    transcriptBuffer.current = [];
    translationBuffer.current = [];
  }

  return {
    transcripts,
    translations,
    hintText,
    sessionState,
    runtimeErrors,
    pushTranscript,
    pushTranslation,
    pushSessionState,
    pushHintDelta,
    pushRuntimeError,
    resetSessionView,
  };
}
