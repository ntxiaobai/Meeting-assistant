use std::sync::Arc;

use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use tokio::sync::{mpsc, Mutex};
use tokio_tungstenite::tungstenite::{self, Message};

#[derive(Debug, Clone)]
pub struct DeepgramTranscript {
    pub text: String,
    pub is_final: bool,
}

#[derive(Clone)]
pub struct DeepgramSender {
    write: Arc<Mutex<DeepgramWriteHalf>>,
}

type DeepgramWsStream =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
type DeepgramWriteHalf = futures_util::stream::SplitSink<DeepgramWsStream, Message>;
type DeepgramReadHalf = futures_util::stream::SplitStream<DeepgramWsStream>;

impl DeepgramSender {
    pub async fn send_pcm(&self, pcm: &[i16]) -> Result<()> {
        let mut payload = Vec::with_capacity(pcm.len() * 2);
        for sample in pcm {
            payload.extend_from_slice(&sample.to_le_bytes());
        }

        let mut write = self.write.lock().await;
        write
            .send(Message::Binary(payload))
            .await
            .context("failed to send audio chunk to Deepgram")?;
        Ok(())
    }

    pub async fn close(&self) -> Result<()> {
        let mut write = self.write.lock().await;
        write
            .send(Message::Text(r#"{"type":"CloseStream"}"#.to_string()))
            .await
            .context("failed to send CloseStream message")?;
        Ok(())
    }
}

pub async fn connect_live(
    api_key: &str,
    language: &str,
    sample_rate: u32,
    channels: u16,
) -> Result<(DeepgramSender, mpsc::Receiver<DeepgramTranscript>)> {
    let url = format!(
        "wss://api.deepgram.com/v1/listen?model=nova-2&language={language}&encoding=linear16&sample_rate={sample_rate}&channels={channels}&interim_results=true&punctuate=true"
    );

    let request = tungstenite::http::Request::builder()
        .method("GET")
        .uri(url)
        .header("Authorization", format!("Token {api_key}"))
        .body(())
        .context("failed to build Deepgram websocket request")?;

    let (stream, _) = tokio_tungstenite::connect_async(request)
        .await
        .context("failed to open Deepgram websocket")?;

    let (write, read) = stream.split();
    let sender = DeepgramSender {
        write: Arc::new(Mutex::new(write)),
    };

    let (tx, rx) = mpsc::channel(128);
    spawn_reader(read, tx);

    Ok((sender, rx))
}

fn spawn_reader(mut read: DeepgramReadHalf, tx: mpsc::Sender<DeepgramTranscript>) {
    tokio::spawn(async move {
        while let Some(message) = read.next().await {
            match message {
                Ok(Message::Text(text)) => {
                    if let Some(transcript) = parse_transcript_event(&text) {
                        if tx.send(transcript).await.is_err() {
                            break;
                        }
                    }
                }
                Ok(Message::Close(_)) => break,
                Ok(_) => {}
                Err(_) => break,
            }
        }
    });
}

fn parse_transcript_event(payload: &str) -> Option<DeepgramTranscript> {
    let value: serde_json::Value = serde_json::from_str(payload).ok()?;
    if value.get("type")?.as_str()? != "Results" {
        return None;
    }

    let transcript = value
        .get("channel")?
        .get("alternatives")?
        .get(0)?
        .get("transcript")?
        .as_str()?
        .trim()
        .to_string();

    if transcript.is_empty() {
        return None;
    }

    let is_final = value
        .get("is_final")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    Some(DeepgramTranscript {
        text: transcript,
        is_final,
    })
}
