.PHONY: gen build run install clean

APP = MacCal
CONFIG ?= Debug
DERIVED = build
DEST = /Applications/$(APP).app

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) \
		-configuration $(CONFIG) -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build

# Entwicklungslauf aus dem build-Ordner. Autostart funktioniert hier NICHT
# zuverlässig — dafür `make install`.
run: build
	@pkill -x $(APP) || true
	codesign --force --deep --sign - $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app
	open $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app

# Autostart (SMAppService) verlangt einen festen Ort und eine stabile Signatur.
# Aus dem build-Ordner heraus vergisst macOS die Registrierung beim nächsten Build.
install: build
	@pkill -x $(APP) || true
	@test -d "$(DEST)" && rm -rf "$(DEST)" || true
	cp -R $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app /Applications/
	codesign --force --deep --sign - "$(DEST)"
	open "$(DEST)"
	@echo "→ MacCal läuft jetzt aus /Applications. Autostart ist dort stabil."

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj
