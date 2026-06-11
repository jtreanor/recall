# Recall — Implementation Plan

_Living document. Update when implementation diverges from plan. Granular detail on completed work lives in git history and merged PRs._

---

## Completed

**Phase 1 (Foundation):** Menu bar app, clipboard monitor (text + images), SQLite persistence, floating overlay panel, global hotkey (`⌘⇧V`), keyboard navigation, paste-back via `CGEvent`.

**Phase 2 (Polish):** Bottom-anchored slide-up tray; horizontal card layout; source-app icons; empty state; settings panel (hotkey, history limit, clear all); graceful Accessibility fallback; app/menu bar icons; `.dmg` distribution script.

**Phase 3 (Pre-Release Quality):** Test isolation; Open at Login; sensitive-item detection with 15-min auto-expiry and masked cards; click-to-paste and Backspace-to-delete; text search (animated pill, auto-engage, scoped Backspace); UI polish (selection border, card sizing, tinted backgrounds, code-item dark treatment).

**Phase 4 (Distribution):** Repo made public (MIT); README with screenshots and install instructions; CI test check on PRs; automated binary releases via GitHub Actions on version tags; Homebrew tap (`jtreanor/homebrew-recall`) with auto-update on release.

**Phase 5 (Rich Text Paste, #37):** RTF captured alongside plain text, stored in `rtf_data` BLOB; paste-back prefers RTF with plain-text fallback; "Plain Text Only" settings toggle; "Rich Text" card label; round-trip tests (`RichTextTests.swift`).

**Phase 6 (URL Detection, #38):** Lightweight URL detector on capture and DB load; `url` item type; domain label + URL badge on cards; detection-accuracy tests. _Deferred: favicon fetch/cache._

**Phase 7 (File Handling, #39):** `public.file-url` detection (checked before text); paths stored as JSON in `file_paths`, multi-file as one item with order-insensitive hash dedup; type-aware SF Symbol icon + `+N` badge; paste-back writes `NSURL` objects with path-string fallback; DB migration for `'file'` type; full test suite (`FileHandlingTests.swift`). Paste-back research in `docs/research.md`.

**Overlay open/close compositing bug (resolved 2026-06-11, #40/#41/#43):** A month-long "animation drift" report turned out to be two artifacts, neither an animation bug:

1. _First-composite settle:_ the whole panel composited ~20–28px right of the screen edge for ~6 frames after every open — Window Server settling a freshly composited window, present with no animation at all. **Fixed by approach M (#41):** never order the panel out; `warmUp()` parks it at the resting frame at `alphaValue = 0` + `ignoresMouseEvents = true`, `show()` flips alpha and runs the original animator slide. Measured edge-0 from the first motion frame, and a smoother open than baseline. Follow-up: dismiss overlay on space switch (#43).
2. _Dramatic ~100px blur-vs-content detachment on close (the original May complaint):_ no longer reproduces as of 2026-06-11 (same-day unfixed-baseline controls clean; likely fixed by a macOS update). **Reopen only if seen again, and immediately capture a same-day unfixed-baseline control.** Standing fallback if it returns: approach B (mask reveal in a stationary window) is structurally immune to motion drift.

Failed approaches (A, C–L), forensic timeline, and the reusable capture harness — Darwin-notification toggle, 60fps `screencapture -v` workflow, quantitative left-edge detector, per-frame MAE motion profiling, baseline-control protocol — are preserved in this file's git history (PR #40, commit `1cb8c74`).

> **Notarization** (optional upgrade): if Apple Developer Program membership is obtained, wire up `scripts/distribute.sh --notarize` in CI and drop the `postflight` quarantine removal from the cask.

---

## Version 1.1.0

### Phase 8 — README Refresh

_Make the README compelling and useful for people discovering the app for the first time._

- [ ] Rewrite the opening hook: lead with the core value proposition (summon → glance → paste) rather than a feature list
- [ ] Add a short animated GIF or screen recording showing the overlay in action
- [ ] Add a "Why Recall?" section: contrast with system clipboard and other clipboard managers; call out keyboard-first, privacy (no cloud), open source
- [ ] Improve install section: clearer Homebrew one-liner, note the Accessibility permission prompt and why it's needed
- [ ] Add a Usage section: hotkey, search, keyboard controls — enough for a new user to feel productive immediately
- [ ] Review and tighten all existing sections for clarity and brevity

---

## Implementation Notes

- Keep `NSPanel` subclass minimal; prefer SwiftUI for all rendered content
- Image processing (PNG encode, thumbnail) must never happen on main thread
- Test paste-back with: Xcode, Safari, Terminal, VS Code, Notes — all behave differently
- Do not add SPM dependencies without a concrete blocking reason

---

## Current Status

**Version:** 1.1.0-dev (Phase 7 complete; overlay compositing bug fixed)  
**Next:** Phase 8 — README Refresh
