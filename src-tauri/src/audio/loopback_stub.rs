#[derive(Debug, Clone)]
pub struct LoopbackAvailability {
    pub available: bool,
    pub note: Option<String>,
}

pub fn detect_loopback_availability() -> LoopbackAvailability {
    #[cfg(target_os = "windows")]
    {
        return LoopbackAvailability {
            available: false,
            note: Some(
                "Windows loopback will be added in phase 2. MVP currently uses microphone only."
                    .to_string(),
            ),
        };
    }

    #[cfg(target_os = "macos")]
    {
        return LoopbackAvailability {
            available: false,
            note: Some(
                "macOS system audio capture is not enabled in MVP. Use microphone mode for now."
                    .to_string(),
            ),
        };
    }

    #[allow(unreachable_code)]
    LoopbackAvailability {
        available: false,
        note: Some("System loopback is not available on this platform in MVP.".to_string()),
    }
}
