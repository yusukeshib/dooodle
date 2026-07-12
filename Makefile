APP = Dooodle.app
BIN = .build/release/Dooodle
# Stable signing identity so Accessibility (TCC) permission survives rebuilds.
# Ad-hoc signing ("-") makes macOS treat every build as a new app.
SIGN_IDENTITY ?= Apple Development: Yusuke Shibata (6F8N535B8W)

.PHONY: all build bundle run clean

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Info.plist $(APP)/Contents/
	cp $(BIN) $(APP)/Contents/MacOS/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force --sign "$(SIGN_IDENTITY)" $(APP)

run: bundle
	open $(APP)

clean:
	swift package clean
	rm -rf $(APP)
