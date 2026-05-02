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

### Phase 5 — Rich Text Paste

_Capture and restore formatting when the clipboard contains rich text._

- [ ] Extend `ClipboardMonitor` to capture RTF/attributed-string data alongside plain text
- [ ] Store rich-text representation in the DB (or alongside the existing text row)
- [ ] Update paste-back to write RTF to the pasteboard when available, falling back to plain text
- [ ] Add Settings toggle: **Paste as plain text only** (default: off)
- [ ] Update card rendering to indicate when an item has rich-text data (subtle badge or no change — decide during implementation)
- [ ] Tests: rich-text round-trip, plain-text-only mode, fallback when no RTF stored

### Phase 6 — URL Detection

_Recognise URLs as a first-class item type._

- [ ] On capture (and on DB load), run a lightweight URL detector over text items
- [ ] Annotate matching items with a `url` type in the data layer
- [ ] Card UI: show domain as a secondary label (e.g. `github.com`) and a URL-type badge
- [ ] (Optional) Fetch and cache favicon; display on card — defer if fetch latency is a concern
- [ ] Tests: URL detection accuracy (plain URL, URL mid-sentence, non-URL text), card label rendering

### Phase 7 — File Handling

_Surface copied files and their paths as usable clipboard items._

- [ ] **Research first:** determine best strategy for files — `NSPasteboard` file promises vs. paths vs. actual file data. Key question: on paste, should Recall re-paste the file object (so it lands in Finder/apps as a file) or paste the path string? Document the decision in `docs/research.md`.
- [ ] Extend `ClipboardMonitor` to detect `NSFilenamesPboardType` / `public.file-url` items
- [ ] Store file items: path(s), display name, UTI/icon reference; handle multi-file selections as a single item
- [ ] Card UI: filename + file-type icon; multi-file items show count badge
- [ ] Paste-back: implement the strategy decided during research
- [ ] Tests: single file capture, multi-file capture, paste-back behaviour

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

**Version:** 1.0 shipped (Phase 4 complete)  
**Next:** Phase 5 — Rich Text Paste (start of v1.1.0)
