import { useEffect, useMemo, useState } from "react";
import { Card, CardTitle } from "../../components/ui/card";
import { Button } from "../../components/ui/button";
import { Input } from "../../components/ui/input";
import { Select } from "../../components/ui/select";
import { Textarea } from "../../components/ui/textarea";
import {
  deleteMeetingProfile,
  extractAttachmentText,
  saveMeetingProfile,
} from "../../lib/tauri-ipc";
import { useI18n } from "../../i18n/provider";
import type {
  AttachmentFileType,
  MeetingProfile,
  MeetingProfileUpsert,
} from "../../types/ipc-types";

interface ProfileManagerProps {
  profiles: MeetingProfile[];
  selectedProfileId: string;
  onSelectProfile: (profileId: string) => void;
  onProfilesChanged: () => Promise<void>;
  onError: (message: string) => void;
}

const initialProfileForm: MeetingProfileUpsert = {
  name: "",
  meetingType: "",
  domain: "",
  language: "en-US",
  selfIntro: "",
  contextNotes: "",
};

export function ProfileManager({
  profiles,
  selectedProfileId,
  onSelectProfile,
  onProfilesChanged,
  onError,
}: ProfileManagerProps) {
  const { t } = useI18n();
  const selectedProfile = useMemo(
    () => profiles.find((profile) => profile.id === selectedProfileId),
    [profiles, selectedProfileId],
  );

  const [form, setForm] = useState<MeetingProfileUpsert>(initialProfileForm);
  const [attachmentPath, setAttachmentPath] = useState("");
  const [attachmentType, setAttachmentType] = useState<AttachmentFileType>("txt");
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    if (!selectedProfile) {
      setForm(initialProfileForm);
      return;
    }

    setForm({
      id: selectedProfile.id,
      name: selectedProfile.name,
      meetingType: selectedProfile.meetingType,
      domain: selectedProfile.domain,
      language: selectedProfile.language,
      selfIntro: selectedProfile.selfIntro,
      contextNotes: selectedProfile.contextNotes,
    });
  }, [selectedProfile]);

  async function handleSaveProfile() {
    if (!form.name.trim()) {
      onError("Meeting profile name is required.");
      return;
    }

    setIsSaving(true);
    try {
      const saved = await saveMeetingProfile(form);
      await onProfilesChanged();
      onSelectProfile(saved.id);
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  async function handleDeleteProfile() {
    if (!selectedProfile) {
      return;
    }

    setIsSaving(true);
    try {
      await deleteMeetingProfile(selectedProfile.id);
      await onProfilesChanged();
      const next = profiles.find((profile) => profile.id !== selectedProfile.id);
      onSelectProfile(next?.id ?? "");
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  async function handleExtractAttachment() {
    if (!selectedProfile?.id) {
      onError("Please save or select a profile before adding attachments.");
      return;
    }
    if (!attachmentPath.trim()) {
      onError("Attachment path is required.");
      return;
    }

    setIsSaving(true);
    try {
      await extractAttachmentText({
        profileId: selectedProfile.id,
        filePath: attachmentPath.trim(),
        fileType: attachmentType,
      });
      setAttachmentPath("");
      await onProfilesChanged();
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <Card>
      <CardTitle>{t("profile.title")}</CardTitle>
      <div className="section-list profile-list">
        {profiles.map((profile) => (
          <button
            key={profile.id}
            className={profile.id === selectedProfileId ? "pill active" : "pill"}
            onClick={() => onSelectProfile(profile.id)}
            type="button"
          >
            {profile.name}
          </button>
        ))}
      </div>

      <div className="section-list compact-gap">
        <Input
          placeholder="Profile name"
          value={form.name}
          onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))}
        />
        <Input
          placeholder="Meeting type (e.g. tech interview)"
          value={form.meetingType}
          onChange={(event) =>
            setForm((prev) => ({ ...prev, meetingType: event.target.value }))
          }
        />
        <Input
          placeholder="Domain"
          value={form.domain}
          onChange={(event) => setForm((prev) => ({ ...prev, domain: event.target.value }))}
        />
        <Input
          placeholder="Language (e.g. en-US)"
          value={form.language}
          onChange={(event) => setForm((prev) => ({ ...prev, language: event.target.value }))}
        />
        <Textarea
          placeholder="Self introduction"
          rows={3}
          value={form.selfIntro}
          onChange={(event) =>
            setForm((prev) => ({ ...prev, selfIntro: event.target.value }))
          }
        />
        <Textarea
          placeholder="Context notes"
          rows={4}
          value={form.contextNotes}
          onChange={(event) =>
            setForm((prev) => ({ ...prev, contextNotes: event.target.value }))
          }
        />
      </div>

      <div className="button-row">
        <Button onClick={handleSaveProfile} disabled={isSaving}>
          {selectedProfile ? "Update" : "Create"}
        </Button>
        <Button onClick={() => setForm(initialProfileForm)} variant="secondary" disabled={isSaving}>
          Reset
        </Button>
        <Button onClick={handleDeleteProfile} variant="danger" disabled={!selectedProfile || isSaving}>
          Delete
        </Button>
      </div>

      <div className="separator" />

      <div className="section-list compact-gap">
        <label className="field-label">Attachment extraction</label>
        <Input
          placeholder="Absolute file path (.txt/.pdf)"
          value={attachmentPath}
          onChange={(event) => setAttachmentPath(event.target.value)}
        />
        <Select
          value={attachmentType}
          onChange={(event) => setAttachmentType(event.target.value as AttachmentFileType)}
        >
          <option value="txt">TXT</option>
          <option value="pdf">PDF</option>
        </Select>
        <Button onClick={handleExtractAttachment} disabled={isSaving}>
          Extract
        </Button>
      </div>

      {selectedProfile?.attachments.length ? (
        <ul className="section-list attachment-list">
          {selectedProfile.attachments.map((attachment) => (
            <li key={attachment.id}>
              <span className="mono">{attachment.fileType.toUpperCase()}</span>
              <span className="truncate">{attachment.filePath}</span>
            </li>
          ))}
        </ul>
      ) : null}
    </Card>
  );
}
