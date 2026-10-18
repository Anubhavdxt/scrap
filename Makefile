PREFIX ?= /usr/local
APP_DIR ?= /Applications
SWIFTFLAGS ?=
BUILD = build
APP = $(BUILD)/Scrap.app

.PHONY: build app install uninstall test clean icons

build:
	swift build -c release $(SWIFTFLAGS)

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/ScrapApp $(APP)/Contents/MacOS/ScrapApp
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	mkdir -p $(APP)/Contents/Resources
	cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png $(APP)/Contents/Resources/
	cp -R Resources/Icons $(APP)/Contents/Resources/Icons
	codesign --force --sign - $(APP)

install: app
	rm -rf $(APP_DIR)/Scrap.app
	cp -R $(APP) $(APP_DIR)/Scrap.app
	install -d $(PREFIX)/bin
	install .build/release/scrap-cli $(PREFIX)/bin/scrap

uninstall:
	rm -rf $(APP_DIR)/Scrap.app $(PREFIX)/bin/scrap

# Regenerates the logo assets from scripts/make_icon.swift.
icons:
	rm -rf $(BUILD)/icons && mkdir -p $(BUILD)/icons
	swift scripts/make_icon.swift $(BUILD)/icons
	iconutil -c icns $(BUILD)/icons/AppIcon.iconset -o Resources/AppIcon.icns
	cp $(BUILD)/icons/MenuBarIcon.png $(BUILD)/icons/MenuBarIcon@2x.png Resources/
	mkdir -p Resources/Icons && cp $(BUILD)/icons/Icons/*.png Resources/Icons/
	cp $(BUILD)/icons/logo.png $(BUILD)/icons/social-preview.png docs/

test:
	swift test

clean:
	rm -rf .build $(BUILD)
