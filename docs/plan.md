# Recall — Implementation Plan

_Living document. Update when implementation diverges from plan._

---

## Phases 1–3 — Complete

**Phase 1 (Foundation):** Menu bar app, clipboard monitor (text + images), SQLite persistence, floating overlay panel, global hotkey (`⌘⇧V`), keyboard navigation, paste-back via `CGEvent`.

**Validation:** Test suite confirmed stable across 3 runs; integration tests cover full data path, dedup, history cap, and persistence; manual checklist passed.

**Phase 2 (Polish):** Bottom-anchored slide-up tray; horizontal card layout; source-app icons; empty state; settings panel (hotkey, history limit, clear all); graceful Accessibility fallback; app/menu bar icons; timestamp/image-clipping fixes; `.dmg` distribution script (notarization deferred pending Apple Developer cert).

**Phase 3 (Pre-Release Quality):** Test isolation (injectable DB path, scoped `UserDefaults`); Open at Login (`SMAppService`); sensitive-item detection (`org.nspasteboard.ConcealedType` + password-manager bundle IDs) with 15-min auto-expiry and masked cards; click-to-paste and Backspace-to-delete; text search (animated pill, auto-engage, scoped Backspace); UI polish (selection border, card 180×200, panel 260pt, tinted card backgrounds, code-item dark treatment, image pill overlay); test coverage gaps closed.

---

## Phase 4 — Open Source and Distribution

_Pursue when the app is stable enough to share publicly._

- [x] **Repo history review** — reviewed all 95 commits and current working tree. Two commit subjects reference "Paste-style" (commits 5b3f33e, f9f90c3); decision: **leave history** (scrubbing rewrites all SHAs and destroys PR links — cost outweighs benefit for minor stylistic references). Renamed `docs/research.md` section "Paste UX Analysis" → "Clipboard Manager UX Analysis" since that file is publicly visible. No credentials, personal data, or sensitive content found anywhere.
- [x] **Open source the repo** — made `jtreanor/recall` public on GitHub; added `LICENSE` (MIT) and `README.md` with screenshots, install instructions, and feature overview
- [x] **CI: test check on PRs** — added `.github/workflows/test.yml`; runs `xcodebuild test` on every PR and push to `main`; set as required status check before merge
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

**Phase:** Phase 4 — Open Source and Distribution  
**Milestone:** Repo public, CI wired up.  
**Next task:** Automated binary releases — GitHub Actions workflow on version tags, builds universal DMG, uploads as GitHub Release asset.

