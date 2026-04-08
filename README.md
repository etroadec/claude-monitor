# Claude Monitor

A lightweight macOS menu bar app to monitor your Claude usage limits in real-time.

![Screenshot](https://img.shields.io/badge/macOS-13%2B-blue) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Session usage** — see your current 5-hour usage percentage and time until reset
- **Weekly usage** — track your 7-day usage with per-model breakdown (Sonnet, Opus)
- **Extra credits** — monitor your monthly extra credit consumption
- **Status notifications** — get notified of Claude outages and incidents from status.claude.com
- **Badge indicator** — orange dot appears when there's an active incident
- **OAuth login** — connect your Claude account in one click, no API key needed
- **Auto-refresh** — usage updates every 30 seconds, status feed every 5 minutes

## Installation

### Download

Download the latest `.zip` from the [Releases](../../releases) page, extract, and drag `ClaudeMonitor.app` to your Applications folder.

### Build from source

```bash
git clone https://github.com/etroadec/claude-monitor.git
cd claude-monitor
./build.sh
open build/ClaudeMonitor.app
```

Requires Xcode Command Line Tools (`xcode-select --install`).

## Usage

1. Click the **CL** indicator in your menu bar
2. Click **Connecter mon compte Claude**
3. Log in with your Claude account in the browser
4. Done — your usage appears in the menu bar

The app shows two tabs:
- **Utilisation** — session/weekly usage, extra credits, last update time
- **Notifications** — recent incidents from the Claude status page

## How it works

- Authenticates via OAuth with your Claude account (same flow as Claude Code)
- Polls `api.anthropic.com/api/oauth/usage` for usage data
- Polls `status.claude.com/history.atom` for incident notifications
- Tokens are stored locally in `~/Library/Application Support/ClaudeMonitor/`
- Tokens auto-refresh when expired

## Requirements

- macOS 13.0+
- Apple Silicon (arm64)

## License

MIT
