#!/bin/sh
# Bild-Testkopie (docs/SECURE-DESIGN.md K1): Debug-Build mit EIGENER Kennung dev.mwlr.kalli.bild, ohne
# Berechtigungen, ohne Updater, ohne Gnotchi-Verbindung, mit Befehlskanal – dazu das signierte Steuerprogramm
# build-dev/kallictl.
#
# Warum eigene Kennung: Die Bildschirmaufnahme-Freigabe hängt an Kennung + Signatur. Mit der echten Kennung
# hätte auch das veröffentlichte Kalli die Freigabe. Das echte Kalli (/Applications) läuft währenddessen
# einfach weiter und wird nicht angefasst.
#
#   sh scripts/bild-test.sh                → bauen, signieren, nach ~/Applications installieren, starten
#   build-dev/kallictl status              → Zustand (nur Zahlen/Kennungen)
#   build-dev/kallictl snapshot einstellungen|hilfe
#   build-dev/kallictl appearance light|dark|system
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
BUNDLE_ID="dev.mwlr.kalli.bild"

mkdir -p build-dev
LOG=$(mktemp "build-dev/bild-build.XXXXXX")
if ! make build DERIVED=build-dev >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -8
    echo "✗ Build fehlgeschlagen — Log: $LOG" >&2
    exit 1
fi
SRC="build-dev/Build/Products/Debug/Kalli.app"
DEST_DIR=$(mktemp -d /tmp/kalli-bild.XXXXXX)
APP="$DEST_DIR/Kalli Bild.app"
ditto "$SRC" "$APP"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Kalli Bild" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :CFBundleDisplayName" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Kalli Bild" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$PLIST"
# Kein Dienste-Menü: Sonst stünde „Als eine Sache in Kalli“ doppelt im System und könnte in der Kopie landen.
/usr/libexec/PlistBuddy -c "Delete :NSServices" "$PLIST"

IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "✗ Kein Developer-ID-Zertifikat im Schlüsselbund" >&2; exit 1; }

# Eingebettete Teile einzeln (innen nach außen), ohne eigene Berechtigungen.
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$SPK"/XPCServices/*.xpc "$SPK/Autoupdate" "$SPK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --preserve-metadata=entitlements --sign "$IDENTITY" "$part"
done
for part in "$APP"/Contents/MacOS/*.dylib; do
    [ -e "$part" ] || continue
    codesign --force --options runtime --sign "$IDENTITY" "$part"
done

# App: KEINE Berechtigungen (K1). Ohne Kalender-/Erinnerungs-Entitlement lehnt macOS unter Hardened Runtime jede
# Anfrage sofort ab – die Kopie sieht nie einen Termin. Keine Apple Events.
ENT="$DEST_DIR/KalliBild.entitlements"
cat > "$ENT" <<'PLISTEND'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
PLISTEND
codesign --force --options runtime --entitlements "$ENT" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

# Steuerprogramm: nur mit dieser Kennung + Developer ID nimmt die Kopie Befehle an.
swiftc -O tools/kallictl.swift -o build-dev/kallictl
codesign --force --options runtime -i dev.mwlr.kalli.ctl --sign "$IDENTITY" build-dev/kallictl

# Fester Ort ~/Applications statt /tmp (Gnotchi, gemessen 28.10.): Apps unter /tmp findet macOS nicht über ihre
# Kennung, die Systemeinstellungen zeigen den Schalter dann nie. Gleiche Kennung + gleiche Signatur am selben Ort
# → die Freigabe bleibt über Neubauten erhalten.
INSTALLED="$HOME/Applications/Kalli Bild.app"
# Alte Bild-Kopie beenden – nur sie, über ihre PID aus dem vollen Programmpfad. Nie nach Prozessnamen und nie per
# AppleScript: Das echte Kalli heißt genauso („Kalli“).
for pid in $(pgrep -f "^$INSTALLED/Contents/MacOS/Kalli\$" || true); do
    kill "$pid"
done
i=0
while pgrep -f "^$INSTALLED/Contents/MacOS/Kalli\$" >/dev/null && [ "$i" -lt 30 ]; do
    sleep 0.1
    i=$((i + 1))
done
mkdir -p "$HOME/Applications"
[ -d "$INSTALLED" ] && mv "$INSTALLED" "$DEST_DIR/alt.app"
ditto "$APP" "$INSTALLED"
codesign --verify --deep --strict "$INSTALLED"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED"
open "$INSTALLED"
echo "✓ Bild-Testkopie gestartet: $INSTALLED"
echo "  Erster Lauf auf einem Mac: Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme"
echo "  → „Kalli Bild“ einschalten (nicht „Kalli“), dann dieses Skript erneut starten."
echo "  Steuern: build-dev/kallictl status | snapshot einstellungen|hilfe | appearance light|dark|system"
