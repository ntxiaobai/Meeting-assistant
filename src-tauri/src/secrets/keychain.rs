use anyhow::Result;
use keyring::{Entry, Error as KeyringError};

use crate::models::{ProviderKind, ProviderSecretField, ProviderStatus};

#[derive(Clone)]
pub struct KeychainStore {
    service_name: String,
}

impl KeychainStore {
    pub fn new(service_name: impl Into<String>) -> Self {
        Self {
            service_name: service_name.into(),
        }
    }

    pub fn save_provider_key(&self, provider: ProviderKind, api_key: &str) -> Result<()> {
        self.save_provider_secret(provider, ProviderSecretField::ApiKey, api_key)
    }

    pub fn get_provider_key(&self, provider: ProviderKind) -> Result<Option<String>> {
        self.get_provider_secret(provider, ProviderSecretField::ApiKey)
    }

    pub fn save_provider_secret(
        &self,
        provider: ProviderKind,
        field: ProviderSecretField,
        value: &str,
    ) -> Result<()> {
        let entry = self.entry(provider, field)?;
        entry.set_password(value)?;
        Ok(())
    }

    pub fn get_provider_secret(
        &self,
        provider: ProviderKind,
        field: ProviderSecretField,
    ) -> Result<Option<String>> {
        let entry = self.entry(provider, field)?;
        match entry.get_password() {
            Ok(value) => Ok(Some(value)),
            Err(KeyringError::NoEntry) => Ok(None),
            Err(error) => Err(error.into()),
        }
    }

    pub fn provider_status(&self) -> ProviderStatus {
        let aliyun = self.has_secret(ProviderKind::Aliyun, ProviderSecretField::AccessKeyId)
            && self.has_secret(ProviderKind::Aliyun, ProviderSecretField::AccessKeySecret)
            && self.has_secret(ProviderKind::Aliyun, ProviderSecretField::AppKey);

        ProviderStatus {
            aliyun,
            deepgram: self.has_key(ProviderKind::Deepgram),
            claude: self.has_key(ProviderKind::Claude),
            gemini: self.has_key(ProviderKind::Gemini),
            openai: self.has_key(ProviderKind::Openai),
            custom_llm: self.has_key(ProviderKind::CustomLlm),
        }
    }

    fn has_key(&self, provider: ProviderKind) -> bool {
        self.has_secret(provider, ProviderSecretField::ApiKey)
    }

    fn has_secret(&self, provider: ProviderKind, field: ProviderSecretField) -> bool {
        match self.entry(provider, field) {
            Ok(entry) => entry.get_password().is_ok(),
            Err(_) => false,
        }
    }

    fn entry(&self, provider: ProviderKind, field: ProviderSecretField) -> Result<Entry> {
        let account = format!("{}:{}", provider.as_key(), field.as_key());
        Entry::new(&self.service_name, &account)
            .map_err(|error| anyhow::anyhow!("keychain entry creation failed: {error}"))
    }
}
