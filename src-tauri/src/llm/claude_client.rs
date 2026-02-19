use std::{future::Future, pin::Pin};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use super::LlmProvider;

#[derive(Clone)]
pub struct ClaudeClient {
    http_client: reqwest::Client,
    api_key: String,
    model: String,
    base_url: String,
}

impl ClaudeClient {
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
        format!("{}/messages", self.base_url.trim_end_matches('/'))
    }
}

impl LlmProvider for ClaudeClient {
    fn complete<'a>(
        &'a self,
        system_prompt: &'a str,
        user_prompt: &'a str,
    ) -> Pin<Box<dyn Future<Output = Result<String>> + Send + 'a>> {
        Box::pin(async move {
            let payload = ClaudeRequest {
                model: self.model.clone(),
                max_tokens: 512,
                system: system_prompt.to_string(),
                messages: vec![ClaudeMessage {
                    role: "user".to_string(),
                    content: user_prompt.to_string(),
                }],
                stream: false,
            };

            let response = self
                .http_client
                .post(self.endpoint())
                .header("x-api-key", &self.api_key)
                .header("anthropic-version", "2023-06-01")
                .header("content-type", "application/json")
                .json(&payload)
                .send()
                .await
                .context("failed to call Claude API")?;

            if !response.status().is_success() {
                let body = response.text().await.unwrap_or_default();
                return Err(anyhow::anyhow!("Claude request failed: {body}"));
            }

            let body: ClaudeResponse = response
                .json()
                .await
                .context("failed to parse Claude response")?;

            let text = body
                .content
                .into_iter()
                .filter_map(|item| item.text)
                .collect::<Vec<_>>()
                .join("\n")
                .trim()
                .to_string();

            Ok(text)
        })
    }
}

#[derive(Debug, Serialize)]
struct ClaudeRequest {
    model: String,
    max_tokens: u32,
    system: String,
    messages: Vec<ClaudeMessage>,
    stream: bool,
}

#[derive(Debug, Serialize)]
struct ClaudeMessage {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct ClaudeResponse {
    content: Vec<ClaudeContentItem>,
}

#[derive(Debug, Deserialize)]
struct ClaudeContentItem {
    text: Option<String>,
}
