use anyhow::{anyhow, Context, Result};
use tauri::{AppHandle, Manager};

use crate::models::{TeleprompterModeInput, WindowModeState};

pub fn apply_window_mode(
    app: &AppHandle,
    label: &str,
    input: TeleprompterModeInput,
) -> Result<WindowModeState> {
    let window = app
        .get_webview_window(label)
        .ok_or_else(|| anyhow!("window not found: {label}"))?;

    let opacity = input.opacity.clamp(0.35, 1.0);

    window
        .set_always_on_top(input.always_on_top)
        .context("failed to set always-on-top")?;
    window
        .set_decorations(!input.undecorated)
        .context("failed to set window decorations")?;

    // Keep one interactive control area in overlay even when click-through is enabled.
    // We therefore use content-level pass-through (frontend) instead of OS-level full pass-through.
    window
        .set_ignore_cursor_events(false)
        .context("failed to configure click-through guard mode")?;

    Ok(WindowModeState {
        always_on_top: input.always_on_top,
        transparent: input.transparent,
        undecorated: input.undecorated,
        click_through: input.click_through,
        opacity,
    })
}
