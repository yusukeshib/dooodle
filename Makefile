APP = Dooodle.app
BIN = .build/release/Dooodle

.PHONY: all build bundle run clean

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/
	cp $(BIN) $(APP)/Contents/MacOS/
	codesign --force --sign - $(APP)

run: bundle
	open $(APP)

clean:
	swift package clean
	rm -rf $(APP)
