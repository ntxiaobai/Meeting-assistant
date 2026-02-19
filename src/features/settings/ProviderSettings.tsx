import { useEffect, useMemo, useState } from "react";
import { Button } from "../../components/ui/button";
import { Card, CardTitle } from "../../components/ui/card";
import { Input } from "../../components/ui/input";
import { Select } from "../../components/ui/select";
import { useI18n } from "../../i18n/provider";
import { saveLlmSettings, saveProviderKey, saveProviderSecret } from "../../lib/tauri-ipc";
import type { LlmProviderKind, LlmSettings, ProviderKind, ProviderStatus } from "../../types/ipc-types";

interface ProviderSettingsProps {
  providerStatus: ProviderStatus;
  llmSettings: LlmSettings;
  onSaved: () => Promise<void>;
  onError: (message: string) => void;
}

export function ProviderSettings({ providerStatus, llmSettings, onSaved, onError }: ProviderSettingsProps) {
  const { t } = useI18n();
  const [aliyunAccessKeyId, setAliyunAccessKeyId] = useState("");
  const [aliyunAccessKeySecret, setAliyunAccessKeySecret] = useState("");
  const [aliyunAppKey, setAliyunAppKey] = useState("");
  const [deepgramKey, setDeepgramKey] = useState("");
  const [claudeKey, setClaudeKey] = useState("");
  const [openaiKey, setOpenaiKey] = useState("");
  const [customLlmKey, setCustomLlmKey] = useState("");
  const [llmDraft, setLlmDraft] = useState<LlmSettings>(llmSettings);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    setLlmDraft(llmSettings);
  }, [llmSettings]);

  const activeLlmProviderStatus = useMemo(() => {
    switch (llmDraft.provider) {
      case "anthropic":
        return providerStatus.claude;
      case "openai":
        return providerStatus.openai;
      case "custom":
        return providerStatus.customLlm;
      default:
        return false;
    }
  }, [llmDraft.provider, providerStatus]);

  async function saveAliyun() {
    if (!aliyunAccessKeyId.trim() || !aliyunAccessKeySecret.trim() || !aliyunAppKey.trim()) {
      onError("Aliyun AccessKeyId / AccessKeySecret / AppKey are required.");
      return;
    }

    setIsSaving(true);
    try {
      await saveProviderSecret({
        provider: "aliyun",
        field: "access_key_id",
        value: aliyunAccessKeyId.trim(),
      });
      await saveProviderSecret({
        provider: "aliyun",
        field: "access_key_secret",
        value: aliyunAccessKeySecret.trim(),
      });
      await saveProviderSecret({
        provider: "aliyun",
        field: "app_key",
        value: aliyunAppKey.trim(),
      });
      setAliyunAccessKeyId("");
      setAliyunAccessKeySecret("");
      setAliyunAppKey("");
      await onSaved();
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  async function saveDeepgram() {
    if (!deepgramKey.trim()) {
      onError("Deepgram API Key is required.");
      return;
    }

    setIsSaving(true);
    try {
      await saveProviderKey({ provider: "deepgram", apiKey: deepgramKey.trim() });
      setDeepgramKey("");
      await onSaved();
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  async function saveClaude() {
    if (!claudeKey.trim()) {
      onError("Anthropic API Key is required.");
      return;
    }

    setIsSaving(true);
    try {
      await saveProviderKey({ provider: "claude", apiKey: claudeKey.trim() });
      setClaudeKey("");
      await onSaved();
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  async function saveOpenAi() {
    if (!openaiKey.trim()) {
      onError("OpenAI API Key is required.");
      return;
    }

    setIsSaving(true);
    try {
      await saveProviderKey({ provider: "openai", apiKey: openaiKey.trim() });
      setOpenaiKey("");
      await onSaved();
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  async function saveCustomLlmKey() {
    if (!customLlmKey.trim()) {
      onError("Custom LLM API Key is required.");
      return;
    }

    setIsSaving(true);
    try {
      await saveProviderKey({ provider: "custom_llm", apiKey: customLlmKey.trim() });
      setCustomLlmKey("");
      await onSaved();
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  async function saveLlmProviderConfig() {
    if (!llmDraft.model.trim()) {
      onError("Model is required.");
      return;
    }

    if (llmDraft.provider === "custom" && !llmDraft.baseUrl?.trim()) {
      onError("Custom provider requires base URL.");
      return;
    }

    setIsSaving(true);
    try {
      await saveLlmSettings({
        provider: llmDraft.provider,
        model: llmDraft.model.trim(),
        apiFormat: llmDraft.apiFormat,
        baseUrl: llmDraft.baseUrl?.trim() || undefined,
      });
      await onSaved();
    } catch (error) {
      onError(String(error));
    } finally {
      setIsSaving(false);
    }
  }

  function setProvider(provider: LlmProviderKind) {
    setLlmDraft((prev) => {
      if (provider === "anthropic") {
        return {
          ...prev,
          provider,
          apiFormat: "anthropic",
          baseUrl: prev.baseUrl ?? "https://api.anthropic.com/v1",
          model: prev.model || "claude-3-5-sonnet-latest",
        };
      }
      if (provider === "openai") {
        return {
          ...prev,
          provider,
          apiFormat: "openai",
          baseUrl: prev.baseUrl ?? "https://api.openai.com/v1",
          model: prev.model || "gpt-4o-mini",
        };
      }
      return {
        ...prev,
        provider,
      };
    });
  }

  const keyBinding: Record<LlmProviderKind, ProviderKind> = {
    anthropic: "claude",
    openai: "openai",
    custom: "custom_llm",
  };

  return (
    <Card className="provider-settings-card">
      <CardTitle>{t("provider.title")}</CardTitle>

      <div className="provider-split">
        <section className="provider-column">
          <h4 className="sub-title">{t("provider.realtimeAsr")}</h4>

          <div className="section-list compact-gap">
            <label className="field-label">
              {t("provider.aliyun")}{" "}
              <span className="status-dot">
                {providerStatus.aliyun ? t("provider.configured") : t("provider.missing")}
              </span>
            </label>
            <Input
              placeholder="AccessKeyId"
              value={aliyunAccessKeyId}
              onChange={(event) => setAliyunAccessKeyId(event.target.value)}
            />
            <Input
              placeholder="AccessKeySecret"
              value={aliyunAccessKeySecret}
              onChange={(event) => setAliyunAccessKeySecret(event.target.value)}
            />
            <Input
              placeholder="AppKey"
              value={aliyunAppKey}
              onChange={(event) => setAliyunAppKey(event.target.value)}
            />
            <Button onClick={saveAliyun} disabled={isSaving}>
              {t("provider.saveAliyun")}
            </Button>
          </div>

          <div className="separator" />

          <div className="section-list compact-gap">
            <label className="field-label">
              {t("provider.deepgram")}{" "}
              <span className="status-dot">
                {providerStatus.deepgram ? t("provider.configured") : t("provider.missing")}
              </span>
            </label>
            <Input
              placeholder="Deepgram API Key"
              value={deepgramKey}
              onChange={(event) => setDeepgramKey(event.target.value)}
            />
            <Button onClick={saveDeepgram} disabled={isSaving}>
              {t("provider.saveDeepgram")}
            </Button>
          </div>
        </section>

        <section className="provider-column">
          <h4 className="sub-title">{t("provider.hintLlm")}</h4>

          <div className="section-list compact-gap">
            <label className="field-label">{t("provider.llmProvider")}</label>
            <Select
              value={llmDraft.provider}
              onChange={(event) => setProvider(event.target.value as LlmProviderKind)}
            >
              <option value="anthropic">Anthropic</option>
              <option value="openai">OpenAI</option>
              <option value="custom">Custom</option>
            </Select>
          </div>

          <div className="section-list compact-gap">
            <label className="field-label">{t("provider.llmModel")}</label>
            <Input
              placeholder="Model name"
              value={llmDraft.model}
              onChange={(event) => setLlmDraft((prev) => ({ ...prev, model: event.target.value }))}
            />
          </div>

          {llmDraft.provider === "custom" ? (
            <>
              <div className="section-list compact-gap">
                <label className="field-label">{t("provider.apiFormat")}</label>
                <Select
                  value={llmDraft.apiFormat}
                  onChange={(event) =>
                    setLlmDraft((prev) => ({
                      ...prev,
                      apiFormat: event.target.value as "openai" | "anthropic",
                    }))
                  }
                >
                  <option value="openai">OpenAI Compatible</option>
                  <option value="anthropic">Anthropic Compatible</option>
                </Select>
              </div>
              <div className="section-list compact-gap">
                <label className="field-label">{t("provider.baseUrl")}</label>
                <Input
                  placeholder="https://your-endpoint.example.com/v1"
                  value={llmDraft.baseUrl ?? ""}
                  onChange={(event) =>
                    setLlmDraft((prev) => ({
                      ...prev,
                      baseUrl: event.target.value,
                    }))
                  }
                />
              </div>
            </>
          ) : (
            <div className="section-list compact-gap">
              <label className="field-label">{t("provider.baseUrlOverride")}</label>
              <Input
                placeholder={
                  llmDraft.provider === "anthropic"
                    ? "https://api.anthropic.com/v1"
                    : "https://api.openai.com/v1"
                }
                value={llmDraft.baseUrl ?? ""}
                onChange={(event) =>
                  setLlmDraft((prev) => ({
                    ...prev,
                    baseUrl: event.target.value || undefined,
                  }))
                }
              />
            </div>
          )}

          <Button onClick={saveLlmProviderConfig} disabled={isSaving}>
            {t("provider.saveLlmConfig")}
          </Button>

          <div className="separator" />

          <div className="section-list compact-gap">
            <label className="field-label">
              {t("provider.activeApiKey")}{" "}
              <span className="status-dot">
                {activeLlmProviderStatus ? t("provider.configured") : t("provider.missing")}
              </span>
            </label>

            {llmDraft.provider === "anthropic" ? (
              <>
                <Input
                  placeholder="Anthropic API Key"
                  value={claudeKey}
                  onChange={(event) => setClaudeKey(event.target.value)}
                />
                <Button onClick={saveClaude} disabled={isSaving}>
                  {t("provider.saveAnthropicKey")}
                </Button>
              </>
            ) : null}

            {llmDraft.provider === "openai" ? (
              <>
                <Input
                  placeholder="OpenAI API Key"
                  value={openaiKey}
                  onChange={(event) => setOpenaiKey(event.target.value)}
                />
                <Button onClick={saveOpenAi} disabled={isSaving}>
                  {t("provider.saveOpenAiKey")}
                </Button>
              </>
            ) : null}

            {llmDraft.provider === "custom" ? (
              <>
                <Input
                  placeholder="Custom LLM API Key"
                  value={customLlmKey}
                  onChange={(event) => setCustomLlmKey(event.target.value)}
                />
                <Button onClick={saveCustomLlmKey} disabled={isSaving}>
                  {t("provider.saveCustomKey")}
                </Button>
              </>
            ) : null}
          </div>

          <p className="muted">
            {t("provider.activeSlot")}: <span className="mono">{keyBinding[llmDraft.provider]}</span>
          </p>
        </section>
      </div>
    </Card>
  );
}
