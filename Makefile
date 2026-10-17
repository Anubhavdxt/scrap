PREFIX ?= /usr/local
APP_DIR ?= /Applications
BUILD = build
APP = $(BUILD)/Scrap.app

.PHONY: build app install uninstall test clean

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/ScrapApp $(APP)/Contents/MacOS/ScrapApp
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

install: app
	rm -rf $(APP_DIR)/Scrap.app
	cp -R $(APP) $(APP_DIR)/Scrap.app
	install -d $(PREFIX)/bin
	install .build/release/scrap-cli $(PREFIX)/bin/scrap

uninstall:
	rm -rf $(APP_DIR)/Scrap.app $(PREFIX)/bin/scrap

test:
	swift test

clean:
	rm -rf .build $(BUILD)
