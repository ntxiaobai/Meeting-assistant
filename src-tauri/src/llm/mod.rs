use std::{future::Future, pin::Pin, sync::Arc};

use anyhow::Result;

pub mod claude_client;
pub mod openai_client;

pub trait LlmProvider: Send + Sync {
    fn complete<'a>(
        &'a self,
        system_prompt: &'a str,
        user_prompt: &'a str,
    ) -> Pin<Box<dyn Future<Output = Result<String>> + Send + 'a>>;
}

#[derive(Clone)]
pub struct LlmService {
    provider: Arc<dyn LlmProvider>,
}

impl LlmService {
    pub fn new(provider: Arc<dyn LlmProvider>) -> Self {
        Self { provider }
    }

    pub async fn translate_to_chinese(&self, source_text: &str) -> Result<String> {
        let system = "You are a real-time translator. Translate English speech into concise and natural Simplified Chinese. Keep original meaning and tone.";
        let user = format!("Translate this into Chinese only:\n\n{source_text}");
        self.provider.complete(system, &user).await
    }

    pub async fn suggest_answer(
        &self,
        profile_context: &str,
        latest_question: &str,
    ) -> Result<String> {
        let system = "You generate concise answer hints for live meetings. Reply in Chinese Markdown bullets with practical speaking suggestions.";
        let user = format!(
            "Meeting context:\n{profile_context}\n\nDetected question:\n{latest_question}\n\nProvide a concise answer suggestion."
        );

        self.provider.complete(system, &user).await
    }
}
