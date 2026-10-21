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

.DEFAULT_GOAL := app
.PHONY: build app install uninstall run stop test log clean

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

# Quits a running ontop first (copying over a running bundle leaves the old code running),
# and opens the installed copy again if one was running.
install: app
	@running=$$(pgrep -x $(APP) >/dev/null && echo yes); \
	pkill -x $(APP); while pgrep -x $(APP) >/dev/null; do sleep 0.1; done; \
	rm -rf /Applications/$(APP).app && cp -R $(APPDIR) /Applications/ && \
	if [ -n "$$running" ]; then open /Applications/$(APP).app; fi

uninstall: stop
	rm -rf /Applications/$(APP).app

run: app stop
	open $(APPDIR)

stop:
	-pkill -x $(APP)

test:
	swift test

log:
	/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "$(BUNDLE_ID)"'

clean:
	rm -rf $(BUILD) .build
