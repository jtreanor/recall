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

- [x] Resize `OverlayPanel` to full screen width, fixed height (~180pt)
- [x] Position: bottom of the main screen, y = 0 (above Dock)
- [x] Rounded top corners only (12pt radius via `CALayer.maskedCorners`)
- [x] Background: `NSVisualEffectView` with `.hudWindow` material (system-matched blur)
- [x] Window level: `.floating` (sits above normal windows, below menu bar)
- [x] Remove old centered-panel sizing logic

**Acceptance criteria:** Panel opens at screen bottom, full width, correct height, blurred background, rounded top corners only.

---

### Milestone 2.3 — Slide Animation

**Goal:** Overlay slides up from below the screen edge; slides down to dismiss.

- [x] On open: panel starts at `y = -panelHeight`, animates to `y = 0` with a spring (stiffness ~280, damping ~0.82, ~280ms)
- [x] On dismiss: reverse — slide to `y = -panelHeight`, then `orderOut`
- [x] Use `NSAnimationContext` or `SwiftUI withAnimation` driving an `NSPanel.setFrame` call
- [x] Escape and hotkey-toggle both trigger the slide-out dismiss path (not instant `orderOut`)

**Acceptance criteria:** Overlay smoothly slides up; dismisses smoothly down. No flash or jump at start/end of animation.

---

### Milestone 2.4 — Horizontal Card Layout

**Goal:** Replace vertical list with a horizontal row of item cards, matching Paste-style layout.

- [x] Replace `LazyVStack` + `ScrollView(.vertical)` with `ScrollView(.horizontal)` + `LazyHStack`
- [x] Card size: 120×140pt (text items); 120×140pt (image items, thumbnail fills top ~80pt)
- [x] Card anatomy (text): small source-app icon (top-left, 16pt), content preview (2–3 lines, truncated), relative timestamp (bottom, caption style)
- [x] Card anatomy (image): thumbnail fills top portion; source-app icon + timestamp at bottom
- [x] Selected card: subtle scale(1.05) + elevated shadow; non-selected: normal
- [x] Update keyboard navigation: arrow-left / arrow-right move selection; Enter pastes

**Acceptance criteria:** Items render as horizontal cards. Arrow keys navigate left/right. Selected card is visually distinct.

**Manual testing note (2026-04-23):** Tested after 2.4 landed. Paste-back was broken — the M2.3 slide animation (220ms) meant ⌘V fired while the panel was still on screen. Fixed by calling `activate()` before the animation starts and posting ⌘V at 180ms (after the animation, now 150ms). Both text and image paste confirmed working in TextEdit and Terminal.

---

### Milestone 2.5 — Source App Capture and Display

**Goal:** Record which app was frontmost at copy time; show its icon on each card.

- [x] In `ClipboardMonitor`: capture `NSWorkspace.shared.frontmostApplication` at the moment of clipboard change detection; record `bundleIdentifier` and `localizedName`
- [x] Add `source_bundle_id TEXT` column to the `items` SQLite table (migration: `ALTER TABLE items ADD COLUMN source_bundle_id TEXT`)
- [x] `HistoryStore.insert` persists the bundle ID
- [x] In `ClipboardItemRow`: resolve `NSWorkspace.shared.icon(forFile:)` or `NSWorkspace.shared.icon(forApp:)` from bundle ID; display as 16pt icon
- [x] Fallback: generic document icon if bundle ID is nil or app not found

**Acceptance criteria:** Cards show the icon of the app that copied the item. Existing items (no bundle ID) show fallback icon without crashing.

---

### Milestone 2.6 — Empty State and Visual Refinements

**Goal:** App feels considered and complete even before any items exist.

- [x] Empty state view inside the overlay: centered icon + "Nothing copied yet" message
- [x] Refine card typography: primary content in `.body`, timestamp in `.caption2`, muted color
- [x] Subtle card background (`.thinMaterial`) differentiating cards from the panel background (`.hudWindow`)
- [x] Scroll indicator hidden (`.scrollIndicators(.hidden)`) for cleaner look
- [x] Ensure panel height accommodates Dock (uses `screen.visibleFrame.minY` — already handled)

**Acceptance criteria:** Empty state renders correctly. Cards are readable and visually distinct from the panel background.

---

### Milestone 2.7 — App Icon and Menu Bar Icon

**Goal:** Ship with real assets, not placeholders.

- [x] Menu bar icon: template image (monochrome, 18×18pt @2x) — a simple clipboard or stack glyph
- [x] App icon: 1024×1024pt master, exported to all required sizes via `AppIcon.appiconset`
- [x] Menu bar icon uses `NSImage(named:)` with `isTemplate = true` so it adapts to light/dark menu bar

**Acceptance criteria:** Menu bar icon appears correctly in both light and dark menu bars. App icon shows in Finder and Launchpad.

---

### Milestone 2.8 — Settings Panel

**Goal:** Users can customize the hotkey and history size without editing plist files.

- [x] `SettingsWindowController`: plain `NSPanel` (not sheet), opens from menu bar "Settings…" item
- [x] Hotkey recorder: click-to-record field that captures the next key combination; persisted in `UserDefaults`
- [x] History limit segmented control: 50 / 200 / 500; persisted in `UserDefaults`; `HistoryStore` reads this on prune
- [x] "Clear All History" button with confirmation alert
- [x] `HotkeyManager` re-registers hotkey when setting changes

**Acceptance criteria:** Hotkey can be changed without relaunch. History limit preference is respected on next prune. Clear history removes all items from both SQLite and the image directory.

---

### Milestone 2.9 — Graceful Accessibility Permission Handling

**Goal:** App remains useful even if Accessibility permission is denied.

- [x] On Enter with permission denied: write item to clipboard, dismiss overlay, show a brief heads-up (`.bezel`-style toast or `NSUserNotification`) — "Copied — paste manually with ⌘V"
- [x] Menu bar: show "⚠ Accessibility required" item when permission is missing; clicking opens System Settings to the Accessibility pane
- [x] Do not spam permission prompts; check once at launch and once when the user triggers paste

**Acceptance criteria:** With Accessibility denied, Enter still copies the item and shows a toast. Menu bar warns the user with a clear action.

---

### Milestone 2.10 — UI Polish (card layout, timestamps, image clipping)

**Goal:** Fix visual and functional rough edges surfaced during daily use.

- [x] **Timestamp fix:** `createdAt` was stored as microseconds but converted back as seconds (dates far in future → always "just now"). Fix: divide stored `Int64` by 1,000,000 when constructing `Date` in `row(from:)`, `insertText`, and `insertImage`
- [x] **Image overflow:** Images with `.fill` escaped card borders. Fix: add `.clipShape(RoundedRectangle(cornerRadius: 10))` to the card's outer `.frame` so all content is masked to the card shape
- [x] **Card size:** Increase card dimensions from 120×140 to 150×150 to reduce cramping
- [x] **Remove scale on selection:** Drop `.scaleEffect(1.05)` — the highlight border is sufficient visual feedback
- [x] **Reduce top gap:** Change `.padding(.vertical, 14)` to `.padding(.bottom, 12).padding(.top, 6)` and shrink panel height from 180 to 172 to eliminate the unused gap at the top of the tray

**Acceptance criteria:** Timestamps show correct relative age (e.g. "13m ago", "2h ago"). Images are fully contained within their card. Cards feel spacious. Selected card shows only the accent border highlight, no size change. The tray has minimal dead space above the cards.

---

### Milestone 2.11 — Notarization and Distribution

**Goal:** App can be downloaded and run by anyone without Gatekeeper warnings.

- [x] Confirm Hardened Runtime entitlements are correct (empty entitlements — no exceptions needed; see `docs/distribution.md`)
- [x] `codesign --deep --strict` passes cleanly (ad-hoc signed; `get-task-allow` debug entitlement stripped by `scripts/distribute.sh`)
- [ ] `xcrun notarytool submit` succeeds and stapling completes — **deferred**: requires paid Apple Developer Program ($99/yr). Script supports it via `--notarize` flag; see `docs/distribution.md`.
- [x] Create a `.dmg` with the app for direct distribution (`build/dist/Recall-0.1.0.dmg` via `scripts/distribute.sh`)
- [x] Document the notarization steps in `docs/distribution.md`

**Acceptance criteria:** Users can install from the `.dmg` by right-clicking → Open on first launch. Full notarization ready to activate once a Developer ID cert is available.

---

### Phase 2 complete when:
- Overlay is a bottom-anchored, slide-up horizontal card tray
- Source app icons appear on all new items
- App and menu bar icons are real assets
- Settings panel covers hotkey + history limit + clear
- Graceful fallback when Accessibility is denied
- UI polish: correct timestamps, image clipping, comfortable card sizing
- App is notarized and distributable

---

## Phase 3 — Pre-Release Quality and Features

**Goal:** Fix reliability issues, ship the last few high-value features, and iterate the UI collaboratively before going public.

---

### Milestone 3.1 — Test Isolation Fix

**Branch:** `feature/test-isolation`

**Problem:** Tests currently share the production SQLite database and read live `UserDefaults` (e.g. history limit). Changing the history limit in Settings to 200 causes tests written against 500 to fail, and running the test suite leaves "unit-test" entries visible in the live app.

- [ ] Audit every test that touches `HistoryStore` or `ClipboardMonitor` — identify all places the production DB path or `UserDefaults` is used
- [ ] Refactor `HistoryStore` to accept an injectable database path (default: production path; tests pass a temp directory path)
- [ ] Inject a fresh `UserDefaults` suite (not `.standard`) into tests that touch settings-dependent logic
- [ ] Ensure every test cleans up its temp database on teardown
- [ ] Confirm: suite passes with production history limit set to 200; no test-originated items appear in the live app after running tests

---

### Milestone 3.2 — System-Level Fixes (App Icon + Open at Login)

**Branch:** `feature/system-fixes`

**Goal:** Two small system-level issues fixed in one session.

**App icon missing in System Settings (Accessibility list):**
The app shows a generic grid icon instead of the Recall icon in Privacy & Security → Accessibility. This is typically caused by a missing or incorrectly named icon in `AppIcon.appiconset`, a missing `CFBundleIconName` in `Info.plist`, or the icon not being included in the built app bundle.

- [ ] Inspect the built `.app` bundle (`Contents/Resources/`) to confirm whether `AppIcon.icns` is present
- [ ] Verify `CFBundleIconName` is set correctly in `Info.plist` (should be `AppIcon`)
- [ ] Confirm `AppIcon.appiconset` contains at least a 512×512 and 1024×1024 representation (the sizes macOS pulls for system UI)
- [ ] Rebuild and confirm the correct icon appears in the Accessibility list

**Open at Login:**

- [ ] Add an "Open at Login" toggle to the Settings panel (below the existing controls)
- [ ] Implement using `SMAppService.mainApp` (macOS 13+ API) — `register()` on enable, `unregister()` on disable
- [ ] Persist the user's choice in `UserDefaults`; reflect the current `SMAppService` status on Settings open
- [ ] Handle edge case where the service is already registered from a previous install

**Notes:** `SMAppService` is the modern replacement for `SMLoginItemSetEnabled` / Launch Agents. No entitlement change required for a non-sandboxed app.

**Acceptance criteria:** Recall icon appears correctly in the Accessibility list. Toggling "Open at Login" on → app launches on next login. Toggling off → it does not.

---

### Milestone 3.3 — UI Iteration: Selection State

**Branch:** `feature/ui-selection-state`

**Session protocol (collaborative):** Claude implements and presents three distinct selection treatments as swappable variants, user compares them live, and picks one.

- [ ] Implement three variants: (1) current — border only; (2) subtle zoom — `scaleEffect(1.05)` with spring + border; (3) elevated glow — stronger shadow + lighter card background, no scale
- [ ] Build and present each for live comparison; adopt the chosen variant
- [ ] Remove the rejected variants; no dead code remains

---

### Milestone 3.4 — UI Iteration: Panel Layout

**Branch:** `feature/ui-panel-layout`

**Session protocol (collaborative):** User provides reference screenshots at session start; Claude proposes 2–3 concrete layout variants with specific measurements; user picks one; Claude implements.

- [ ] User shares reference screenshots of similar apps (e.g. Paste, Clipboard Manager)
- [ ] Claude proposes 2–3 variants covering: panel height, card size, top gap, internal padding, card spacing
- [ ] Implement the agreed variant; no unexplained magic numbers

---

### Milestone 3.5 — Click to Paste

**Branch:** `feature/click-to-paste`

**Goal:** Clicking a card pastes it, matching pointer-interaction expectations.

- [ ] Add `.onTapGesture` to `ClipboardItemRow` that sets selection briefly then pastes (same action as Enter)
- [ ] Confirm `NSPanel` focus handling is correct so `⌘V` posts successfully after a mouse click
- [ ] Existing keyboard flow unaffected

**Acceptance criteria:** Single click on any card pastes it and dismisses the panel, identically to pressing Enter.

---

### Milestone 3.6 — Basic Text Search

**Branch:** `feature/text-search`

**Goal:** User can type in the overlay to filter clipboard history by content. No OCR, no image filtering.

- [ ] Add a search field to the panel (position decided during implementation based on layout fit)
- [ ] Filter client-side: case-insensitive substring match on `content`; image items hidden during active query
- [ ] Overlay opens with search field focused; Escape clears query; second Escape dismisses
- [ ] Arrow keys navigate among filtered results; search clears on dismiss

**Acceptance criteria:** Typing filters cards in real time. Images hidden during search. Escape clears before dismissing. Keyboard navigation works on filtered results.

---

### Phase 3 complete when:
- [ ] Tests are isolated from production state and pass regardless of user settings
- [ ] Open at Login setting works and persists
- [ ] Selection state, panel layout, and click-to-paste are polished and user-confirmed
- [ ] Basic text search works for text items

---

## Phase 4 — Open Source and Distribution

_Pursue when the app is stable enough to share publicly._

- [ ] **Repo history review** — before making the repo public, review git history for references to third-party apps (e.g. Paste), internal notes, or anything unsuitable for a public audience; decide whether to scrub (via `git filter-repo`) or leave it and document the decision
- [ ] **CI: test check on PRs** — add a GitHub Actions workflow (`.github/workflows/test.yml`) that runs `xcodebuild test` on every PR; required status check before merge
- [ ] **Open source the repo** — make `jtreanor/recall` public on GitHub; add `LICENSE` (MIT) and a proper `README.md` with screenshots, install instructions, and feature overview
- [ ] **Automated binary releases** — GitHub Actions workflow triggered on version tags: builds a universal Release binary, runs `scripts/distribute.sh`, uploads `Recall-{version}.dmg` as a GitHub Release asset
- [ ] **Homebrew tap** — create `jtreanor/homebrew-recall`; write a cask (`recall.rb`) that points at the GitHub Release DMG and uses a `postflight` block to remove the quarantine xattr so users get zero Gatekeeper friction: `brew install --cask jtreanor/recall/recall`
- [ ] **Notarization** (optional upgrade) — if Apple Developer Program membership ($99/yr) becomes worthwhile, wire up `scripts/distribute.sh --notarize` in CI and drop the `postflight` quarantine removal from the cask

---

## Phase 5 — Extended (If Needed)

_Only pursue if daily use reveals a genuine gap._

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

**Phase:** Phase 3 — Pre-Release Quality and Features  
**Milestone:** Starting 3.1 (test isolation fix).  
**Next task:** M3.1 — fix test isolation so tests don't share the production DB or UserDefaults.

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
