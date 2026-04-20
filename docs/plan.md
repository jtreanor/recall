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

**Goal:** Feels genuinely good to use — a Paste-style horizontal card tray that slides up from the bottom of the screen. Ready to share.

**Reference UI:** Full-width overlay anchored to the bottom of the screen. Items are horizontal cards in a single scrollable row. Vibrancy/blur background, rounded top corners. Slides up on open, slides down on dismiss.

---

### Milestone 2.1 — Clipboard Monitor Efficiency

**Goal:** Eliminate unnecessary CPU wake-ups; pause polling when the machine is asleep or the screen is locked.

- [x] Bump polling interval from 0.75s to 1.0s (negligible UX impact; saves ~25% timer wakes)
- [x] Add `leeway` to `DispatchSourceTimer` (e.g. 200ms) so the OS can coalesce wakes
- [x] Observe `NSWorkspace.screensDidSleepNotification` → suspend timer
- [x] Observe `NSWorkspace.screensDidWakeNotification` → resume timer
- [x] Observe `NSWorkspace.willSleepNotification` / `didWakeNotification` for system sleep/wake

**Notes:** Polling `changeCount` is the only viable approach on macOS — no push API exists. These changes make it power-friendly without sacrificing responsiveness.

**Acceptance criteria:** App polls 1/s while screen is on; timer is fully suspended while screen is off. Unit test: monitor suspends/resumes correctly on sleep/wake notifications.

---

### Milestone 2.2 — Bottom-Anchored Overlay Panel

**Goal:** Replace the centered floating panel with a full-width tray anchored to the bottom of the screen.

- [ ] Resize `OverlayPanel` to full screen width, fixed height (~180pt)
- [ ] Position: bottom of the main screen, y = 0 (above Dock)
- [ ] Rounded top corners only (12pt radius via `NSBezierPath` mask or SwiftUI `UnevenRoundedRectangle`)
- [ ] Background: `NSVisualEffectView` with `.hudWindow` or `.popover` material (system-matched blur)
- [ ] Window level: `.floating` (sits above normal windows, below menu bar)
- [ ] Remove old centered-panel sizing logic

**Acceptance criteria:** Panel opens at screen bottom, full width, correct height, blurred background, rounded top corners only.

---

### Milestone 2.3 — Slide Animation

**Goal:** Overlay slides up from below the screen edge; slides down to dismiss.

- [ ] On open: panel starts at `y = -panelHeight`, animates to `y = 0` with a spring (stiffness ~280, damping ~0.82, ~280ms)
- [ ] On dismiss: reverse — slide to `y = -panelHeight`, then `orderOut`
- [ ] Use `NSAnimationContext` or `SwiftUI withAnimation` driving an `NSPanel.setFrame` call
- [ ] Escape and hotkey-toggle both trigger the slide-out dismiss path (not instant `orderOut`)

**Acceptance criteria:** Overlay smoothly slides up; dismisses smoothly down. No flash or jump at start/end of animation.

---

### Milestone 2.4 — Horizontal Card Layout

**Goal:** Replace vertical list with a horizontal row of item cards, matching Paste-style layout.

- [ ] Replace `LazyVStack` + `ScrollView(.vertical)` with `ScrollView(.horizontal)` + `LazyHStack`
- [ ] Card size: 120×140pt (text items); 120×140pt (image items, thumbnail fills top ~80pt)
- [ ] Card anatomy (text): small source-app icon (top-left, 16pt), content preview (2–3 lines, truncated), relative timestamp (bottom, caption style)
- [ ] Card anatomy (image): thumbnail fills top portion; source-app icon + timestamp at bottom
- [ ] Selected card: subtle scale(1.05) + elevated shadow; non-selected: normal
- [ ] Update keyboard navigation: arrow-left / arrow-right move selection; Enter pastes

**Acceptance criteria:** Items render as horizontal cards. Arrow keys navigate left/right. Selected card is visually distinct.

---

### Milestone 2.5 — Source App Capture and Display

**Goal:** Record which app was frontmost at copy time; show its icon on each card.

- [ ] In `ClipboardMonitor`: capture `NSWorkspace.shared.frontmostApplication` at the moment of clipboard change detection; record `bundleIdentifier` and `localizedName`
- [ ] Add `source_bundle_id TEXT` column to the `items` SQLite table (migration: `ALTER TABLE items ADD COLUMN source_bundle_id TEXT`)
- [ ] `HistoryStore.insert` persists the bundle ID
- [ ] In `ClipboardItemRow`: resolve `NSWorkspace.shared.icon(forFile:)` or `NSWorkspace.shared.icon(forApp:)` from bundle ID; display as 16pt icon
- [ ] Fallback: generic document icon if bundle ID is nil or app not found

**Acceptance criteria:** Cards show the icon of the app that copied the item. Existing items (no bundle ID) show fallback icon without crashing.

---

### Milestone 2.6 — Empty State and Visual Refinements

**Goal:** App feels considered and complete even before any items exist.

- [ ] Empty state view inside the overlay: centered icon + "Nothing copied yet" message
- [ ] Refine card typography: primary content in `.body`, timestamp in `.caption2`, muted color
- [ ] Subtle card background (e.g. `.thinMaterial` or semi-transparent white/dark) differentiating cards from the panel background
- [ ] Scroll indicator hidden (`.scrollIndicators(.hidden)`) for cleaner look
- [ ] Ensure panel height accommodates Dock (detect Dock edge and adjust `y` origin accordingly)

**Acceptance criteria:** Empty state renders correctly. Cards are readable and visually distinct from the panel background.

---

### Milestone 2.7 — App Icon and Menu Bar Icon

**Goal:** Ship with real assets, not placeholders.

- [ ] Menu bar icon: template image (monochrome, 18×18pt @2x) — a simple clipboard or stack glyph
- [ ] App icon: 1024×1024pt master, exported to all required sizes via `AppIcon.appiconset`
- [ ] Menu bar icon uses `NSImage(named:)` with `isTemplate = true` so it adapts to light/dark menu bar

**Acceptance criteria:** Menu bar icon appears correctly in both light and dark menu bars. App icon shows in Finder and Launchpad.

---

### Milestone 2.8 — Settings Panel

**Goal:** Users can customize the hotkey and history size without editing plist files.

- [ ] `SettingsWindowController`: plain `NSPanel` (not sheet), opens from menu bar "Settings…" item
- [ ] Hotkey recorder: click-to-record field that captures the next key combination; persisted in `UserDefaults`
- [ ] History limit segmented control: 50 / 200 / 500; persisted in `UserDefaults`; `HistoryStore` reads this on prune
- [ ] "Clear All History" button with confirmation alert
- [ ] `HotkeyManager` re-registers hotkey when setting changes

**Acceptance criteria:** Hotkey can be changed without relaunch. History limit preference is respected on next prune. Clear history removes all items from both SQLite and the image directory.

---

### Milestone 2.9 — Graceful Accessibility Permission Handling

**Goal:** App remains useful even if Accessibility permission is denied.

- [ ] On Enter with permission denied: write item to clipboard, dismiss overlay, show a brief heads-up (`.bezel`-style toast or `NSUserNotification`) — "Copied — paste manually with ⌘V"
- [ ] Menu bar: show "⚠ Accessibility required" item when permission is missing; clicking opens System Settings to the Accessibility pane
- [ ] Do not spam permission prompts; check once at launch and once when the user triggers paste

**Acceptance criteria:** With Accessibility denied, Enter still copies the item and shows a toast. Menu bar warns the user with a clear action.

---

### Milestone 2.10 — Notarization and Distribution

**Goal:** App can be downloaded and run by anyone without Gatekeeper warnings.

- [ ] Confirm Hardened Runtime entitlements are correct (no `com.apple.security.cs.disable-library-validation` unless needed)
- [ ] `codesign --deep --strict` passes cleanly
- [ ] `xcrun notarytool submit` succeeds and stapling completes
- [ ] Create a `.dmg` with the app for direct distribution
- [ ] Document the notarization steps in `docs/distribution.md`

**Acceptance criteria:** Downloaded `.dmg` opens without Gatekeeper warning on a clean Mac (or Gatekeeper bypass is not required — notarization ticket is stapled).

---

### Phase 2 complete when:
- Overlay is a bottom-anchored, slide-up horizontal card tray
- Source app icons appear on all new items
- App and menu bar icons are real assets
- Settings panel covers hotkey + history limit + clear
- Graceful fallback when Accessibility is denied
- App is notarized and distributable

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

**Phase:** Phase 2 — Polish  
**Milestone:** 2.1 complete (PR #11 open). Validation Phase fully complete (V.1, V.2, V.3 merged).  
**Next task:** Milestone 2.2 — Bottom-Anchored Overlay Panel

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
