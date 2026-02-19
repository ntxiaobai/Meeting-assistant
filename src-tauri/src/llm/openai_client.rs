use std::{future::Future, pin::Pin};

use anyhow::{Context, Result};
use serde::Serialize;

use super::LlmProvider;

#[derive(Clone)]
pub struct OpenAiCompatClient {
    http_client: reqwest::Client,
    api_key: String,
    model: String,
    base_url: String,
}

impl OpenAiCompatClient {
    pub fn with_config(
        http_client: reqwest::Client,
        api_key: String,
        base_url: impl Into<String>,
        model: impl Into<String>,
    ) -> Self {
        Self {
            http_client,
            api_key,
            model: model.into(),
            base_url: base_url.into(),
        }
    }

    fn endpoint(&self) -> String {
        format!("{}/chat/completions", self.base_url.trim_end_matches('/'))
    }
}

impl LlmProvider for OpenAiCompatClient {
    fn complete<'a>(
        &'a self,
        system_prompt: &'a str,
        user_prompt: &'a str,
    ) -> Pin<Box<dyn Future<Output = Result<String>> + Send + 'a>> {
        Box::pin(async move {
            let payload = OpenAiRequest {
                model: self.model.clone(),
                messages: vec![
                    OpenAiMessage {
                        role: "system".to_string(),
                        content: system_prompt.to_string(),
                    },
                    OpenAiMessage {
                        role: "user".to_string(),
                        content: user_prompt.to_string(),
                    },
                ],
                stream: false,
                temperature: 0.2,
            };

            let response = self
                .http_client
                .post(self.endpoint())
                .header("authorization", format!("Bearer {}", self.api_key))
                .header("content-type", "application/json")
                .json(&payload)
                .send()
                .await
                .context("failed to call OpenAI-compatible API")?;

            if !response.status().is_success() {
                let body = response.text().await.unwrap_or_default();
                return Err(anyhow::anyhow!("OpenAI-compatible request failed: {body}"));
            }

            let value: serde_json::Value = response
                .json()
                .await
                .context("failed to parse OpenAI-compatible response")?;

            let content = value
                .get("choices")
                .and_then(|choices| choices.get(0))
                .and_then(|choice| choice.get("message"))
                .and_then(|message| message.get("content"))
                .cloned()
                .unwrap_or(serde_json::Value::String(String::new()));

            let text = if let Some(single) = content.as_str() {
                single.to_string()
            } else if let Some(parts) = content.as_array() {
                parts
                    .iter()
                    .filter_map(|part| part.get("text").and_then(|text| text.as_str()))
                    .collect::<Vec<_>>()
                    .join("\n")
            } else {
                String::new()
            };

            Ok(text.trim().to_string())
        })
    }
}

#[derive(Debug, Serialize)]
struct OpenAiRequest {
    model: String,
    messages: Vec<OpenAiMessage>,
    stream: bool,
    temperature: f32,
}

#[derive(Debug, Serialize)]
struct OpenAiMessage {
    role: String,
    content: String,
}
