# dooodle

[![CI](https://github.com/yusukeshib/dooodle/actions/workflows/ci.yml/badge.svg)](https://github.com/yusukeshib/dooodle/actions/workflows/ci.yml)

Hold a key, scribble on your screen, let go.

dooodle is a macOS menu bar app that shows a transparent drawing overlay
above all windows **while you hold a trigger key** (Fn by default). Release
the key and the overlay vanishes instantly; press it again and your strokes
pop right back.

The three o's are the doodles. 〰️

## Features

- **Hold-to-draw** — overlay appears only while the trigger key is held
- **Customizable trigger key** — Fn, Right ⌘, Right ⌥, Right ⌃, or Left ⌃
  (handy if you mouse with your left hand)
- **5 pen thicknesses / 5 colors** from the menu bar
- **Every stroke and vertex is timestamped** and persisted to SQLite,
  so you can query your doodling history later
- **Clear Canvas** hides strokes but keeps them in the database
  (`cleared_at` is set instead of deleting rows)
- **Launch at Login** toggle
- No Dock icon — lives entirely in the menu bar

## Install

Requires macOS 13+.

**Download the notarized build** from the
[Releases page](https://github.com/yusukeshib/dooodle/releases): open
`Dooodle.dmg` and drag Dooodle to Applications. The build is signed with a
Developer ID and notarized by Apple, so Gatekeeper opens it without warnings.

### Build from source

Requires Xcode command line tools.

```sh
git clone https://github.com/yusukeshib/dooodle
cd dooodle
make bundle SIGN_IDENTITY=-   # or set your own signing identity
open Dooodle.app
```

> [!NOTE]
> Signing with a **stable identity** (an Apple Development certificate)
> is strongly recommended. Ad-hoc signing (`SIGN_IDENTITY=-`) works, but
> macOS treats every rebuild as a new app and re-asks for the
> Accessibility permission each time.

### Accessibility permission

Monitoring the trigger key globally requires the Accessibility permission:

1. Launch the app — a permission prompt appears
2. Enable Dooodle in **System Settings › Privacy & Security › Accessibility**
3. Relaunch the app (the permission is only picked up at launch)

## Usage

1. Hold **Fn** (or your chosen trigger key)
2. Draw with the mouse / trackpad
3. Release — the overlay disappears; your strokes are saved
4. Use the ✏️ menu bar icon to change thickness, color, or the trigger key

## Data

Strokes are stored in
`~/Library/Application Support/Dooodle/dooodle.sqlite`:

```sql
strokes  (id, started_at, color, width, cleared_at)
vertices (stroke_id, seq, x, y, t)   -- t = unix epoch seconds per point
```

Example — strokes per day:

```sh
sqlite3 ~/Library/Application\ Support/Dooodle/dooodle.sqlite \
  "SELECT date(started_at,'unixepoch','localtime') AS day, count(*)
   FROM strokes GROUP BY day ORDER BY day"
```

Example — drawing speed of a stroke (points per second):

```sh
sqlite3 ~/Library/Application\ Support/Dooodle/dooodle.sqlite \
  "SELECT stroke_id, count(*) / (max(t) - min(t)) AS pts_per_sec
   FROM vertices GROUP BY stroke_id HAVING count(*) > 1"
```

## Development

```sh
make build    # swift build -c release
make bundle   # build + assemble + codesign Dooodle.app
make run      # bundle + open
make clean
```

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
