use anyhow::{anyhow, Result};
use tokio::sync::mpsc;

use crate::{models::AsrProvider, secrets::AliyunSecrets};

use super::{
    aliyun_tingwu_client::{self, AliyunEvent, AliyunSender},
    deepgram_client::{self, DeepgramSender, DeepgramTranscript},
};

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum AsrEventKind {
    Transcript,
    Translation,
}

#[derive(Debug, Clone)]
pub struct AsrEvent {
    pub kind: AsrEventKind,
    pub text: String,
    pub is_final: bool,
    pub sentence_index: Option<i64>,
}

#[derive(Clone)]
pub enum AsrSender {
    Deepgram(DeepgramSender),
    Aliyun(AliyunSender),
}

impl AsrSender {
    pub async fn send_pcm(&self, pcm: &[i16]) -> Result<()> {
        match self {
            Self::Deepgram(sender) => sender.send_pcm(pcm).await,
            Self::Aliyun(sender) => sender.send_pcm(pcm).await,
        }
    }

    pub async fn close(&self) -> Result<()> {
        match self {
            Self::Deepgram(sender) => sender.close().await,
            Self::Aliyun(sender) => sender.close().await,
        }
    }
}

pub struct AsrConnection {
    pub sender: AsrSender,
    pub receiver: mpsc::Receiver<AsrEvent>,
    pub provider: AsrProvider,
    pub fallback_reason: Option<String>,
}

pub struct AsrConnectInput {
    pub preferred_provider: AsrProvider,
    pub deepgram_key: Option<String>,
    pub aliyun_secrets: Option<AliyunSecrets>,
    pub source_language: String,
    pub target_language: String,
    pub sample_rate: u32,
    pub channels: u16,
    pub http_client: reqwest::Client,
}

pub async fn connect_with_fallback(input: AsrConnectInput) -> Result<AsrConnection> {
    match input.preferred_provider {
        AsrProvider::Aliyun => match try_connect_aliyun(&input).await {
            Ok(connection) => Ok(connection),
            Err(aliyun_error) => {
                let deepgram_key = input.deepgram_key.clone().ok_or_else(|| {
                    anyhow!("Aliyun unavailable and Deepgram key missing: {aliyun_error}")
                })?;

                let mut connection = connect_deepgram(
                    deepgram_key,
                    input.source_language.clone(),
                    input.sample_rate,
                    input.channels,
                )
                .await?;
                connection.fallback_reason = Some(format!(
                    "Aliyun failed, fallback to Deepgram: {aliyun_error}"
                ));
                Ok(connection)
            }
        },
        AsrProvider::Deepgram => {
            let deepgram_key = input
                .deepgram_key
                .clone()
                .ok_or_else(|| anyhow!("Deepgram key is required"))?;
            connect_deepgram(
                deepgram_key,
                input.source_language,
                input.sample_rate,
                input.channels,
            )
            .await
        }
    }
}

async fn try_connect_aliyun(input: &AsrConnectInput) -> Result<AsrConnection> {
    let secrets = input
        .aliyun_secrets
        .clone()
        .ok_or_else(|| anyhow!("Aliyun credentials not configured"))?;

    let (sender, receiver) = aliyun_tingwu_client::connect_live(
        input.http_client.clone(),
        secrets,
        &input.source_language,
        &input.target_language,
        input.sample_rate,
    )
    .await?;

    let (tx, rx) = mpsc::channel::<AsrEvent>(256);
    bridge_aliyun(receiver, tx);

    Ok(AsrConnection {
        sender: AsrSender::Aliyun(sender),
        receiver: rx,
        provider: AsrProvider::Aliyun,
        fallback_reason: None,
    })
}

async fn connect_deepgram(
    deepgram_key: String,
    source_language: String,
    sample_rate: u32,
    channels: u16,
) -> Result<AsrConnection> {
    let (sender, receiver) =
        deepgram_client::connect_live(&deepgram_key, &source_language, sample_rate, channels)
            .await?;
    let (tx, rx) = mpsc::channel::<AsrEvent>(256);
    bridge_deepgram(receiver, tx);

    Ok(AsrConnection {
        sender: AsrSender::Deepgram(sender),
        receiver: rx,
        provider: AsrProvider::Deepgram,
        fallback_reason: None,
    })
}

fn bridge_deepgram(mut source: mpsc::Receiver<DeepgramTranscript>, tx: mpsc::Sender<AsrEvent>) {
    tokio::spawn(async move {
        while let Some(item) = source.recv().await {
            let event = AsrEvent {
                kind: AsrEventKind::Transcript,
                text: item.text,
                is_final: item.is_final,
                sentence_index: None,
            };
            if tx.send(event).await.is_err() {
                break;
            }
        }
    });
}

fn bridge_aliyun(mut source: mpsc::Receiver<AliyunEvent>, tx: mpsc::Sender<AsrEvent>) {
    tokio::spawn(async move {
        while let Some(item) = source.recv().await {
            let event = AsrEvent {
                kind: item.kind,
                text: item.text,
                is_final: item.is_final,
                sentence_index: item.sentence_index,
            };

            if tx.send(event).await.is_err() {
                break;
            }
        }
    });
}
