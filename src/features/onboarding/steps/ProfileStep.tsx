import { ProfileManager } from "../../profiles/ProfileManager";
import type { MeetingProfile } from "../../../types/ipc-types";

interface ProfileStepProps {
  profiles: MeetingProfile[];
  selectedProfileId: string;
  onSelectProfile: (id: string) => void;
  onProfilesChanged: () => Promise<void>;
  onError: (message: string) => void;
}

export function ProfileStep({
  profiles,
  selectedProfileId,
  onSelectProfile,
  onProfilesChanged,
  onError,
}: ProfileStepProps) {
  return (
    <ProfileManager
      profiles={profiles}
      selectedProfileId={selectedProfileId}
      onSelectProfile={onSelectProfile}
      onProfilesChanged={onProfilesChanged}
      onError={onError}
    />
  );
}
