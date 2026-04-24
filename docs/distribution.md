# Recall — Distribution Guide

## Current status

Recall is distributed as an **ad-hoc signed** build. Users must bypass Gatekeeper once on first launch (see [User instructions](#user-instructions-for-ad-hoc-builds) below). Full notarization requires a paid Apple Developer Program membership ($99/year); the script supports it when a Developer ID cert is available.

---

## Building a release

```bash
./scripts/distribute.sh
```

Output: `build/dist/Recall-0.1.0.dmg`

The script:
1. Builds a universal (x86_64 + arm64) Release binary
2. Re-signs with clean entitlements (strips the debug `get-task-allow` entitlement Xcode injects)
3. Verifies the signature with `codesign --verify --deep --strict`
4. Creates a compressed `.dmg` with an `/Applications` symlink

---

## User instructions for ad-hoc builds

Include these with any download:

**Option A — Right-click open (easiest):**
1. Open the `.dmg` and drag Recall to Applications
2. In Finder, right-click `Recall.app` → **Open**
3. Click **Open** in the dialog that appears
4. Recall will launch normally from now on

**Option B — Terminal (one command):**
```bash
xattr -dr com.apple.quarantine /Applications/Recall.app
```

---

## Entitlements

`Recall/Recall.entitlements` is intentionally empty. Recall does not require any special Hardened Runtime exceptions because:

- **Clipboard access** — `NSPasteboard` requires no entitlement
- **Synthetic key events** (`CGEventPost`) — requires Accessibility runtime permission (user-granted), not an entitlement
- **Accessibility API** (`AXIsProcessTrusted`) — runtime permission, no entitlement
- **Carbon global hotkeys** (`RegisterEventHotKey`) — no entitlement required
- **No third-party libraries** — `com.apple.security.cs.disable-library-validation` is not needed

---

## Upgrading to full notarization (when ready)

### Prerequisites

1. Enroll in the [Apple Developer Program](https://developer.apple.com/enroll/) ($99/year)
2. After approval (~24h), open **Xcode → Settings → Accounts**, select your team, click **Manage Certificates → + → Developer ID Application**
3. Create an [app-specific password](https://appleid.apple.com) for notarytool
4. Find your Team ID: `security find-identity -v -p codesigning` — it's the alphanumeric in parentheses

### Update project.yml

Set your team in `project.yml`:
```yaml
DEVELOPMENT_TEAM: "YOUR_TEAM_ID"
```

Regenerate the Xcode project:
```bash
xcodegen generate
```

### Run notarized build

```bash
TEAM_ID=XXXXXXXXXX \
APPLE_ID=you@example.com \
APP_PASSWORD=xxxx-xxxx-xxxx-xxxx \
./scripts/distribute.sh --notarize
```

The script will build, sign with Developer ID, submit to Apple's notary service, wait for approval, staple the ticket to the DMG, and verify Gatekeeper acceptance.

### What changes with notarization

- No Gatekeeper warning on download
- `spctl --assess` passes
- Notarization ticket is stapled — works offline
- `codesign -dv` shows `TeamIdentifier: YOUR_TEAM_ID` instead of `not set`

---

## Versioning

Version is set in `project.yml` under `MARKETING_VERSION`. Bump it before each release:

```yaml
MARKETING_VERSION: "0.2.0"
```

Then regenerate and rebuild:
```bash
xcodegen generate
./scripts/distribute.sh
```
