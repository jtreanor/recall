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

- **Overlay shows a brief left-edge gap on open** — **FIXED 2026-06-11 by approach M (PR #41); history kept below for the methodology.** *Re-characterized 2026-06-11; this was originally filed as "opening/closing animation has a slight horizontal drift" and chased as an animation bug for a month. There were two distinct artifacts hiding under that one report:*

  1. **The dramatic artifact (the original complaint): ~100px+ horizontal misalignment of the blur backdrop vs. panel content during the close slide.** Last confirmed sighting: the 2026-05-19 recording on `feature/animation-fix-approach-j`. **No longer reproduces as of 2026-06-11** — not in an unfixed-baseline control, not with the Dock restored to its May position (auto-hidden, left edge). Most plausible cause of disappearance: a macOS update between 2026-05-19 and 2026-06-11. Status: *cannot reproduce → cannot fix or verify; reopen only if seen again, and immediately capture a baseline control.*
  2. **A constant, subtle artifact: the whole panel (blur + content together) composites ~20–28px right of the screen edge for the first ~6 frames (~100ms) after the window appears, decaying to zero.** This is **not an animation bug**: it appears identically with the slide animation, with a synchronous animation, with an opaque material, with a stationary window revealed by a mask, and with *no animation at all* (instant `orderFront`). It is the Window Server settling a freshly composited `NSVisualEffectView` window — every `show()` cold-starts the backdrop because `hide()` orders the panel out. It is present in the May recordings too, underneath artifact 1, and predates all fix attempts. Whether it is ever perceptible to a user at real speed is an open question. **Fixed: approach M (warm panel, see below), verified quantitatively against a same-day baseline and merged 2026-06-11 (PR #41).**

  Logged frame values (x=0, width=1470) are correct throughout in both cases — both are compositing artifacts, not geometry bugs.

  **Approaches already tried (all failed):**
  1. `animator().setFrame()` on the window — original; drift present.
  2. `animator().setFrameOrigin()` on the window — window failed to appear at all.
  3. `CABasicAnimation` on content view's `transform` layer — same drift.
  4. Wrapping `NSVisualEffectView` in a plain `NSView` container; animating subview frame — identical artifact.
  5. Keeping `NSVisualEffectView` fixed at final position and growing window height from 0 → 260 — drift gone but reveal feel is wrong (peel-up rather than slide-in).
  6. Layer-backed container as `contentView` with approximate hudWindow background colour, `NSVisualEffectView` as subview at alpha 0 during slide and faded in at rest (mirror on close). Drift still visible; appearance worse than the original.

  **Diagnostic findings (2026-05-16 recording):** 60fps `screencapture -v` captured the artifact frame-by-frame. On close it is a **multi-pixel, ~100px+** horizontal misalignment of the blur backdrop vs. the panel content — not a single-frame glitch. Visible on both open (subtle) and close (dramatic). This rules out any "redraw timing" explanation and confirms the WindowServer-backdrop-lag hypothesis: the backdrop is being composited at the previous animation step's position while the panel content has already moved.

  **Tried and rejected (in addition to 1–6 above):**

  - **A. Snapshot the resting panel and slide that.** Implemented: capture cards-only via `cacheDisplay` on the hosting view, layer over a dark slab tuned to the live blur color, slide the slab+cards inside a fixed-position window, crossfade slab→live `NSVisualEffectView` at the end. Build worked and removed the drift entirely. **Rejected by user:** the slide doesn't have live blur underneath, and the crossfade brightness/blur step at the handoff is visibly worse than the original drift. User strongly prefers the original feel (live blur + window slides up) even with the drift.
  - **I. Toggle `visualEffect.state` to `.inactive` during the slide.** Implemented on `feature/animation-fix-approach-i` (now deleted): flipped `.inactive` at the top of `show()` / `hide()`, restored `.active` in `show()`'s completion handler. **Failed both axes:** drift was still present during the slide, AND the `.inactive ↔ .active` handoff produced a visible color flash at rest. Net worse than baseline. **Falsifies the "WindowServer composites the blur backdrop and lags" hypothesis** — if dropping to the flat fallback fill leaves the same drift, the moving thing isn't (only) the blur backdrop. The dual-NSVisualEffectView crossfade fallback for I is therefore also dead. Likely culprits to investigate instead: (a) the rounded-corner mask layer drifting (we set `cornerRadius=12` + `maskedCorners` + `masksToBounds=true` on the visual effect's layer), or (b) `animator().setFrame()` driving the window-frame animation off the main thread while content composites on a different clock — WWDC 2013 Session 213 explicitly warns this produces "drifting or jitter."
  - **J. Remove the corner-mask from the visual effect view during the slide.** Implemented on `feature/animation-fix-approach-j` (2026-05-19): kept a reference to the `NSVisualEffectView`, set `masksToBounds=false` + `cornerRadius=0` at the top of `show()`/`hide()`, restored in `show()`'s completion handler. **Failed:** 60fps recording (`~/Desktop/recall-approach-j.mov`) shows the same multi-pixel left-edge gap on close at frames 79–82. **Falsifies the "corner-mask layer composites on a different clock" hypothesis** — if removing the mask entirely leaves the same drift, the mask isn't the moving thing. Combined with the I finding (it's not the blur backdrop either), the surviving hypothesis is the WWDC 2013 Session 213 one: `animator().setFrame()` runs the window-frame animation off the main thread while content composites on a different clock → "drifting or jitter." That points to **K** next. Branch reverted; no merge.
  - **K. Drive the slide with synchronous `setFrame(_:display:animate:)` instead of `animator().setFrame()` inside `NSAnimationContext`.** Implemented on `feature/animation-fix-approach-k` (2026-06-06): replaced both animation blocks in `show()`/`hide()` with `setFrame(target, display: true, animate: true)` (hide's teardown now runs inline since the call blocks until the slide completes), and overrode `animationResizeTime(_:)` on `OverlayPanel` to return `0.15`. **Verified the duration is honored:** `NSLog` timing around the call shows `setFrame` blocks 152–156ms every open/close, so the override holds the 150ms timing (the WWDC concurrency premise is satisfied — the frame animation is now synchronous on the main thread).
    - **Gap (the primary question): appears fixed.** *[Superseded — see the 2026-06-11 session correction below: the gap is present in K's own recordings under quantitative measurement.]* Captured two 60fps `screencapture -v` recordings and inspected frame-by-frame: real-speed 150ms (`~/Desktop/recall-approach-k.mov`) and a temporary 0.45s slow-mo (`~/Desktop/recall-k-slowmo.mov`, ~27 inspectable frames per slide — K's "no cross-thread concurrency" premise predicts zero drift at any speed). Neither recording shows the dramatic ~100px+ left-edge blur-vs-content misalignment that J's recording showed at frames 79–82. Blur backdrop and card content stay aligned throughout open and close. (Caveat: the slow-mo desktop region was near-black, so a gap exposing *desktop* would be low-contrast — but the described artifact is the card detaching from the blur rectangle, which would be visible against any background, and it isn't.)
    - **Feel: regressed — this is the blocker.** The legacy `setFrame(display:animate:)` path is **not** the smooth 60fps Core Animation slide that `animator().setFrame` produced. At the real 150ms, the 60fps capture (279 frames / 4.6s ≈ no dropped frames) caught only ~4–5 motion frames on open and a near-instant 1-frame jump on close (f189 fully resting → f190 ~90% gone), i.e. a coarse/steppy slide rather than a fluid one. The 450ms slow-mo looked smoother only because the same coarse step interval spans more frames. Easing also changed (`animate:` exposes no timing function; the easeOut/easeIn are gone, and the close in particular reads as abrupt). Live blur + bottom slide-up direction *are* preserved.
    - **Status: awaiting user verdict on feel before any merge.** Gap looks solved but the slide is choppier than baseline, which collides with the "smooth live-blur slide-up is non-negotiable" bar. Branch `feature/animation-fix-approach-k` retained (not merged, no PR). If the choppiness is rejected, next candidate is **L**. Scaffolding used for capture (a temporary Darwin-notification toggle in `AppDelegate` + `NSLog` timing) has been removed; the branch diff is just the K change + this log.

  - **L. `allowsInPlaceFiltering = false` on the `CABackdropLayer`s (private API, via KVC).** Implemented on `feature/animation-fix-approach-l` (2026-06-11) on the original `animator().setFrame` easeOut/easeIn path (K's synchronous slide reverted). Walks `contentView.layer`'s sublayer tree and sets the flag via KVC behind a `responds(to:)` guard. Two reusable timing notes: (a) the backdrop subtree does **not exist** at `makeKeyAndOrderFront` time — it is built lazily on the first display pass, so the walk needs a `displayIfNeeded()` first (layer-tree dump: zero `CABackdropLayer`s before display, six after — the hudWindow blur plus SwiftUI card materials); (b) re-walk in `hide()` because SwiftUI adds more backdrop layers after open (seven by close). **Failed: no measurable effect** — open frames carry the same decaying ~16–21px right-shift as the same-day baseline control, frame for frame. (An initial "fixed" verdict was retracted: it sampled frames past the artifact window.) Recordings: `~/Desktop/recall-approach-l.mov`, `recall-l-slowmo.mov`.
  - **D. `setAnchorAttribute(.left, for: .horizontal)` before each slide.** Implemented on `feature/animation-fix-approach-d` (2026-06-11) on the animator path. **Failed: no measurable effect** (open gap 20→14→10→6→4→2 vs. baseline 21→11→7→4→2→1). Anchor attributes evidently affect constraint-driven resize anchoring only, not Window Server compositing of an animated frame move. Recordings: `~/Desktop/recall-approach-d.mov`, `recall-d-slowmo.mov`.
  - **G. Material A/B: `.sidebar` and `.windowBackground`.** Tested on `feature/animation-fix-approach-g` (2026-06-11). **Failed as a fix, decisive as a diagnostic:** `.sidebar` gaps identically to baseline, and — the headline — **fully opaque `.windowBackground` gaps identically too** (24→20→14→10→6→4→2; `~/Desktop/recall-g-windowbg.mov`). A window with no blur backdrop drifts the same, killing the entire backdrop-lag hypothesis family and pointing at window-level compositing. Branch keeps `.hudWindow`; the value of G is this finding.
  - **M. Never order the panel out — keep the backdrop warm.** Implemented on `feature/animation-fix-approach-m` (2026-06-11). **Success on every measured axis — the only approach to beat baseline; feel approved by user, merged 2026-06-11 (PR #41).** Final shape: `warmUp()` parks the panel in the window list at the resting frame with `alphaValue = 0` + `ignoresMouseEvents = true` (`orderFrontRegardless`, called once at launch); `show()` flips alpha to 1 before `makeKeyAndOrderFront` and runs the original `animator().setFrame` easeOut slide unchanged; `hide()` runs the easeIn slide unchanged, then in the completion handler calls `orderOut` (key resignation exactly as before) followed immediately by `warmUp()`, so any re-composite settle decays invisibly at alpha 0 long before the next summon.
    - **Decisive control passed (premise confirmed):** warm panel + instant alpha-flip show (no slide) composites at edge 0/0/0 from the very first visible frame on both opens (`~/Desktop/recall-m-instant.mov`), while the same-day unfixed baseline settles 20→14→10→7→4→2→1 / ~10→6→4→2 (`~/Desktop/recall-m-baseline.mov`).
    - **Full slide passed:** edge 0 from the first motion frame on both opens (`~/Desktop/recall-approach-m.mov`); open 2 follows a full `orderOut` → re-warm cycle, proving the re-warm works (a window ordered in at alpha 0 that has never been visible still warms — launch-warm open 1 proved the same).
    - **Key-window finding (the reason for the orderOut+re-warm shape):** a pure alpha-0 hide leaves the invisible panel with `isKeyWindow = true` — a nonactivating key panel could keep swallowing keystrokes after dismissal. Could not be falsified without Accessibility, so the final variant resigns key via `orderOut` as before; probe confirms `isKeyWindow = 0` after hide while the panel stays in the window list, occlusion-visible at alpha 0.
    - **Feel: better than baseline, not just equal.** 9 motion frames each way at the original 150ms easeOut/easeIn with live blur. The close's per-frame motion profile matches baseline frame-for-frame (3342/3190/3571/4154/4494/4593/4530/3616/783 vs 3346/3193/3598/4131/4491/4593/4534/3614/784). The open is *smoother* than baseline: baseline's first composite arrives mid-slide as a single huge pop (MAE 15930 — ~60% of the panel in one frame; the settle was eating the first animation frames), M renders a clean monotonic easeOut ramp (6600→4684→4570→4245→3983→3284→3073→2132→663).
    - **Watch-fors measured:** no detectable WindowServer CPU delta with the parked panel (ambient ~40% with and without; Recall idles at 0.0%). The parked window **is** enumerated by `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` (alpha 0, layer 3, resting bounds) — it contributes no pixels to screen recordings (all session captures show nothing at rest) but may be listed by window-picker UIs. `ignoresMouseEvents = true` while parked so the invisible window can't intercept clicks along the bottom of the screen. Not yet manually verified (needs a human): space-switch behavior at alpha 0 (`canJoinAllSpaces` unchanged) and real-keyboard typing after an Escape dismissal — spot-check both during the feel review.
  - **B. Mask-layer reveal inside a stationary window.** Implemented on `feature/animation-fix-approach-b` (2026-06-11): window goes straight to its resting frame (never animated); a bottom-anchored black `CALayer` mask on the content view animates its height 0→260 (easeOut) / 260→0 (easeIn); mask dropped at rest. **Gap: identical to baseline** (28→22→17→12→8→5 on open) even though nothing about the window moves — the observation that forced the instant-show experiment below. **Feel: a wipe, not a slide** (cards revealed in place; live blur preserved). Structurally immune to *motion* drift, so it is the standing fallback if artifact 1 ever returns. Recording: `~/Desktop/recall-approach-b.mov`.

  **2026-06-11 session correction — re-read this before trusting anything above.** A full candidate sweep (L, D, G, B; each on its own `feature/animation-fix-approach-<x>` branch, each 60fps-captured and measured) plus same-day controls rewrote the picture:

  1. **K's "gap appears fixed" claim is falsified.** A quantitative detector (per-frame x-position of the panel's left edge, measured at three heights — first column that is bright `>0.39` *and* desaturated `<0.25`, so blur-over-dark-terminal counts but wallpaper doesn't) applied to K's *own* June 6 real-speed recording shows the open-side gap plainly: 26→26→15→15→10→7 px across the first ~7 frames. The June 6 inspection missed it because (a) it looked only for the dramatic ~100px card-vs-blur detachment signature from J's recording, and (b) the slow-mo "confirmation" shrinks the artifact ~3× (it scales with per-frame animation step) on top of a near-black desktop that hides it. Same result when K was rebuilt and recaptured on 2026-06-11 (`~/Desktop/recall-k-today.mov`): 26→20→15→10→7→4→2.
  2. **Today's measurable artifact is not motion drift at all.** Every variant shows an identical decaying right-shift of the whole panel (blur *and* content together) on open — baseline 21→11→7→4→2→1, K 26→…, L 16→…, D 20→…, G(.sidebar) 20→…, G(.windowBackground, **fully opaque**) 24→…, B (stationary window, mask reveal) 28→…. The decisive control: an **instant-show build with no animation whatsoever** (window ordered front at its final frame) still shows 23→13→9→5→3→1→0 over the first ~6 frames (`~/Desktop/recall-instant-show.mov`). The artifact is the Window Server **settling a freshly composited window** (blur ramp-in / first-composite behavior), visible against the dark terminal at the left edge. It happens on every open regardless of how — or whether — the slide is animated, which is why no candidate could ever beat any other on it. J's May 19 recording shows the same decaying open-side settle, so it has probably always been there, underneath the real bug.
  3. **The real May bug (dramatic ~100px blur-vs-content detachment on close) no longer reproduces.** A same-day unfixed-baseline control (`~/Desktop/recall-baseline-control.mov`) has a completely clean close, as does every other capture this session. Restoring the May Dock placement (auto-hidden, left edge) and re-capturing baseline + K changed nothing (`~/Desktop/recall-baseline-dockleft.mov`, `~/Desktop/recall-k-dockleft.mov`). Attempting to re-verify the artifact in J's May 19 recording failed — in a fresh extraction the close drops from at-rest to gone in a single frame (VFR frame drops), so the documented "frames 79–82" can't be re-derived. Most plausible explanation: a macOS update between 2026-05-19 and 2026-06-11 changed Window Server behavior. **Verdict: cannot currently be reproduced, therefore cannot be fixed or verified against.**
  4. **Candidate scoreboard (all measured against same-day baseline):** L (private `allowsInPlaceFiltering=false`) — no effect; D (`setAnchorAttribute`) — no effect; G (`.sidebar` / opaque `.windowBackground`) — no effect, but proves the artifact is not blur-related; B (mask reveal in a never-animated window) — no effect on the settle, structurally immune to motion drift, but the reveal is a wipe rather than a slide. K — no better than baseline on the settle, and still has the choppier legacy-path slide. **Nothing beats the plain `animator().setFrame` baseline on today's evidence; K's feel regression buys nothing demonstrable.**
  5. **Methodology lessons now baked into the harness notes below:** always capture a same-day *unfixed baseline control* before judging a fix; the artifact window is the first ~6 frames of the rise (sample those, not mid-slide); use the quantitative edge detector instead of eyeballing zooms (blur-over-dark-terminal reads as "missing blur" to the eye); remember `screencapture -v` output can be VFR — verify frame counts before trusting indices.

  **Approaches to explore next** (ordered by promise / cost):

  - ~~**M.** Never order the panel out — keep the backdrop warm~~ — **tried 2026-06-11, works; settle eliminated and open is smoother than baseline. Merged (PR #41); see the M entry above.**
  - ~~**L.** `allowsInPlaceFiltering = false`~~ — tried 2026-06-11, no effect; see `feature/animation-fix-approach-l`.
  - ~~**B.** Mask reveal inside a stationary window~~ — tried 2026-06-11, no effect on the settle (wipe feel); see `feature/animation-fix-approach-b`.
  - ~~**D.** `setAnchorAttribute(.left, for: .horizontal)`~~ — tried 2026-06-11, no effect; see `feature/animation-fix-approach-d`.
  - ~~**G.** Material A/B (`.sidebar`, `.windowBackground`)~~ — tried 2026-06-11, no effect; proved the artifact is not blur-related; see `feature/animation-fix-approach-g`.
  - **C. Re-try Core Animation on the window's backing layer with `CATransaction` actions disabled.** Window stays at final frame; animate `contentView.layer.transform` translation. Moot for the settle artifact (B already proves a stationary window doesn't help), only relevant if the May detachment returns.
  - **E. SwiftUI-driven `.transition(.move(edge: .bottom))` inside a fixed-size window.** Same caveat as C: stationary-window approaches don't touch the settle artifact.
  - **F. Force synchronous redraw per animation frame (`CVDisplayLink` + `displayIfNeeded()`).** Moot for the settle artifact (it appears with zero animation).
  - **H. Search AppKit forums / file Apple feedback.** The *settle-on-appear* of a fresh `NSVisualEffectView` window is likely a known WindowServer behavior; the May close-detachment may be a known (and possibly already-fixed) bug. Worth doing alongside M.

  **Diagnostic step regardless of approach:** capture a high-FPS screen recording (60–120 fps) so the artifact can be inspected frame-by-frame — confirms whether it is a single-frame glitch or a multi-frame drift, and on which edge.

  **Animation capture harness (how the K recordings were made — reusable for L and beyond):**

  1. **Driving open/close without the hotkey.** Synthesizing the global ⌘⇧V hotkey from a script fails — `osascript ... "key code 9"` returns `not allowed to send keystrokes (1002)` because the controlling terminal/host lacks Accessibility permission, and a notarized helper isn't worth it. Workaround: a **temporary, permission-free Darwin-notification toggle**. Add this to `AppDelegate.setupHotkey()` (and **delete before merge**):

     ```swift
     // TEST-ONLY: permission-free toggle for the screen-recording harness.
     // Fire with:  notifyutil -p com.recall.debugToggle
     CFNotificationCenterAddObserver(
         CFNotificationCenterGetDarwinNotifyCenter(),
         Unmanaged.passUnretained(self).toOpaque(),
         { _, observer, _, _, _ in
             guard let observer else { return }
             let me = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
             DispatchQueue.main.async { me.isOverlayVisible ? me.hideOverlay() : me.showOverlay() }
         },
         "com.recall.debugToggle" as CFString, nil, .deliverImmediately)
     ```

     It routes through the same `showOverlay()`/`hideOverlay()` path the hotkey uses, so the animation under test is untouched. (Alternative for full automation: grant Accessibility to the terminal and use `osascript` ⌘⇧V instead — then no app changes needed.)

  2. **Record + drive (run the whole thing in one backgrounded script so the `sleep`s aren't blocked):** launch the Debug `.app`, seed a few clipboard items with `pbcopy` so the overlay has content, then `screencapture -v out.mov &`, `notifyutil -p com.recall.debugToggle` (open), sleep ~1.5s, `notifyutil` again (close), sleep, `kill -INT` the `screencapture` PID to finalize the file.

  3. **Inspect frame-by-frame.** `ffprobe -show_entries stream=nb_frames,r_frame_rate,duration` to confirm ~60fps and no dropped frames (frame count ÷ duration ≈ 60). `ffmpeg -i out.mov -vf "crop=560:600:0:1312" f_%03d.png` to extract just the bottom-left corner (Retina coords; panel = bottom 520px) where the gap lives. Build labeled contact sheets with ImageMagick `montage ... -label '%f'` to locate the transition frames, then `magick <frame> -crop 300x600+0+0 -resize 300%` to zoom the left edge. **Gotcha:** `montage`/`magick` labels need an explicit `-font /System/Library/Fonts/Helvetica.ttc` on this box or they error with `unable to read font`.

  4. **Two measurements that resolved K** and are worth repeating: (a) **`NSLog` wall-clock around the `setFrame` call** to prove the real animation duration (don't infer it from frames); (b) a **temporary slow-mo** — bump `animationResizeTime` to e.g. `0.45` — to get ~3× more inspectable frames per slide when the real-speed capture is too coarse to judge. Restore the real duration afterward. **Caution (2026-06-11): slow-mo shrinks step-proportional artifacts ~3× — it can hide the gap it is supposed to expose. Treat a clean slow-mo as weak evidence.**
  5. **Quantitative left-edge detector (2026-06-11; use this instead of eyeballing).** For each frame, at three heights (`y=320/420/520`, 60px bands of the 560×600 bottom-left crop), find the first column that is bright (gray mean >100/255) **and** desaturated (HSL S <64/255) after `-resize '560x1!'` column-averaging. Blur-over-dark-terminal passes (≈131); raw terminal (≈43) and the green wallpaper strip fail. Reports the panel's actual left-edge x per frame; the at-rest value must read 0 (threshold sanity check) before trusting motion frames. Script preserved in the session log; trivially rebuilt from this description. Two protocol rules learned the hard way: **(a) always capture a same-day unfixed-baseline control** — without it, "fix verified" is unfalsifiable; **(b) the artifact lives in the first ~6 frames of the rise** — locate motion frames with a brightness scan (10px inner strip at x=100) and measure those, not mid-slide samples. **(c) screen the recording before trusting or keeping it** — confirm the pre-open frames read as the expected dark-terminal backdrop (≈47). A 2026-06-11 capture was silently invalidated (and had to be deleted) when another app's window drifted into the capture region mid-session; this check catches both bad calibration and accidental capture of unrelated personal content. **(d) per-frame MAE between consecutive frames (`magick compare -metric MAE`) is a cheap motion/easing profile** — it counts motion frames, exposes easing shape, and made baseline's settle-induced first-frame pop (MAE 15930 vs M's 6600) directly visible.

## Implementation Notes

- Keep `NSPanel` subclass minimal; prefer SwiftUI for all rendered content
- Image processing (PNG encode, thumbnail) must never happen on main thread
- Test paste-back with: Xcode, Safari, Terminal, VS Code, Notes — all behave differently
- Do not add SPM dependencies without a concrete blocking reason

---

## Current Status

**Version:** 1.1.0-dev (Phase 7 complete)  
**Next:** Phase 8 — README Refresh
