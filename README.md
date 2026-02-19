# Meeting Assistant MVP

A lightweight Tauri desktop app for live meeting support:

- Meeting profile management (context + attachments)
- Microphone-first real-time transcription pipeline (Deepgram)
- Chinese translation and answer-hint generation (Claude optional)
- Teleprompter window controls (always-on-top/opacity/click-through)

## Stack

- Desktop: Tauri v2 + Rust
- Frontend: React + TypeScript + Vite
- Audio: `cpal`
- Storage: local JSON (schema versioned, SQLite migration hook reserved)
- Secrets: system keychain

## Environment

The app expects provider keys at runtime:

- Deepgram API key (required for transcription)
- Claude API key (optional for translation/hint generation)

Keys are saved via UI into OS keychain.

## Run

```bash
npm run build
npm run tauri dev
```

## Notes

- MVP currently runs in microphone-only mode.
- System loopback capture is intentionally stubbed for phase 2.
