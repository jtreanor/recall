# Recall — Research & Architecture

## Paste UX Analysis

### Worth copying for v1
- Keyboard-invoked overlay (global shortcut, summons from any app)
- Visual grid/list of recent items — text previews + image thumbnails
- Arrow key navigation with live highlight
- Enter to paste into previously focused app
- Instant dismiss on Escape or click-away
- Deduplication (most-recent wins)
- Fast, low-latency appearance (no animation lag, no loading state)
- Text truncation previews — enough context to identify an item

### Defer to later phases
- Pinned items / favorites
- Multi-item select and paste
- Per-app clipboard history filtering
- Customizable history limit via UI
- Rich text formatting preservation display
- Search / filter bar
- Source-app attribution badges

### Avoid entirely (v1 or ever)
- Sync / iCloud / accounts
- Snippets / templates / macros
- OCR on images
- Collaboration or sharing
- AI features
- Web clipboard / universal clipboard beyond what macOS already does
- Paste Queue / multi-paste
- Collections, boards, tagging
- Analytics, telemetry, crash reporting to third-party services

---

## Technical Decision Areas

### 1. Clipboard Monitoring

**The problem:** macOS does not push notifications when clipboard content changes. You must poll.

**Approach:**
- `NSPasteboard.general.changeCount` — integer that increments on every write
- Poll on a `DispatchSourceTimer` at ~0.5–1s interval (background queue)
- On change, read `NSPasteboard.general` to extract content
- Read `string(forType: .string)` for plain text
- Read `data(forType: .tiff)` or `NSImage(pasteboard:)` for images
- Check `availableType(from:)` to know what's present before reading

**Supported types for v1:**
- `NSPasteboard.PasteboardType.string` — plain text
- `NSPasteboard.PasteboardType.tiff` / `.png` — raster images
- Consider: `NSFilenamesPboardType` for file references (defer)

**Interval tradeoff:** 0.5s feels instant; 1s is fine for most use. Go with 0.75s to split the difference.

---

### 2. Persistence & History Model

**Options compared:**

| Option | Pros | Cons |
|--------|------|------|
| SQLite (raw or GRDB) | Fast, mature, flexible schema | Extra dependency (GRDB) or verbose raw API |
| CoreData | Apple-native, Xcode tooling | Heavy for this use case; overkill |
| Flat files + JSON index | Simple, no dep | Slow queries at scale; fragile |
| SQLite via Foundation's built-in | No extra dep | Verbose but workable |

**Recommendation: Raw SQLite3 via Swift's C interop** or a thin wrapper.
- No SPM dependency needed — SQLite3 ships with macOS
- Schema: `items(id, timestamp, type, text_content, image_path, hash, source_app)`
- Keep it in `~/Library/Application Support/Recall/`
- Cap history at 500 items (configurable via constant, not UI)
- On insert: check hash for deduplication; if exists, update timestamp and reorder

**Schema sketch:**
```sql
CREATE TABLE items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('text','image')),
  text_content TEXT,
  image_path TEXT,
  content_hash TEXT NOT NULL UNIQUE
);
CREATE INDEX idx_updated ON items(updated_at DESC);
```

---

### 3. Image Storage Strategy

**The problem:** Images can be large. Storing TIFF blobs in SQLite kills performance and bloat.

**Approach:**
- Store image files on disk: `~/Library/Application Support/Recall/images/<hash>.png`
- Compress to PNG on write (use `NSBitmapImageRep` → PNG representation)
- Generate thumbnails at write time: 200×150px max, stored as `<hash>_thumb.png`
- SQLite row stores the path; the file is the source of truth
- On history trimming, delete orphaned image files

**Memory model:**
- Load only thumbnails for the overlay grid
- Load full image only when user hovers/selects (lazy)
- Keep in-memory LRU cache of last N thumbnails (N = visible items + buffer)

**Size limits:** Reject images over 10MB at paste time to avoid runaway storage. Log and skip silently.

---

### 4. Global Shortcut Registration

**Options:**

| Approach | Reliability | Requires Entitlement | Notes |
|----------|-------------|----------------------|-------|
| Carbon `RegisterEventHotKey` | High | No | Legacy API, still works perfectly on macOS 15 |
| `NSEvent.addGlobalMonitorForEvents` | High | Accessibility permission | Simpler Swift API |
| `CGEventTap` | Highest | Accessibility permission | Most powerful, most complex |
| Swift Package: KeyboardShortcuts (sindresorhus) | High | Accessibility | Good user-configurable shortcuts UX |

**Recommendation: Carbon `RegisterEventHotKey`** for v1.
- No accessibility permission needed for the hotkey itself
- Reliable across macOS versions
- Default binding: `⌘⇧V`
- Wrap in a clean Swift struct; ~30 lines

---

### 5. Floating Overlay / Panel Architecture

**The fundamental constraint:** The overlay must appear on top of any app without stealing focus from the previously active app in a disruptive way — yet must accept keyboard events.

**Options:**

| Approach | Focus Behavior | Notes |
|----------|---------------|--------|
| `NSPanel` + `.nonactivatingPanel` style mask | Stays key without activating app | Trickiest but most correct |
| `NSWindow` at `.floating` level, manual activate/restore | Simple but jarring focus switch | Flicker when restoring focus |
| `NSPanel` + temporarily activate app + restore | Clean but requires tracking frontmost app | Most reliable for paste-back |

**Recommended approach: `NSPanel` with `NSWindowLevel.floating`, temporarily activating the app.**
1. Record `NSWorkspace.shared.frontmostApplication` before showing
2. Call `NSApp.activate(ignoringOtherApps: true)` so the panel accepts keys
3. On dismiss/paste, re-activate the previously frontmost app, then simulate ⌘V

**Visual style:**
- Vibrancy (`NSVisualEffectView`, `.hudWindow` or `.menu` material) for frosted look
- Rounded corners via `cornerRadius`
- Thin drop shadow via `NSWindow.hasShadow`
- Appears near center-bottom or center of screen (not cursor-relative for v1)

---

### 6. Keyboard Navigation

- `NSPanel` is a responder; override `keyDown(with:)` or use a `SwiftUI` `onKeyPress` modifier
- Arrow up/down: move selection index ± 1, scroll to keep in view
- Enter: trigger paste of selected item, dismiss
- Escape: dismiss without action
- ⌘1–9: quick-select by position (defer to later phase)

---

### 7. Paste-back Behavior

This is the most fragile part of the whole system. Steps:

1. When hotkey fires: record `previousApp = NSWorkspace.shared.frontmostApplication`
2. Show panel (app briefly activates to receive keys)
3. User selects item and presses Enter:
   a. Write selected content to `NSPasteboard.general`
   b. Dismiss panel
   c. `previousApp?.activate(options: .activateIgnoringOtherApps)`
   d. After a short delay (~50ms for the app to become active), post a synthetic ⌘V `CGEvent`

**Posting synthetic ⌘V:**
```swift
let src = CGEventSource(stateID: .hidSystemState)
let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) // V
keyDown?.flags = .maskCommand
let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
keyDown?.flags = .maskCommand
keyDown?.post(tap: .cghidEventTap)
keyUp?.post(tap: .cghidEventTap)
```

**Requires:** Accessibility permission (`AXIsProcessTrusted()`). App must prompt user on first launch.

**Edge cases:**
- Target app is gone by the time we paste → no-op, content still on clipboard
- Target app ignores ⌘V (terminal paste needs ⌘V anyway) → acceptable
- User pastes from overlay while already in Recall → guard against self-paste

---

### 8. Permissions, Sandbox, and Accessibility

**Distribution choice is critical:**

| Distribution | Sandbox | Clipboard Access | CGEvent Keystroke | Verdict |
|---|---|---|---|---|
| Mac App Store | Required | Yes (no entitlement needed) | Requires `com.apple.security.automation.apple-events` — often rejected | Avoid for v1 |
| Direct / notarized | Not required | Yes | Yes (with accessibility permission) | **Recommended** |

**Permissions required at runtime:**
- **Accessibility** (`AXIsProcessTrusted`): needed to post `CGEvent` for paste-back. Prompt user on first launch with a "Grant Access" button that opens System Settings.
- **No other permissions needed** for clipboard reading, local file storage, or hotkey registration.

**Hardened Runtime entitlements needed (for notarization):**
- `com.apple.security.cs.allow-jit` — not needed
- No special entitlements beyond default hardened runtime for this use case

---

### 9. Performance and Memory for Image Support

- **Clipboard polling:** lightweight — changeCount check is negligible
- **Image write path:** compress to PNG + generate thumbnail on a background `DispatchQueue.global(qos: .utility)`; never block main thread
- **Overlay load:** load only thumbnail images for visible items; ~20 items × 30KB thumb ≈ 600KB — fine
- **Full image preview:** load lazily on selection hover
- **Memory footprint target:** <30MB RSS at idle; <60MB with overlay open
- **History cap:** 500 items prevents unbounded growth; prune oldest on insert

---

## Architecture Options

### Option A: Pure SwiftUI App (`@main` struct + SwiftUI lifecycle)
- `SwiftUI.App` with `NSApplicationDelegateAdaptor` for AppKit hooks
- Overlay is a SwiftUI `View` presented in a `Window` scene or via `NSPanel`
- Simple to start; struggles with fine-grained `NSPanel` control and non-activating behavior
- **Risk:** SwiftUI's window management API has gaps for floating panels; workarounds required

### Option B: AppKit-primary with SwiftUI Views embedded (Recommended)
- `NSApplicationDelegate` owns the app lifecycle, clipboard monitor, persistence, hotkey
- Overlay is an `NSPanel` subclass; contents are a SwiftUI `View` hosted via `NSHostingView`
- Full control over panel behavior, activation policy, window levels
- SwiftUI handles the list/grid rendering cleanly
- Clean separation: AppKit for OS integration, SwiftUI for UI components

### Option C: Full AppKit (no SwiftUI)
- Everything in AppKit: `NSCollectionView` or `NSTableView` for history grid
- Maximum control, no framework friction
- Significantly more boilerplate; slower to build; no advantage given we're targeting macOS 13+

---

## Recommendation: Option B — AppKit shell + SwiftUI overlay views

**Rationale:**
- `NSPanel` control is non-negotiable for the overlay behavior (non-activating, floating, dismissable). SwiftUI's window APIs can't do this cleanly without AppKit interop anyway.
- SwiftUI is materially better than AppKit for rendering a scrollable list of thumbnail cards with selection state — less code, better animation, cleaner state binding.
- Option A forces hacky workarounds for panel behavior. Option C is slower to build with no benefit.
- This hybrid is the dominant pattern in modern macOS utilities (Alfred, Raycast, etc. use equivalent approaches).

---

## Key Risks & Unknowns

| Risk | Severity | Mitigation |
|---|---|---|
| Accessibility permission UX — user may deny | High | Clear first-run prompt; degrade gracefully (copy to clipboard, no auto-paste) |
| Paste-back timing — 50ms delay may not be enough on slow machines | Medium | Make delay a tunable constant; test on older hardware |
| CGEvent paste blocked by some apps (e.g., password managers, secure fields) | Medium | Document this limitation; acceptable behavior |
| PNG compression on large images blocks background thread longer than expected | Low | Profile; add size cap |
| NSPasteboard polling misses rapid successive copies | Low | Acceptable; only last item in burst matters |
| Carbon hotkey conflicts with existing app shortcuts | Low | Allow user to rebind (Phase 2) |
| SwiftUI `NSHostingView` in `NSPanel` focus/responder chain issues | Medium | Prototype early; known issue with workarounds |

---

## References

- [NSPasteboard Documentation](https://developer.apple.com/documentation/appkit/nspasteboard)
- [CGEvent Reference](https://developer.apple.com/documentation/coregraphics/cgevent)
- [AXIsProcessTrusted](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted)
- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview)
- Carbon `RegisterEventHotKey` — available via `<Carbon/Carbon.h>` (still in macOS SDK as of macOS 15)
