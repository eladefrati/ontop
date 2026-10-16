APP           := ontop
BUNDLE_ID     := io.github.eladefrati.ontop
CONFIG        ?= release
BUILD         := build
BIN           := .build/$(CONFIG)/$(APP)
APPDIR        := $(BUILD)/$(APP).app
# First Apple Development identity in the keychain; override with SIGN_IDENTITY=... if needed.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $$2; exit}')

.PHONY: build app install run stop log clean

build:
	swift build -c $(CONFIG)

app: build
	rm -rf $(APPDIR)
	mkdir -p $(APPDIR)/Contents/MacOS $(APPDIR)/Contents/Resources
	cp $(BIN) $(APPDIR)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(APPDIR)/Contents/Info.plist
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
