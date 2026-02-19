use anyhow::Result;

use crate::models::{ProviderKind, ProviderSecretField, ProviderStatus};

pub mod keychain;

use keychain::KeychainStore;

#[derive(Debug, Clone)]
pub struct AliyunSecrets {
    pub access_key_id: String,
    pub access_key_secret: String,
    pub app_key: String,
}

#[derive(Clone)]
pub struct SecretService {
    store: KeychainStore,
}

impl SecretService {
    pub fn new(service_name: impl Into<String>) -> Self {
        Self {
            store: KeychainStore::new(service_name),
        }
    }

    pub fn save_provider_key(&self, provider: ProviderKind, api_key: &str) -> Result<()> {
        self.store.save_provider_key(provider, api_key)
    }

    pub fn get_provider_key(&self, provider: ProviderKind) -> Result<Option<String>> {
        self.store.get_provider_key(provider)
    }

    pub fn save_provider_secret(
        &self,
        provider: ProviderKind,
        field: ProviderSecretField,
        value: &str,
    ) -> Result<()> {
        self.store.save_provider_secret(provider, field, value)
    }

    pub fn get_aliyun_secrets(&self) -> Result<Option<AliyunSecrets>> {
        let access_key_id = self
            .store
            .get_provider_secret(ProviderKind::Aliyun, ProviderSecretField::AccessKeyId)?;
        let access_key_secret = self
            .store
            .get_provider_secret(ProviderKind::Aliyun, ProviderSecretField::AccessKeySecret)?;
        let app_key = self
            .store
            .get_provider_secret(ProviderKind::Aliyun, ProviderSecretField::AppKey)?;

        match (access_key_id, access_key_secret, app_key) {
            (Some(access_key_id), Some(access_key_secret), Some(app_key)) => {
                Ok(Some(AliyunSecrets {
                    access_key_id,
                    access_key_secret,
                    app_key,
                }))
            }
            _ => Ok(None),
        }
    }

    pub fn provider_status(&self) -> ProviderStatus {
        self.store.provider_status()
    }
}
