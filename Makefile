PREFIX ?= /usr/local
APP_DIR ?= /Applications
SWIFTFLAGS ?=
BUILD = build
APP = $(BUILD)/Scrap.app

VERSION = $(shell sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/ScrapCore/ScrapCore.swift | head -1)
DIST = $(BUILD)/dist

.PHONY: build app dist install uninstall test clean icons demo

build:
	swift build -c release $(SWIFTFLAGS)

# $(call assemble_app,<Scrap.app to make>,<the ScrapApp binary>)
define assemble_app
	rm -rf $(1)
	mkdir -p $(1)/Contents/MacOS $(1)/Contents/Resources
	cp $(2) $(1)/Contents/MacOS/ScrapApp
	cp Resources/Info.plist $(1)/Contents/Info.plist
	cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png $(1)/Contents/Resources/
	cp -R Resources/Icons $(1)/Contents/Resources/Icons
	codesign --force --sign - $(1)
endef

app: build
	$(call assemble_app,$(APP),.build/release/ScrapApp)

# The release build the Homebrew formula installs: universal (Apple silicon and Intel), packed as
# scrap-<version>-macos.tar.gz holding bin/scrap and Scrap.app. Built by CI on a tag; needs Xcode.
dist: ARCHS = --arch arm64 --arch x86_64
dist:
	swift build -c release $(ARCHS) $(SWIFTFLAGS)
	rm -rf $(DIST) && mkdir -p $(DIST)/scrap-$(VERSION)/bin
	$(call assemble_app,$(DIST)/scrap-$(VERSION)/Scrap.app,$$(swift build -c release $(ARCHS) --show-bin-path)/ScrapApp)
	cp $$(swift build -c release $(ARCHS) --show-bin-path)/scrap-cli $(DIST)/scrap-$(VERSION)/bin/scrap
	codesign --force --sign - $(DIST)/scrap-$(VERSION)/bin/scrap
	tar -C $(DIST) -czf $(DIST)/scrap-$(VERSION)-macos.tar.gz scrap-$(VERSION)
	cd $(DIST) && shasum -a 256 scrap-$(VERSION)-macos.tar.gz | tee scrap-$(VERSION)-macos.tar.gz.sha256

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

# Regenerates the README screenshots and demo GIF from the real app views (needs Pillow).
demo:
	rm -rf $(BUILD)/demo
	SCRAP_DEMO_DIR=$(CURDIR)/$(BUILD)/demo swift test --filter DemoAssetsTests
	python3 scripts/make_demo.py $(BUILD)/demo docs
