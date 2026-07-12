#!/usr/bin/env bash
#
# Build a notarized, stapled Dooodle.dmg for distribution on GitHub.
#
# ── One-time setup ──────────────────────────────────────────────────────────
#
# 1. Create a "Developer ID Application" certificate (NOT "Apple Development"):
#      Xcode ▸ Settings ▸ Accounts ▸ (your Apple ID) ▸ Manage Certificates…
#      ▸ + ▸ Developer ID Application
#    Confirm it landed in your login keychain:
#      security find-identity -v -p codesigning | grep "Developer ID Application"
#
# 2. Create an app-specific password for notarization:
#      https://account.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords
#
# 3. Store notarytool credentials once as a keychain profile:
#      xcrun notarytool store-credentials dooodle-notary \
#        --apple-id "you@example.com" \
#        --team-id  "YOURTEAMID" \
#        --password "xxxx-xxxx-xxxx-xxxx"    # the app-specific password
#    (Team ID: https://developer.apple.com/account ▸ Membership details)
#
# ── Usage ───────────────────────────────────────────────────────────────────
#
#   ./Scripts/release.sh           # auto-detects the Developer ID identity
#   NOTARY_PROFILE=other ./Scripts/release.sh
#   SIGN_IDENTITY="Developer ID Application: …" ./Scripts/release.sh
#
# Then publish:
#   VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
#   gh release create "v$VERSION" Dooodle.dmg --title "v$VERSION" --generate-notes
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Dooodle.app"
DMG="Dooodle.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-dooodle-notary}"

# Auto-detect the Developer ID Application identity unless one is provided.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | awk -F'"' '/Developer ID Application/{print $2; exit}')}"

if [ -z "$SIGN_IDENTITY" ]; then
  cat >&2 <<'EOF'
error: no "Developer ID Application" certificate found in your keychain.

Notarized distribution requires a Developer ID Application certificate
(an "Apple Development" cert will NOT work). Create one via:
  Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates… ▸ + ▸ Developer ID Application
EOF
  exit 1
fi
echo "▸ Signing identity: $SIGN_IDENTITY"

# 1. Build + bundle, signed with Hardened Runtime and a secure timestamp
#    (both are required for notarization).
make bundle \
  SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODESIGN_FLAGS="--options runtime --timestamp"

echo "▸ Verifying signature…"
codesign --verify --strict --verbose=2 "$APP"

# 2. Package the app into a compressed DMG.
echo "▸ Building $DMG…"
rm -f "$DMG"
hdiutil create -volname Dooodle -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

# 3. Sign the DMG itself.
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

# 4. Submit for notarization and wait for Apple's verdict.
echo "▸ Notarizing (this can take a minute)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# 5. Staple the ticket so Gatekeeper works offline.
echo "▸ Stapling…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true

echo "✅ $DMG is notarized + stapled and ready to upload to GitHub Releases."
