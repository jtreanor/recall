# Recall — Implementation Plan

_Living document. Update when implementation diverges from plan._

---

## MVP Definition

The MVP is a working, daily-usable clipboard manager. It must:

- Run as a menu bar app (`.accessory` activation policy)
- Monitor clipboard continuously (text and images)
- Open a polished floating overlay on a global shortcut (`⌘⇧V`)
- Show recent clipboard history as a scrollable list: text previews + image thumbnails
- Navigate with arrow keys; dismiss with Escape
- Paste selected item into the previously focused app with Enter
- Persist history locally across relaunches
- Deduplicate entries; cap history at 500 items
- Request Accessibility permission on first launch with clear explanation
- Be notarized and directly distributable (no App Store)

---

## Phase 1 — Foundation (MVP)

**Goal:** Working daily-use app. No polish, but the core loop functions reliably.

### Milestone 1.1 — Project scaffold
- [x] Xcode project: macOS app target, minimum deployment macOS 13
- [x] `NSApplicationDelegate`, `.accessory` activation policy (menu bar icon only)
- [x] Basic menu bar `NSStatusItem` with "Quit" item
- [x] Hardened runtime, no sandbox, provisioning profile for notarization
- [x] `CLAUDE.md` and `docs/` committed to `master`; all feature work on branches

**Acceptance criteria:** App launches, appears in menu bar, can be quit.

### Milestone 1.2 — Clipboard monitor
- [x] `ClipboardMonitor` class: `DispatchSourceTimer` at 0.75s interval
- [x] Detects `changeCount` change on `NSPasteboard.general`
- [x] Reads plain text items
- [x] Reads image items (TIFF/PNG), converts to PNG, generates 200×150 thumbnail
- [x] Emits items via `Combine` publisher or delegate callback

**Acceptance criteria:** Copy text → item appears in in-memory array. Copy image → thumbnail generated.

### Milestone 1.3 — Local persistence
- [ ] SQLite3 wrapper (`Database.swift`) using `libsqlite3` (no SPM dependency)
- [ ] Schema: `items` table per research doc
- [ ] `HistoryStore` CRUD: insert, fetchAll (newest first), delete, prune to 500
- [ ] Image files written to `~/Library/Application Support/Recall/images/`
- [ ] Deduplication on `content_hash`

**Acceptance criteria:** Items survive app relaunch. Duplicates collapse to most recent.

### Milestone 1.4 — Overlay panel
- [ ] `OverlayPanel: NSPanel` subclass: `.floating` level, vibrancy, rounded corners
- [ ] `NSHostingView<OverlayView>` as content view
- [ ] `OverlayView` (SwiftUI): `List` or `ScrollView + LazyVStack` of `ClipboardItemRow`
- [ ] `ClipboardItemRow`: text preview (truncated) or image thumbnail; selection highlight
- [ ] Shows centered on main screen
- [ ] Dismisses on Escape, click-outside, or after paste

**Acceptance criteria:** Panel opens, shows history items, looks clean.

### Milestone 1.5 — Global hotkey
- [ ] `HotkeyManager` using Carbon `RegisterEventHotKey`
- [ ] Default: `⌘⇧V`
- [ ] Toggles overlay open/closed

**Acceptance criteria:** `⌘⇧V` from any app opens/closes the overlay.

### Milestone 1.6 — Keyboard navigation + paste-back
- [ ] Arrow up/down moves selection; view auto-scrolls to keep selection visible
- [ ] Enter: write item to `NSPasteboard.general`, dismiss panel, re-activate previous app, post synthetic `⌘V` via `CGEvent` after 50ms delay
- [ ] `AccessibilityManager`: checks `AXIsProcessTrusted`, prompts on first launch

**Acceptance criteria:** Full loop works — open overlay, arrow to item, press Enter, item is pasted into previous app.

### Phase 1 complete when:
- Daily-use loop works reliably in 10 manual test sessions
- No crashes on text and image clipboard items
- Memory RSS < 60MB with overlay open
- All unit tests pass (`xcodebuild test -scheme Recall -destination 'platform=macOS'`)

---

## Phase 2 — Polish

**Goal:** Feels genuinely good to use. Ready to share.

- [ ] Animation: overlay fades in/out (100ms, spring easing)
- [ ] Source-app icon in item row (optional, small)
- [ ] Configurable hotkey (stored in `UserDefaults`, UI in a minimal settings panel)
- [ ] History limit preference (50 / 200 / 500)
- [ ] Clear history action in menu bar
- [ ] Better empty state in overlay
- [ ] Keyboard shortcut: `⌘K` to clear filter (if search added)
- [ ] App icon, menu bar icon (template image)
- [ ] Notarization and direct download distribution
- [ ] Scroll momentum and overscan feel polished in list
- [ ] Graceful degradation when Accessibility permission denied (copy to clipboard, show toast "Copied — paste manually")

---

## Phase 3 — Extended (If Needed)

_Only pursue if daily use reveals a genuine gap._

- [ ] Search / filter bar (type to filter history)
- [ ] Quick-select: `⌘1`–`⌘9` for top 9 items
- [ ] Per-app history source filtering
- [ ] Pinned items (favorites that persist beyond history cap)
- [ ] Image preview on hover/selection (full-size in popover)
- [ ] File path items (copy file → show filename + icon)
- [ ] URL detection (show domain as label)

---

## Implementation Notes

- Keep `NSPanel` subclass minimal; prefer SwiftUI for all rendered content
- Image processing (PNG encode, thumbnail) must never happen on main thread
- Test paste-back with: Xcode, Safari, Terminal, VS Code, Notes — all behave differently
- Do not add SPM dependencies without a concrete blocking reason

---

## Current Status

**Phase:** Phase 1 — Foundation  
**Milestone:** 1.2 complete; next is 1.3 (Local persistence)

---

## First Coding Task

**Branch:** `feature/project-scaffold`

Create the Xcode project:
1. New macOS App target named `Recall`, bundle ID `com.recall.app`, minimum deployment macOS 13, Swift + SwiftUI
2. Set `NSApplicationDelegate` with `.accessory` activation policy (app hides from Dock)
3. Add `NSStatusItem` to menu bar with a placeholder template icon and a single "Quit Recall" menu item
4. Enable Hardened Runtime in signing settings; disable sandbox
5. Delete the default `ContentView.swift` and Window scene from the SwiftUI App struct — this is a menu bar / overlay app, not a window-based app
6. Add `CLAUDE.md` and `docs/` to the repo; commit on `feature/project-scaffold`; open a PR

Acceptance: App builds and runs. Menu bar icon appears. No Dock icon. App quits from menu bar item.
