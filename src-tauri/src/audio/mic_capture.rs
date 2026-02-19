use std::{
    sync::mpsc as std_mpsc,
    thread::{self, JoinHandle},
    time::Duration,
};

use anyhow::{anyhow, Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{SampleFormat, Stream, StreamConfig};
use tokio::sync::mpsc;

#[derive(Debug, Clone)]
pub struct MicDeviceDescriptor {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

pub struct MicCaptureHandle {
    stream: Stream,
}

pub fn list_microphones() -> Result<Vec<MicDeviceDescriptor>> {
    let host = cpal::default_host();
    let default_name = host
        .default_input_device()
        .and_then(|device| device.name().ok())
        .unwrap_or_default();

    let devices = host
        .input_devices()
        .context("failed to enumerate input devices")?;

    let descriptors = devices
        .enumerate()
        .filter_map(|(idx, device)| {
            let name = device.name().ok()?;
            Some(MicDeviceDescriptor {
                id: format!("mic-{idx}"),
                is_default: name == default_name,
                name,
            })
        })
        .collect();

    Ok(descriptors)
}

pub fn resolve_capture_format(selected_device_id: Option<&str>) -> Result<(u32, u16)> {
    let host = cpal::default_host();
    let selected_device = find_device_by_id(&host, selected_device_id)?
        .or_else(|| host.default_input_device())
        .ok_or_else(|| anyhow!("no microphone device available"))?;

    let supported_config = selected_device
        .default_input_config()
        .context("failed to read default microphone config")?;

    let config = supported_config.config();
    Ok((config.sample_rate.0, config.channels))
}

pub fn spawn_capture_worker(
    selected_device_id: Option<String>,
    audio_tx: mpsc::Sender<Vec<i16>>,
    rms_threshold: f32,
) -> Result<(std_mpsc::Sender<()>, JoinHandle<()>)> {
    let (stop_tx, stop_rx) = std_mpsc::channel::<()>();
    let (init_tx, init_rx) = std_mpsc::channel::<Result<(), String>>();

    let thread = thread::Builder::new()
        .name("meeting-assistant-mic-capture".to_string())
        .spawn(move || {
            let capture = start_capture(selected_device_id.as_deref(), audio_tx, rms_threshold)
                .map_err(|error| error.to_string());

            match capture {
                Ok(handle) => {
                    let _ = init_tx.send(Ok(()));
                    let _keep_stream_alive = handle.stream;
                    let _ = stop_rx.recv();
                }
                Err(error) => {
                    let _ = init_tx.send(Err(error));
                }
            }
        })
        .context("failed to spawn microphone capture worker")?;

    match init_rx.recv_timeout(Duration::from_secs(3)) {
        Ok(Ok(())) => Ok((stop_tx, thread)),
        Ok(Err(error)) => {
            let _ = thread.join();
            Err(anyhow!("failed to initialize microphone capture: {error}"))
        }
        Err(error) => {
            let _ = stop_tx.send(());
            let _ = thread.join();
            Err(anyhow!(
                "timed out waiting for microphone capture worker: {error}"
            ))
        }
    }
}

fn start_capture(
    selected_device_id: Option<&str>,
    audio_tx: mpsc::Sender<Vec<i16>>,
    rms_threshold: f32,
) -> Result<MicCaptureHandle> {
    let host = cpal::default_host();

    let selected_device = find_device_by_id(&host, selected_device_id)?
        .or_else(|| host.default_input_device())
        .ok_or_else(|| anyhow!("no microphone device available"))?;

    let supported_config = selected_device
        .default_input_config()
        .context("failed to read default microphone config")?;

    let sample_format = supported_config.sample_format();
    let config: StreamConfig = supported_config.config();

    let err_fn = |err| eprintln!("microphone stream error: {err}");

    let stream = match sample_format {
        SampleFormat::F32 => selected_device.build_input_stream(
            &config,
            move |data: &[f32], _| {
                push_f32_samples(data, &audio_tx, rms_threshold);
            },
            err_fn,
            None,
        )?,
        SampleFormat::I16 => selected_device.build_input_stream(
            &config,
            move |data: &[i16], _| {
                push_i16_samples(data, &audio_tx, rms_threshold);
            },
            err_fn,
            None,
        )?,
        SampleFormat::U16 => selected_device.build_input_stream(
            &config,
            move |data: &[u16], _| {
                push_u16_samples(data, &audio_tx, rms_threshold);
            },
            err_fn,
            None,
        )?,
        other => {
            return Err(anyhow!("unsupported input sample format: {other:?}"));
        }
    };

    stream.play().context("failed to start microphone stream")?;

    Ok(MicCaptureHandle { stream })
}

fn find_device_by_id(
    host: &cpal::Host,
    selected_device_id: Option<&str>,
) -> Result<Option<cpal::Device>> {
    let Some(selected_id) = selected_device_id else {
        return Ok(None);
    };

    let devices = host
        .input_devices()
        .context("failed to enumerate input devices")?;

    for (idx, device) in devices.enumerate() {
        if format!("mic-{idx}") == selected_id {
            return Ok(Some(device));
        }
    }

    Ok(None)
}

fn push_f32_samples(data: &[f32], audio_tx: &mpsc::Sender<Vec<i16>>, rms_threshold: f32) {
    if data.is_empty() {
        return;
    }

    let mut pcm = Vec::with_capacity(data.len());
    for sample in data {
        let clamped = sample.clamp(-1.0, 1.0);
        pcm.push((clamped * i16::MAX as f32) as i16);
    }

    push_pcm_if_loud_enough(&pcm, audio_tx, rms_threshold);
}

fn push_i16_samples(data: &[i16], audio_tx: &mpsc::Sender<Vec<i16>>, rms_threshold: f32) {
    if data.is_empty() {
        return;
    }

    let pcm = data.to_vec();
    push_pcm_if_loud_enough(&pcm, audio_tx, rms_threshold);
}

fn push_u16_samples(data: &[u16], audio_tx: &mpsc::Sender<Vec<i16>>, rms_threshold: f32) {
    if data.is_empty() {
        return;
    }

    let mut pcm = Vec::with_capacity(data.len());
    for sample in data {
        let centered = *sample as i32 - u16::MAX as i32 / 2;
        pcm.push(centered as i16);
    }

    push_pcm_if_loud_enough(&pcm, audio_tx, rms_threshold);
}

fn push_pcm_if_loud_enough(data: &[i16], audio_tx: &mpsc::Sender<Vec<i16>>, rms_threshold: f32) {
    if data.is_empty() {
        return;
    }

    let energy = data
        .iter()
        .map(|sample| {
            let normalized = *sample as f32 / i16::MAX as f32;
            normalized * normalized
        })
        .sum::<f32>();

    let rms = (energy / data.len() as f32).sqrt();

    if rms >= rms_threshold {
        // Never block inside audio callbacks; dropping burst frames is preferable to stalling stream threads.
        let _ = audio_tx.try_send(data.to_vec());
    }
}
