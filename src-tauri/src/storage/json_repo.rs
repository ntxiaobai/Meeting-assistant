use std::{fs, path::PathBuf};

use anyhow::{Context, Result};
use chrono::{SecondsFormat, Utc};
use uuid::Uuid;

use crate::models::{AttachmentRecord, MeetingProfile, MeetingProfileUpsert, UserPreferences};

use super::schema::{PersistedState, CURRENT_SCHEMA_VERSION};

#[derive(Clone)]
pub struct JsonProfileRepository {
    db_path: PathBuf,
}

impl JsonProfileRepository {
    pub fn new(base_dir: PathBuf) -> Self {
        Self {
            db_path: base_dir.join("meeting-assistant-state.json"),
        }
    }

    pub fn migrate_if_needed(&self) -> Result<()> {
        let mut state = self.read_state()?;
        if state.schema_version < CURRENT_SCHEMA_VERSION {
            state.schema_version = CURRENT_SCHEMA_VERSION;
            self.write_state(&state)?;
        }
        Ok(())
    }

    pub fn list_profiles(&self) -> Result<Vec<MeetingProfile>> {
        Ok(self.read_state()?.meeting_profiles)
    }

    pub fn upsert_profile(&self, input: MeetingProfileUpsert) -> Result<MeetingProfile> {
        let mut state = self.read_state()?;
        let now = now_iso();

        if let Some(id) = &input.id {
            if let Some(profile) = state.meeting_profiles.iter_mut().find(|p| p.id == *id) {
                profile.name = input.name;
                profile.meeting_type = input.meeting_type;
                profile.domain = input.domain;
                profile.language = input.language;
                profile.self_intro = input.self_intro;
                profile.context_notes = input.context_notes;
                profile.updated_at = now;

                let result = profile.clone();
                self.write_state(&state)?;
                return Ok(result);
            }
        }

        let profile = MeetingProfile {
            id: input.id.unwrap_or_else(|| Uuid::new_v4().to_string()),
            name: input.name,
            meeting_type: input.meeting_type,
            domain: input.domain,
            language: input.language,
            self_intro: input.self_intro,
            context_notes: input.context_notes,
            attachments: Vec::new(),
            created_at: now.clone(),
            updated_at: now,
        };

        state.meeting_profiles.push(profile.clone());
        self.write_state(&state)?;
        Ok(profile)
    }

    pub fn delete_profile(&self, id: &str) -> Result<()> {
        let mut state = self.read_state()?;
        state.meeting_profiles.retain(|profile| profile.id != id);
        self.write_state(&state)
    }

    pub fn add_attachment(&self, attachment: AttachmentRecord) -> Result<AttachmentRecord> {
        let mut state = self.read_state()?;

        let profile = state
            .meeting_profiles
            .iter_mut()
            .find(|profile| profile.id == attachment.profile_id)
            .with_context(|| format!("meeting profile not found: {}", attachment.profile_id))?;

        profile.attachments.push(attachment.clone());
        profile.updated_at = now_iso();

        self.write_state(&state)?;
        Ok(attachment)
    }

    pub fn find_profile(&self, profile_id: &str) -> Result<Option<MeetingProfile>> {
        let state = self.read_state()?;
        Ok(state
            .meeting_profiles
            .into_iter()
            .find(|profile| profile.id == profile_id))
    }

    pub fn get_user_preferences(&self) -> Result<UserPreferences> {
        Ok(self.read_state()?.user_preferences)
    }

    pub fn save_user_preferences(&self, input: UserPreferences) -> Result<UserPreferences> {
        let mut state = self.read_state()?;
        state.user_preferences = input.clone();
        self.write_state(&state)?;
        Ok(input)
    }

    fn read_state(&self) -> Result<PersistedState> {
        self.ensure_store_exists()?;
        let raw = fs::read_to_string(&self.db_path)
            .with_context(|| format!("failed to read {}", self.db_path.display()))?;

        if raw.trim().is_empty() {
            return Ok(PersistedState::default());
        }

        serde_json::from_str(&raw).with_context(|| {
            format!(
                "failed to deserialize meeting assistant state from {}",
                self.db_path.display()
            )
        })
    }

    fn write_state(&self, state: &PersistedState) -> Result<()> {
        self.ensure_parent_dir()?;
        let tmp_path = self.db_path.with_extension("tmp");

        let serialized = serde_json::to_string_pretty(state)?;
        fs::write(&tmp_path, serialized)
            .with_context(|| format!("failed to write {}", tmp_path.display()))?;
        fs::rename(&tmp_path, &self.db_path).with_context(|| {
            format!(
                "failed to atomically move {} to {}",
                tmp_path.display(),
                self.db_path.display()
            )
        })?;

        Ok(())
    }

    fn ensure_store_exists(&self) -> Result<()> {
        if self.db_path.exists() {
            return Ok(());
        }

        self.ensure_parent_dir()?;
        self.write_state(&PersistedState::default())
    }

    fn ensure_parent_dir(&self) -> Result<()> {
        if let Some(parent) = self.db_path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
        Ok(())
    }
}

fn now_iso() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true)
}
