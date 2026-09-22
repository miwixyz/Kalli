.PHONY: docs gen build run install clean check-docs release release-dry-run

APP = Kalli
CONFIG ?= Debug
DERIVED = build
DEST = /Applications/$(APP).app

# Das CHANGELOG lebt im Repo-Wurzelverzeichnis. Damit die App nie eine aeltere
# Fassung anzeigt als das Repo enthaelt, wird es bei JEDEM Build frisch
# gespiegelt -- kein Vorsatz, ein Schritt.
docs:
	cp CHANGELOG.md Kalli/Resources/CHANGELOG.md

gen: docs
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
# Reihenfolge ist wesentlich: Erst spiegeln, dann pruefen. Andersherum prueft
# das Gate gegen einen Zustand, den es selbst noch nicht hergestellt hat.
check-docs: docs
	@bash scripts/docs-gate.sh

install: check-docs build
	@pkill -x $(APP) || true
	@test -d "$(DEST)" && rm -rf "$(DEST)" || true
	cp -R $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app /Applications/
	codesign --force --deep --sign - "$(DEST)"
	open "$(DEST)"
	@echo "→ Kalli läuft jetzt aus /Applications. Autostart ist dort stabil."

# Signiertes, notarisiertes ZIP + GitHub-Release. Braucht Developer-ID-Zertifikat
# und notarytool-Profil im Schluesselbund. `make release PUBLISH=0` baut alles,
# veroeffentlicht aber nicht.
release:
	@bash scripts/release.sh

# Zeigt die Vorbedingungen, ohne etwas zu bauen.
release-dry-run:
	@echo "VERSION:        $$(awk -F'\"' '/MARKETING_VERSION:/ { print $$2; exit }' project.yml)"
	@echo "NOTARY_PROFILE: $${NOTARY_PROFILE:-tippi-notary}"
	@printf "DEVELOPER_ID:   "; security find-identity -v -p codesigning | awk -F'\"' '/Developer ID Application/ { print $$2; exit }'
	@git diff --quiet && git diff --cached --quiet && echo "Arbeitsbaum:    sauber" || echo "Arbeitsbaum:    NICHT sauber"

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj
