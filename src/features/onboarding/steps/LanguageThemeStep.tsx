import { Card, CardTitle } from "../../../components/ui/card";
import { Select } from "../../../components/ui/select";
import { useI18n } from "../../../i18n/provider";
import type { LocaleCode, PlatformStyle, ThemeMode } from "../../../types/ipc-types";

interface LanguageThemeStepProps {
  locale: LocaleCode;
  themeMode: ThemeMode;
  platformStyle: PlatformStyle;
  onLocaleChange: (locale: LocaleCode) => void;
  onThemeModeChange: (themeMode: ThemeMode) => void;
}

export function LanguageThemeStep({
  locale,
  themeMode,
  platformStyle,
  onLocaleChange,
  onThemeModeChange,
}: LanguageThemeStepProps) {
  const { t } = useI18n();

  return (
    <Card>
      <CardTitle>{t("wizard.step1")}</CardTitle>
      <div className="section-list compact-gap">
        <label className="field-label">{t("settings.language")}</label>
        <Select value={locale} onChange={(event) => onLocaleChange(event.target.value as LocaleCode)}>
          <option value="zh-CN">{t("locale.zh-CN")}</option>
          <option value="en-US">{t("locale.en-US")}</option>
        </Select>
      </div>

      <div className="section-list compact-gap">
        <label className="field-label">{t("settings.theme")}</label>
        <Select value={themeMode} onChange={(event) => onThemeModeChange(event.target.value as ThemeMode)}>
          <option value="system">{t("theme.system")}</option>
          <option value="light">{t("theme.light")}</option>
          <option value="dark">{t("theme.dark")}</option>
        </Select>
      </div>

      <p className="muted">{t("settings.platformStyle")}: {platformStyle}</p>
    </Card>
  );
}
