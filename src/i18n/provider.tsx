import { createContext, useContext, type ReactNode } from "react";
import { lookupMessage } from "./messages";
import type { LocaleCode } from "../types/ipc-types";

interface I18nContextValue {
  locale: LocaleCode;
  t: (key: string) => string;
}

const I18nContext = createContext<I18nContextValue>({
  locale: "en-US",
  t: (key) => key,
});

interface I18nProviderProps {
  locale: LocaleCode;
  children: ReactNode;
}

export function I18nProvider({ locale, children }: I18nProviderProps) {
  return (
    <I18nContext.Provider
      value={{
        locale,
        t: (key) => lookupMessage(locale, key),
      }}
    >
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  return useContext(I18nContext);
}
