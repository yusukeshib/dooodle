# dooodle

[![CI](https://github.com/yusukeshib/dooodle/actions/workflows/ci.yml/badge.svg)](https://github.com/yusukeshib/dooodle/actions/workflows/ci.yml)

Hold a key, scribble on your screen, let go.

dooodle is a macOS menu bar app that shows a transparent drawing overlay
above all windows **while you hold a trigger key** (Fn by default). Release
the key and the overlay vanishes instantly; press it again and your strokes
pop right back.

The three o's are the doodles. 〰️

## Install

macOS 13+. [**Download Dooodle.dmg**](https://github.com/yusukeshib/dooodle/releases/latest/download/Dooodle.dmg),
open it, and drag Dooodle to Applications.

## Usage

1. Hold **Fn** (or your chosen trigger key)
2. Draw with the mouse / trackpad
3. Release — the overlay disappears; your strokes are saved
4. Use the ✏️ menu bar icon to change thickness, color, or the trigger key

## Releasing

dooodle uses the Accessibility API for global trigger-key monitoring, which the
Mac App Store sandbox forbids — so it's distributed directly on GitHub as a
notarized DMG instead.

One-time setup and the full pipeline live in
[`Scripts/release.sh`](Scripts/release.sh) (Developer ID certificate +
`notarytool` keychain profile). Once set up:

```sh
make release                 # build → sign (Hardened Runtime) → notarize → staple

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
gh release create "v$VERSION" Dooodle.dmg --title "v$VERSION" --generate-notes
```
