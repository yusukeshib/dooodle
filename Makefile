APP = Dooodle.app
BIN = .build/release/Dooodle
# Stable signing identity so Accessibility (TCC) permission survives rebuilds.
# Ad-hoc signing ("-") makes macOS treat every build as a new app.
SIGN_IDENTITY ?= Apple Development: Yusuke Shibata (6F8N535B8W)
# Extra codesign flags. Distribution/notarization builds set
# CODESIGN_FLAGS="--options runtime --timestamp" (see Scripts/release.sh).
CODESIGN_FLAGS ?=

.PHONY: all build bundle run clean release

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Info.plist $(APP)/Contents/
	cp $(BIN) $(APP)/Contents/MacOS/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force $(CODESIGN_FLAGS) --sign "$(SIGN_IDENTITY)" $(APP)

run: bundle
	open $(APP)

# Build a notarized, stapled Dooodle.dmg for GitHub distribution.
release:
	./Scripts/release.sh

clean:
	swift package clean
	rm -rf $(APP) Dooodle.dmg
