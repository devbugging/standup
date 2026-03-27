# Daily Standup

A lightweight macOS menu bar app that records your daily standup via voice, transcribes it with AI, and pushes structured notes to a shared git repo.

## What it does

1. **Daily reminder** -- pops a notification at your configured time (default 4 PM)
2. **Voice recording** -- click Record, describe what you did and what's next
3. **AI processing** -- transcribes audio (OpenAI Whisper), then structures your notes into clean bullet points with correct project names (GPT-4o-mini)
4. **Git push** -- writes to `standup.md` and `todo.md`, commits, and pushes
5. **Daily to-do viewer** -- shows your pending tasks, organized and prioritized by AI, cached so it opens instantly

## Requirements

- macOS 14 (Sonoma) or later
- An [OpenAI API key](https://platform.openai.com/api-keys) (used for both transcription and note structuring)
- A git repo with a specific folder structure (see below)

## Setup

### 1. Open the app

```bash
open build/DailyStandup.app
```

Or build from source in Xcode (`DailyStandup.xcodeproj`).

A microphone icon appears in your menu bar. On first launch, Settings opens automatically.

### 2. Configure settings

| Setting | What to enter |
|---|---|
| **Name** | Your name (e.g. `Greg`). Used to group standup entries by person. |
| **Roles** | What you do (e.g. `Development, Marketing`). Shown next to your name in notes. |
| **OpenAI API Key** | Your `sk-...` key. Powers both voice transcription and note formatting. |
| **Microphone** | Pick your input device. If recording is silent, try a different one. |
| **Daily Reminder** | Hour and minute for the daily notification (24h format). |
| **Repository Path** | Path to your projects repo on disk (see below). |
| **Launch at Login** | Start automatically when your Mac boots. |

Click **Save & Update** when done.

### 3. Set up your projects repo

The app expects a git repo with this structure:

```
your-repo/
  projects/
    standup.md      <-- daily standup notes (auto-updated)
    todo.md         <-- to-do list (auto-updated)
    ProjectAlpha/   <-- each folder = a project name
    ProjectBeta/
    SomeClient/
    ...
```

**The folder names matter.** Each subfolder inside `projects/` is treated as a project name. When you mention a project during your standup recording, the AI matches your words to these exact folder names.

You can put anything inside each project folder (docs, briefs, notes) -- the app only reads the folder names.

Point the **Repository Path** setting to the root of this repo (e.g. `/Users/you/Dev/projects`).

## Usage

### Recording a standup

1. Click the menu bar icon > **Start Standup** (or use the daily notification)
2. Read the instructions, then click the red **Record** button
3. Speak naturally:
   - **What you worked on today** -- mention project names for auto-tagging
   - **Any blockers** you're facing
   - Say **"todos"** then list what still needs to be done
4. Click **Complete** when finished
5. Review the AI-structured notes -- edit if needed
6. Click **Confirm & Push** to commit and push to the repo

### Viewing your daily to-do

Click the menu bar icon > **Show Daily To-Do**

This shows all your pending (unchecked) tasks from `todo.md`, organized by project and priority. The list is processed by AI once per day (on app launch or wake from sleep) and cached, so it opens instantly.

Click the refresh button to re-process if you've made manual changes.

### Multi-user support

Multiple people can use this app on the same repo. Each person's entries are grouped under their name:

**standup.md:**
```markdown
## 2026-03-27

### Greg (Development, Marketing)

- **RingAssist:** Launched new Meta ad campaigns
- **Darwin Research:** Finished build

### Alice (Design)

- **RingAssist:** Redesigned onboarding flow
```

**todo.md:**
```markdown
## 2026-03-27

### Greg (Development, Marketing)

- [ ] RingAssist: Start email outbound setup
- [ ] Darwin Research: Continue email campaign
```

The app pulls before recording and before pushing to minimize conflicts.

## Building from source

Requires Xcode 15+ and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open DailyStandup.xcodeproj
```

Or build from the command line:

```bash
xcrun swiftc -o build/DailyStandup.app/Contents/MacOS/DailyStandup \
  -sdk $(xcrun --show-sdk-path -sdk macosx) \
  -target arm64-apple-macos14.0 \
  -framework SwiftUI -framework AVFoundation \
  -framework UserNotifications -framework ServiceManagement \
  -framework AppKit -framework CoreAudio \
  DailyStandup/*.swift
```
