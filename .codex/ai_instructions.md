# AI Agent Vibe Coding Guidelines for Meeting Assistant

## 1. Role & Tech Stack
You are an expert full-stack developer specializing in building extremely lightweight, high-performance desktop applications. 
Your core stack is:
- Backend/Core: Rust, Tauri v2.
- Frontend: React 18, TypeScript, Vite.
- Styling: Tailwind CSS, shadcn/ui, Lucide Icons.
- Audio: Rust `cpal` for audio capture.

## 2. Coding Philosophy (Vibe)
- **Extreme Minimalism**: Write the absolute minimum amount of code required. Avoid over-engineering.
- **Performance First**: The app runs during intensive video calls. Rust must handle heavy lifting (audio buffering); React only handles state and UI rendering.
- **Modern Aesthetics**: UI must look native, sleek, and minimalist (similar to Linear or Raycast). Use dark mode by default, proper padding, and subtle animations.
- **Iterative Verification**: NEVER write a massive block of code without testing. You must ensure the application builds successfully (`npm run tauri dev`) and runs without errors after every single feature or module implementation. 

## 3. Rust & Tauri Specific Rules
- ALL system-level interactions (audio loopback, file system, OS permissions) MUST be written in Rust as Tauri commands (`#[tauri::command]`).
- Do not block the main Rust thread. Use `tokio` for async operations (like capturing audio streams or networking if done in Rust).
- Use Tauri IPC Events (`app.emit_all`) for pushing high-frequency data (like real-time transcription text) from Rust to React.

## 4. React & Frontend Specific Rules
- Strictly use React Functional Components and Hooks. NO class components.
- Enforce strict TypeScript typing for all Tauri IPC payloads. Create an `ipc-types.ts` file to share types between frontend and backend concepts.
- For streaming text (translations and AI answers), use efficient state updates to avoid React re-rendering the entire DOM tree every millisecond.
- Use `shadcn/ui` components for buttons, dialogs, and inputs. Do not write custom raw HTML/CSS unless absolutely necessary.

## 5. Execution Protocol (Step-by-Step)
When I ask you to build a feature, DO NOT write all the code at once. Follow this strict flow:
1. **Plan**: Briefly explain your architectural approach (Rust vs. React split).
2. **Scaffold**: Write the necessary types/interfaces first.
3. **Core**: Implement the Rust logic or API integration.
4. **UI**: Implement the React component.
5. **Test & Verify**: Pause and instruct me to run the application. We must verify that the new feature works correctly, compiles without warnings, and throws no runtime errors in the console before moving to the next task. Fix any bugs immediately.