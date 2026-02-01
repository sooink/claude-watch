<div align="center">

# Claude Watch

**Monitor Claude Code parallel subagents and tasks in real-time**

[![platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue?style=flat-square)](https://github.com/sooink/claude-watch)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

</div>

---

## The Problem

When using Claude Code's **Task tool** for parallel work, multiple subagents run simultaneously—each with its own context window, working on different parts of your codebase.

But there's no easy way to see what's happening:

- How many subagents are running?
- What is each one doing?
- Which tasks are completed?
- Is anything stuck or waiting?

You're left checking the terminal or scrolling through logs to understand the current state.

**Claude Watch provides a real-time dashboard** in your menu bar, showing all active projects, subagents, and tasks at a glance.

## Building

```bash
# First-time Xcode setup (if needed)
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept

# Clone and build
git clone https://github.com/sooink/claude-watch.git
cd claude-watch
xcodebuild -scheme ClaudeWatch -configuration Release CONFIGURATION_BUILD_DIR=build build

# Run
open build/ClaudeWatch.app
```

### First Launch (macOS Sequoia+)

The app is unsigned. On first launch:

1. Open `ClaudeWatch.app`
2. macOS will block it
3. Go to **System Settings → Privacy & Security**
4. Click **Open Anyway**
5. Enter your password

Or run in Terminal:
```bash
xattr -cr build/ClaudeWatch.app
```

## Features

| Feature | Description |
|---------|-------------|
| **Menu Bar Integration** | Always accessible from the menu bar |
| **Auto-Detection** | Automatically detects Claude Code sessions |
| **Subagent Tracking** | See all parallel subagents and their status |
| **Task Progress** | View task checklist with completion status |
| **Multi-Project** | Monitor multiple projects simultaneously |
| **Zero Configuration** | Just launch and it works |

<div align="center">

![Claude Watch Demo](https://github.com/sooink/claude-watch/raw/main/assets/demo.gif)

</div>

## How It Works

Claude Watch monitors `~/.claude/projects/` for session files:

```
~/.claude/projects/
└── {project-hash}/
    ├── {sessionId}.jsonl              # Main session log
    └── {sessionId}/
        └── subagents/
            └── agent-{agentId}.jsonl  # Subagent logs
```

When Claude Code runs, it writes activity logs that Claude Watch parses in real-time to show:

- **Projects** — Grouped by working directory
- **Subagents** — Created via Task tool, with running/completed status
- **Tasks** — Created via TaskCreate, with pending/in_progress/completed status

## Status Indicators

### Menu Bar

| Icon | Status | Description |
|------|--------|-------------|
| ○ | Stopped | Claude Code not detected |
| ● (gray) | Watching | Claude Code detected, waiting for activity |
| ● (blue) | Active | Active session with projects |
| ●3 | Active | Number indicates running subagents |

- **Left-click** — Toggle main window
- **Right-click** — Show menu (About, Quit)

### Window

- **Titlebar** — Current watch state with pulse animation when watching
- **Project cards** — Click to expand/collapse details
- **Right-click menu** — Open in Terminal, Copy Path

## Requirements

- macOS 15.0 Sequoia or later
- Xcode 16.0 or later
