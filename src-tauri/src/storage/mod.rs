use std::{path::PathBuf, sync::Arc};

use anyhow::Result;

use crate::models::{AttachmentRecord, MeetingProfile, MeetingProfileUpsert, UserPreferences};

pub mod json_repo;
pub mod schema;

use json_repo::JsonProfileRepository;

pub trait ProfileRepository: Send + Sync {
    fn migrate_if_needed(&self) -> Result<()>;
    fn list_profiles(&self) -> Result<Vec<MeetingProfile>>;
    fn upsert_profile(&self, input: MeetingProfileUpsert) -> Result<MeetingProfile>;
    fn delete_profile(&self, id: &str) -> Result<()>;
    fn add_attachment(&self, attachment: AttachmentRecord) -> Result<AttachmentRecord>;
    fn find_profile(&self, profile_id: &str) -> Result<Option<MeetingProfile>>;
    fn get_user_preferences(&self) -> Result<UserPreferences>;
    fn save_user_preferences(&self, input: UserPreferences) -> Result<UserPreferences>;
}

impl ProfileRepository for JsonProfileRepository {
    fn migrate_if_needed(&self) -> Result<()> {
        self.migrate_if_needed()
    }

    fn list_profiles(&self) -> Result<Vec<MeetingProfile>> {
        self.list_profiles()
    }

    fn upsert_profile(&self, input: MeetingProfileUpsert) -> Result<MeetingProfile> {
        self.upsert_profile(input)
    }

    fn delete_profile(&self, id: &str) -> Result<()> {
        self.delete_profile(id)
    }

    fn add_attachment(&self, attachment: AttachmentRecord) -> Result<AttachmentRecord> {
        self.add_attachment(attachment)
    }

    fn find_profile(&self, profile_id: &str) -> Result<Option<MeetingProfile>> {
        self.find_profile(profile_id)
    }

    fn get_user_preferences(&self) -> Result<UserPreferences> {
        self.get_user_preferences()
    }

    fn save_user_preferences(&self, input: UserPreferences) -> Result<UserPreferences> {
        self.save_user_preferences(input)
    }
}

#[derive(Clone)]
pub struct StorageService {
    repo: Arc<dyn ProfileRepository>,
}

impl StorageService {
    pub fn new(base_dir: PathBuf) -> Self {
        let repo = JsonProfileRepository::new(base_dir);
        Self {
            repo: Arc::new(repo),
        }
    }

    pub fn migrate_if_needed(&self) -> Result<()> {
        self.repo.migrate_if_needed()
    }

    pub fn list_profiles(&self) -> Result<Vec<MeetingProfile>> {
        self.repo.list_profiles()
    }

    pub fn save_profile(&self, input: MeetingProfileUpsert) -> Result<MeetingProfile> {
        self.repo.upsert_profile(input)
    }

    pub fn delete_profile(&self, id: &str) -> Result<()> {
        self.repo.delete_profile(id)
    }

    pub fn add_attachment(&self, attachment: AttachmentRecord) -> Result<AttachmentRecord> {
        self.repo.add_attachment(attachment)
    }

    pub fn find_profile(&self, profile_id: &str) -> Result<Option<MeetingProfile>> {
        self.repo.find_profile(profile_id)
    }

    pub fn get_user_preferences(&self) -> Result<UserPreferences> {
        self.repo.get_user_preferences()
    }

    pub fn save_user_preferences(&self, input: UserPreferences) -> Result<UserPreferences> {
        self.repo.save_user_preferences(input)
    }
}
