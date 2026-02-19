import { useEffect, useState } from "react";
import { Button } from "../../components/ui/button";
import { Card, CardTitle } from "../../components/ui/card";
import { Switch } from "../../components/ui/switch";
import { useI18n } from "../../i18n/provider";
import { hideLiveOverlay, setLiveOverlayMode, showLiveOverlay } from "../../lib/tauri-ipc";
import type { WindowModeState } from "../../types/ipc-types";

interface TeleprompterControlsProps {
  mode: WindowModeState;
  onModeChanged: (mode: WindowModeState) => void;
  onError: (message: string) => void;
}

export function TeleprompterControls({
  mode,
  onModeChanged,
  onError,
}: TeleprompterControlsProps) {
  const { t } = useI18n();
  const [draft, setDraft] = useState<WindowModeState>(mode);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    setDraft(mode);
  }, [mode]);

  async function applyMode() {
    setIsSaving(true);
    try {
      const next = await setLiveOverlayMode(draft);
      onModeChanged(next);
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  async function quickOverlayMode() {
    const quick = {
      ...draft,
      alwaysOnTop: true,
      transparent: true,
      undecorated: true,
      opacity: 0.85,
    };

    setDraft(quick);
    setIsSaving(true);
    try {
      const next = await setLiveOverlayMode(quick);
      onModeChanged(next);
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <Card>
      <CardTitle>{t("overlay.title")}</CardTitle>
      <div className="section-list compact-gap">
        <Switch
          label="Always on top"
          checked={draft.alwaysOnTop}
          onChange={(event) => setDraft((prev) => ({ ...prev, alwaysOnTop: event.target.checked }))}
        />
        <Switch
          label="Transparent mode"
          checked={draft.transparent}
          onChange={(event) => setDraft((prev) => ({ ...prev, transparent: event.target.checked }))}
        />
        <Switch
          label="Undecorated"
          checked={draft.undecorated}
          onChange={(event) => setDraft((prev) => ({ ...prev, undecorated: event.target.checked }))}
        />
        <Switch
          label="Click-through"
          checked={draft.clickThrough}
          onChange={(event) => setDraft((prev) => ({ ...prev, clickThrough: event.target.checked }))}
        />

        <label className="field-label">
          Opacity: {draft.opacity.toFixed(2)}
          <input
            className="range"
            min={0.2}
            max={1}
            step={0.05}
            type="range"
            value={draft.opacity}
            onChange={(event) =>
              setDraft((prev) => ({ ...prev, opacity: Number(event.target.value) }))
            }
          />
        </label>

        <div className="button-row">
          <Button onClick={applyMode} disabled={isSaving}>
            {t("common.apply")}
          </Button>
          <Button onClick={quickOverlayMode} variant="secondary" disabled={isSaving}>
            Quick Overlay
          </Button>
          <Button
            onClick={async () => {
              try {
                await showLiveOverlay();
              } catch (error) {
                onError(String(error));
              }
            }}
            variant="secondary"
            disabled={isSaving}
          >
            {t("common.openOverlay")}
          </Button>
          <Button
            onClick={async () => {
              try {
                await hideLiveOverlay();
              } catch (error) {
                onError(String(error));
              }
            }}
            variant="secondary"
            disabled={isSaving}
          >
            {t("common.hideOverlay")}
          </Button>
        </div>
      </div>
    </Card>
  );
}
