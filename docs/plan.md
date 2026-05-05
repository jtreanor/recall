# Recall — Implementation Plan

_Living document. Update when implementation diverges from plan._

---

## Phases 1–4 — Complete

**Phase 1 (Foundation):** Menu bar app, clipboard monitor (text + images), SQLite persistence, floating overlay panel, global hotkey (`⌘⇧V`), keyboard navigation, paste-back via `CGEvent`.

**Phase 2 (Polish):** Bottom-anchored slide-up tray; horizontal card layout; source-app icons; empty state; settings panel (hotkey, history limit, clear all); graceful Accessibility fallback; app/menu bar icons; `.dmg` distribution script.

**Phase 3 (Pre-Release Quality):** Test isolation; Open at Login; sensitive-item detection with 15-min auto-expiry and masked cards; click-to-paste and Backspace-to-delete; text search (animated pill, auto-engage, scoped Backspace); UI polish (selection border, card sizing, tinted backgrounds, code-item dark treatment).

**Phase 4 (Distribution):** Repo made public (MIT); README with screenshots and install instructions; CI test check on PRs; automated binary releases via GitHub Actions on version tags; Homebrew tap (`jtreanor/homebrew-recall`) with auto-update on release.

> **Notarization** (optional upgrade): if Apple Developer Program membership is obtained, wire up `scripts/distribute.sh --notarize` in CI and drop the `postflight` quarantine removal from the cask.

---

## Version 1.1.0

### Phase 5 — Rich Text Paste ✓

_Capture and restore formatting when the clipboard contains rich text._

- [x] Extend `ClipboardMonitor` to capture RTF/attributed-string data alongside plain text
- [x] Store rich-text representation in the DB (BLOB column `rtf_data`)
- [x] Update paste-back to write RTF to the pasteboard when available, falling back to plain text
- [x] Add Settings toggle: **Plain Text Only** (default: off)
- [x] Update card rendering: type label shows "Rich Text" when RTF data is present
- [x] Tests: rich-text round-trip, plain-text-only mode, fallback when no RTF stored (`RichTextTests.swift`)

### Phase 6 — URL Detection ✓

_Recognise URLs as a first-class item type._

- [x] On capture (and on DB load), run a lightweight URL detector over text items
- [x] Annotate matching items with a `url` type in the data layer
- [x] Card UI: show domain as a secondary label (e.g. `github.com`) and a URL-type badge
- [ ] (Optional) Fetch and cache favicon; display on card — deferred
- [x] Tests: URL detection accuracy (plain URL, URL mid-sentence, non-URL text), card label rendering

### Phase 7 — File Handling ✓

_Surface copied files and their paths as usable clipboard items._

- [x] **Research first:** paste file URLs back to `NSPasteboard` (not path strings); documented in `docs/research.md`.
- [x] Extend `ClipboardMonitor` to detect `public.file-url` items (checked before text to avoid path-string captures)
- [x] Store file items: path(s) as JSON in `file_paths` column; display name derived from filename(s); multi-file handled as single item; hash from sorted paths (order-insensitive deduplication)
- [x] Card UI: SF Symbol file icon (type-aware), filename, `+N` count badge for multi-file selections
- [x] Paste-back: write `NSURL` objects via `writeObjects`; fall back to path string if files no longer exist
- [x] DB migration: table rebuild to extend CHECK constraint to allow `'file'` type + add `file_paths` column
- [x] Tests: single file, multi-file, paste-back, fallback, deduplication, order-insensitive hash, monitor detection, search (`FileHandlingTests.swift`)

### Phase 8 — README Refresh

_Make the README compelling and useful for people discovering the app for the first time._

- [ ] Rewrite the opening hook: lead with the core value proposition (summon → glance → paste) rather than a feature list
- [ ] Add a short animated GIF or screen recording showing the overlay in action
- [ ] Add a "Why Recall?" section: contrast with system clipboard and other clipboard managers; call out keyboard-first, privacy (no cloud), open source
- [ ] Improve install section: clearer Homebrew one-liner, note the Accessibility permission prompt and why it's needed
- [ ] Add a Usage section: hotkey, search, keyboard controls — enough for a new user to feel productive immediately
- [ ] Review and tighten all existing sections for clarity and brevity

---

## Known Bugs

- **Opening animation has a slight horizontal drift (gap visible on left side).** Two approaches attempted: (1) deriving start frame from target to avoid double `visibleFrame()` call; (2) replacing `NSAnimationContext setFrame` with a `CABasicAnimation` on the content view's `transform` layer — neither fixed it. Root cause is unclear; suspect `NSVisualEffectView` or the window compositor introducing a horizontal component. Needs further investigation (possibly: `NSWindow.animator()` with y-only `setFrameOrigin`, or a wrapper clip view inside the visual effect view).

## Implementation Notes

- Keep `NSPanel` subclass minimal; prefer SwiftUI for all rendered content
- Image processing (PNG encode, thumbnail) must never happen on main thread
- Test paste-back with: Xcode, Safari, Terminal, VS Code, Notes — all behave differently
- Do not add SPM dependencies without a concrete blocking reason

---

## Current Status

**Version:** 1.1.0-dev (Phase 7 complete)  
**Next:** Phase 8 — README Refresh
