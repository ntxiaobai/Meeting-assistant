import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./index.css";
import { LiveOverlayApp } from "./features/live-overlay/LiveOverlayApp";
import { I18nProvider } from "./i18n/provider";
import { getBootstrapState } from "./lib/tauri-ipc";
import type { LocaleCode } from "./types/ipc-types";

function OverlayRoot() {
  const [locale, setLocale] = React.useState<LocaleCode>("en-US");

  React.useEffect(() => {
    void getBootstrapState()
      .then((state) => setLocale(state.locale))
      .catch(() => {
        setLocale(navigator.language.toLowerCase().startsWith("zh") ? "zh-CN" : "en-US");
      });
  }, []);

  return (
    <I18nProvider locale={locale}>
      <LiveOverlayApp />
    </I18nProvider>
  );
}

const windowKind = new URLSearchParams(window.location.search).get("window");
const isOverlayWindow = windowKind === "live_overlay";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>{isOverlayWindow ? <OverlayRoot /> : <App />}</React.StrictMode>,
);
