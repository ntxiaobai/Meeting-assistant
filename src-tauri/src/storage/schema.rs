use serde::{Deserialize, Serialize};

use crate::models::{MeetingProfile, UserPreferences};

pub const CURRENT_SCHEMA_VERSION: u32 = 4;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PersistedState {
    pub schema_version: u32,
    #[serde(default)]
    pub meeting_profiles: Vec<MeetingProfile>,
    #[serde(default)]
    pub user_preferences: UserPreferences,
}

impl Default for PersistedState {
    fn default() -> Self {
        Self {
            schema_version: CURRENT_SCHEMA_VERSION,
            meeting_profiles: Vec::new(),
            user_preferences: UserPreferences::default(),
        }
    }
}
