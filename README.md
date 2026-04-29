# Recall

A keyboard-first clipboard history manager for macOS.

Press **⌘⇧V** from any app to summon a floating tray of your recent clipboard items. Arrow to the one you want, hit Enter, and it pastes directly into whatever you were working in.

## Features

- **Instant access** — global hotkey (`⌘⇧V`) works from any app
- **Text and images** — captures plain text and raster images
- **Source app icons** — see where each item was copied from
- **Keyboard navigation** — arrow keys to move, Enter to paste, Escape to dismiss, Backspace to delete
- **Click to paste** — single click pastes and dismisses
- **Text search** — type to filter; Backspace clears search before deleting items
- **Sensitive item detection** — copies from password managers are masked and auto-expire after 15 minutes
- **Configurable history** — adjust the limit (default 200), clear all, toggle password storage
- **Open at Login** — optional via Settings
- **Lightweight** — menu bar only, no dock icon, <30 MB at idle

## Requirements

- macOS 13 Ventura or later
- **Accessibility permission** — required for paste-back (`CGEvent` keystroke injection); Recall will prompt on first launch

## Install

### Homebrew (recommended)

```sh
brew install --cask jtreanor/recall/recall
```

The cask automatically removes the macOS quarantine attribute, so the app opens on first launch without any Gatekeeper prompt.

### Manual

Download the latest `Recall.dmg` from the [Releases](../../releases) page, open it, and drag Recall to Applications.

> **Gatekeeper note:** Because the app is ad-hoc signed (no Apple Developer Program), macOS may block the first launch. Right-click → Open to bypass, or run:
> ```sh
> xattr -d com.apple.quarantine /Applications/Recall.app
> ```

## Build from source

```bash
# Prerequisites: Xcode 15+, xcodegen
brew install xcodegen

git clone https://github.com/jtreanor/recall.git
cd recall
xcodegen generate
open Recall.xcodeproj
```

Run tests:

```bash
xcodebuild test \
  -project Recall.xcodeproj \
  -scheme Recall \
  -destination 'platform=macOS'
```

Build a distributable DMG:

```bash
./scripts/distribute.sh
# Output: build/dist/Recall-0.1.0.dmg
```

## How it works

Recall polls `NSPasteboard.general.changeCount` every 0.75 seconds on a background queue. New items are stored in SQLite under `~/Library/Application Support/Recall/`. The overlay is an `NSPanel` at floating window level; paste-back writes to the pasteboard then posts a synthetic `⌘V` `CGEvent` after re-activating the previously frontmost app.

## Settings

Open Settings from the menu bar icon (⚙) or press **⌘,** while the overlay is visible.

| Setting | Default |
|---|---|
| History limit | 200 items |
| Store passwords | On |
| Open at Login | Off |
| Hotkey | ⌘⇧V |

## License

MIT — see [LICENSE](LICENSE).
