import { getCurrentWindow } from "@tauri-apps/api/window";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  getBootstrapState,
  hideLiveOverlay,
  onTypedEvent,
  saveLiveOverlayLayout,
  setLiveOverlayMode,
  startLiveOverlayDrag,
} from "../../lib/tauri-ipc";
import { useLiveStore } from "../live/live-store";
import { Events, type LiveOverlayLayout, type WindowModeState } from "../../types/ipc-types";
import { useI18n } from "../../i18n/provider";

const DEFAULT_MODE: WindowModeState = {
  alwaysOnTop: true,
  transparent: true,
  undecorated: true,
  clickThrough: false,
  opacity: 0.86,
};

const DEFAULT_LAYOUT: LiveOverlayLayout = {
  opacity: 0.86,
  x: 980,
  y: 110,
  width: 920,
  height: 480,
  anchorScreen: undefined,
};

function clampOpacity(value: number) {
  return Math.max(0.35, Math.min(1, value));
}

export function LiveOverlayApp() {
  const live = useLiveStore();
  const { t } = useI18n();
  const [mode, setMode] = useState<WindowModeState>(DEFAULT_MODE);
  const [layout, setLayout] = useState<LiveOverlayLayout>(DEFAULT_LAYOUT);

  const saveTimer = useRef<number | null>(null);
  const layoutRef = useRef<LiveOverlayLayout>(DEFAULT_LAYOUT);

  useEffect(() => {
    void getBootstrapState()
      .then((state) => {
        layoutRef.current = state.liveOverlayLayout;
        setLayout(state.liveOverlayLayout);
        setMode(state.teleprompter);
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    let mounted = true;
    const unlisten: Array<() => void> = [];
    void (async () => {
      const offSession = await onTypedEvent(Events.SESSION_STATE, (payload) => {
        if (mounted) {
          live.pushSessionState(payload);
        }
      });
      const offTranscript = await onTypedEvent(Events.TRANSCRIPT_SEGMENT, (payload) => {
        if (mounted) {
          live.pushTranscript(payload);
        }
      });
      const offTranslation = await onTypedEvent(Events.TRANSLATION_SEGMENT, (payload) => {
        if (mounted) {
          live.pushTranslation(payload);
        }
      });
      const offHint = await onTypedEvent(Events.HINT_DELTA, (payload) => {
        if (mounted) {
          live.pushHintDelta(payload);
        }
      });
      const offError = await onTypedEvent(Events.RUNTIME_ERROR, (payload) => {
        if (mounted) {
          live.pushRuntimeError(payload);
        }
      });
      const offOverlayMode = await onTypedEvent(Events.OVERLAY_MODE, (payload) => {
        if (mounted) {
          setMode(payload);
        }
      });
      const offOverlayLayout = await onTypedEvent(Events.OVERLAY_LAYOUT, (payload) => {
        if (mounted) {
          layoutRef.current = payload;
          setLayout(payload);
        }
      });
      unlisten.push(
        offSession,
        offTranscript,
        offTranslation,
        offHint,
        offError,
        offOverlayMode,
        offOverlayLayout,
      );
    })();

    return () => {
      mounted = false;
      for (const off of unlisten) {
        off();
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const appWindow = getCurrentWindow();
    let mounted = true;

    const schedulePersist = () => {
      if (!mounted) {
        return;
      }
      if (saveTimer.current) {
        window.clearTimeout(saveTimer.current);
      }
      saveTimer.current = window.setTimeout(() => {
        const snapshot = layoutRef.current;
        void saveLiveOverlayLayout(snapshot).then((next) => {
          if (!mounted) {
            return;
          }
          layoutRef.current = next;
          setLayout(next);
          setMode((prev) => ({ ...prev, opacity: next.opacity }));
        });
      }, 160);
    };

    const setup = async () => {
      const offMove = await appWindow.onMoved(({ payload }) => {
        layoutRef.current = { ...layoutRef.current, x: payload.x, y: payload.y };
        setLayout(layoutRef.current);
        schedulePersist();
      });
      const offResize = await appWindow.onResized(({ payload }) => {
        layoutRef.current = {
          ...layoutRef.current,
          width: payload.width,
          height: payload.height,
        };
        setLayout(layoutRef.current);
        schedulePersist();
      });
      return [offMove, offResize];
    };

    let offs: Array<() => void> = [];
    void setup().then((next) => {
      offs = next;
    });

    return () => {
      mounted = false;
      if (saveTimer.current) {
        window.clearTimeout(saveTimer.current);
      }
      for (const off of offs) {
        off();
      }
    };
  }, []);

  async function applyMode(next: WindowModeState) {
    const normalized = { ...next, opacity: clampOpacity(next.opacity) };
    setMode(normalized);
    const appliedMode = await setLiveOverlayMode(normalized);
    setMode(appliedMode);
  }

  async function applyOpacity(value: number) {
    const opacity = clampOpacity(value);
    const nextLayout = { ...layoutRef.current, opacity };
    layoutRef.current = nextLayout;
    setLayout(nextLayout);
    setMode((prev) => ({ ...prev, opacity }));

    const [savedLayout, appliedMode] = await Promise.all([
      saveLiveOverlayLayout(nextLayout),
      setLiveOverlayMode({ ...mode, opacity }),
    ]);
    layoutRef.current = savedLayout;
    setLayout(savedLayout);
    setMode(appliedMode);
  }

  const mergedLines = useMemo(
    () =>
      live.transcripts
        .slice(-20)
        .map((segment) => {
          const translation = live.translations[segment.id];
          return translation ? `${segment.text}\n${translation.text}` : segment.text;
        })
        .join("\n\n"),
    [live.transcripts, live.translations],
  );

  return (
    <main className="overlay-shell">
      <header
        className="overlay-control-bar"
        onMouseDown={(event) => {
          if (event.button !== 0) {
            return;
          }
          void startLiveOverlayDrag();
        }}
      >
        <span className="overlay-title">{t("overlay.title")}</span>
        <div className="overlay-controls">
          <label className="field-label overlay-opacity">
            {t("overlay.opacity")}
            <input
              className="range"
              min={0.35}
              max={1}
              step={0.01}
              type="range"
              value={layout.opacity}
              onMouseDown={(event) => event.stopPropagation()}
              onChange={(event) => {
                void applyOpacity(Number(event.target.value));
              }}
            />
          </label>
          <button
            className="btn btn-secondary"
            type="button"
            onMouseDown={(event) => event.stopPropagation()}
            onClick={() => {
              void applyMode({ ...mode, clickThrough: !mode.clickThrough });
            }}
          >
            {mode.clickThrough ? t("overlay.clickThroughOff") : t("overlay.clickThroughOn")}
          </button>
          <button
            className="btn btn-secondary"
            type="button"
            onMouseDown={(event) => event.stopPropagation()}
            onClick={() => {
              void hideLiveOverlay();
            }}
          >
            {t("common.hideOverlay")}
          </button>
        </div>
      </header>

      <div
        className={mode.clickThrough ? "overlay-content click-through-content" : "overlay-content"}
        style={{ opacity: layout.opacity }}
      >
        <section className="overlay-pane">
          <h3>{t("overlay.translation")}</h3>
          <pre className="overlay-text">{mergedLines || t("live.empty")}</pre>
        </section>
        <section className="overlay-pane">
          <h3>{t("overlay.hint")}</h3>
          <pre className="overlay-text">{live.hintText || t("hint.empty")}</pre>
        </section>
      </div>
    </main>
  );
}
