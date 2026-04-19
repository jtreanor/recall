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
- [x] SQLite3 wrapper (`Database.swift`) using `libsqlite3` (no SPM dependency)
- [x] Schema: `items` table per research doc
- [x] `HistoryStore` CRUD: insert, fetchAll (newest first), delete, prune to 500
- [x] Image files written to `~/Library/Application Support/Recall/images/`
- [x] Deduplication on `content_hash`

**Acceptance criteria:** Items survive app relaunch. Duplicates collapse to most recent.

### Milestone 1.4 — Overlay panel
- [x] `OverlayPanel: NSPanel` subclass: `.floating` level, vibrancy, rounded corners
- [x] `NSHostingView<OverlayView>` as content view
- [x] `OverlayView` (SwiftUI): `ScrollView + LazyVStack` of `ClipboardItemRow`
- [x] `ClipboardItemRow`: text preview (truncated) or image thumbnail; selection highlight
- [x] Shows centered on main screen
- [x] Dismisses on Escape (via `NSEvent.addLocalMonitorForEvents`)

**Acceptance criteria:** Panel opens, shows history items, looks clean.

### Milestone 1.5 — Global hotkey
- [x] `HotkeyManager` using Carbon `RegisterEventHotKey`
- [x] Default: `⌘⇧V`
- [x] Toggles overlay open/closed

**Acceptance criteria:** `⌘⇧V` from any app opens/closes the overlay.

### Milestone 1.6 — Keyboard navigation + paste-back
- [x] Arrow up/down moves selection; view auto-scrolls to keep selection visible
- [x] Enter: write item to `NSPasteboard.general`, dismiss panel, re-activate previous app, post synthetic `⌘V` via `CGEvent` after 50ms delay
- [x] `AccessibilityManager`: checks `AXIsProcessTrusted`, prompts on first launch

**Acceptance criteria:** Full loop works — open overlay, arrow to item, press Enter, item is pasted into previous app.

### Phase 1 complete when:
- Daily-use loop works reliably in 10 manual test sessions
- No crashes on text and image clipboard items
- Memory RSS < 60MB with overlay open
- All unit tests pass (`xcodebuild test -scheme Recall -destination 'platform=macOS'`)

---

## Validation Phase — Pre-Phase 2 Stability Gate

**Goal:** Confirm Phase 1 is solid before building on it. Each session below is independent, has clear acceptance criteria, and ends with a PR.

---

### Session V.1 — Test Suite Stability

**Branch:** `validation/test-stability`

Run the full unit test suite 3 consecutive times and confirm zero flakiness.

**Steps:**
1. Run `xcodebuild test -project Recall.xcodeproj -scheme Recall -destination 'platform=macOS'` three times in succession.
2. Record pass/fail for each run.
3. If any test fails intermittently, diagnose the root cause (timing dependency, shared state, etc.) and fix it.
4. Re-run the suite 3 times after any fixes to confirm stability.

**Acceptance criteria:**
- All tests pass on all 3 runs with no flakiness.
- No test is skipped or disabled to achieve this.
- PR opened with results noted in description.

---

### Session V.2 — Integration + UI Tests

**Branch:** `validation/integration-tests`

Write tests covering the end-to-end data path and key invariants that unit tests cannot fully verify.

**Integration tests (XCTest):**
- Full cycle: simulate a clipboard change → `ClipboardMonitor` fires → `HistoryStore` receives item → item is fetchable and correct.
- Deduplication: writing the same content twice yields exactly one item with an updated timestamp.
- History cap: inserting 501 items results in exactly 500 items in the store, oldest pruned.

**Persistence test:**
- Write items to a real on-disk SQLite database in a temp directory, close the store, reopen it, and confirm items survive (simulates app restart without actually relaunching).

**Acceptance criteria:**
- All new tests pass on the first run and on 2 subsequent runs (no flakiness).
- Tests use real SQLite on disk (no mocks of the database layer).
- PR opened; test file follows `RecallTests/` convention.

---

### Session V.3 — Interactive Manual Testing

**Branch:** `validation/manual-testing-fixes`

Build the app and walk through a manual checklist interactively. Each step below is confirmed by the user before moving to the next. Any failure is fixed before continuing.

**Checklist (confirmed one at a time):**
1. App launches; menu bar icon appears; no Dock icon.
2. Copy a short text string → open overlay (`⌘⇧V`) → item appears at top of list.
3. Copy a second text string → open overlay → new item is at top; previous item is below.
4. Copy the same text string again → open overlay → no duplicate; existing item moved to top.
5. Arrow down to select the second item; press Enter → item is pasted into a text field in another app (e.g., Notes or TextEdit).
6. Copy an image → open overlay → image thumbnail appears in list.
7. Quit and relaunch the app → open overlay → history is intact.
8. Open overlay; press Escape → overlay dismisses.
9. `⌘⇧V` again → overlay reopens.
10. With overlay open, verify memory RSS < 60 MB (via Activity Monitor or `ps`).

**Session protocol:**
- Present checklist item 1 and wait for user confirmation ("pass" or description of failure).
- On failure: fix the issue, rebuild, and re-present the same step.
- Do not advance to the next step until the current step passes.
- After all 10 steps pass, open a PR summarising fixes made.

**Acceptance criteria:**
- All 10 checklist items pass in a single session without skipping.
- Any bugs found are fixed (not deferred) before the PR is opened.
- PR description lists each fix made, or states "no fixes required."

---

### Validation Phase complete when:
- All three session PRs are merged.
- No open bugs from manual testing.
- Phase 2 work may begin.

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

**Phase:** Validation Phase (between Phase 1 and Phase 2)  
**Milestone:** Session V.2 complete (42/42 tests, 3 consecutive runs, zero flakiness; 4 integration tests added, duplicate reordering bug fixed); PR #9 open  
**Next task:** Session V.3 — Interactive Manual Testing on branch `validation/manual-testing-fixes`

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
