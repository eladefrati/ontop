APP           := ontop
BUNDLE_ID     := io.github.eladefrati.ontop
CONFIG        ?= release
BUILD         := build
BIN           := .build/$(CONFIG)/$(APP)
APPDIR        := $(BUILD)/$(APP).app
ICON          := $(BUILD)/AppIcon.icns
# SHA-1 of the first valid Apple Development identity. A hash is unambiguous where two
# certificates share a name; override with SIGN_IDENTITY=<hash or name>.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning | awk '/Apple Development/{print $$2; exit}')

.PHONY: build app install run stop log clean

build:
	swift build -c $(CONFIG)

$(ICON): tools/make-icon.swift
	mkdir -p $(BUILD)
	rm -rf $(BUILD)/AppIcon.iconset
	swift tools/make-icon.swift $(BUILD)/AppIcon.iconset
	iconutil -c icns -o $(ICON) $(BUILD)/AppIcon.iconset

app: build $(ICON)
	rm -rf $(APPDIR)
	mkdir -p $(APPDIR)/Contents/MacOS $(APPDIR)/Contents/Resources
	cp $(BIN) $(APPDIR)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(APPDIR)/Contents/Info.plist
	cp $(ICON) $(APPDIR)/Contents/Resources/AppIcon.icns
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
	  codesign --force --options runtime --sign "$(SIGN_IDENTITY)" $(APPDIR); \
	else \
	  echo "warning: no Apple Development identity found; signing ad hoc, permission grants will reset on every rebuild" >&2; \
	  codesign --force --sign - $(APPDIR); \
	fi
	@codesign -dv $(APPDIR) 2>&1 | grep -E '^(Authority|TeamIdentifier)' || true

install: app
	rm -rf /Applications/$(APP).app
	cp -R $(APPDIR) /Applications/

run: app stop
	open $(APPDIR)

stop:
	-pkill -x $(APP)

log:
	/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "$(BUNDLE_ID)"'

clean:
	rm -rf $(BUILD) .build
