use anyhow::Result;

use crate::models::{AudioDeviceInfo, AudioDeviceList};

pub mod loopback_stub;
pub mod mic_capture;

pub fn list_audio_devices() -> Result<AudioDeviceList> {
    let microphones = mic_capture::list_microphones()?
        .into_iter()
        .map(|device| AudioDeviceInfo {
            id: device.id,
            name: device.name,
            is_default: device.is_default,
        })
        .collect::<Vec<_>>();

    let loopback = loopback_stub::detect_loopback_availability();

    Ok(AudioDeviceList {
        microphones,
        system_loopback_available: loopback.available,
        note: loopback.note,
    })
}
