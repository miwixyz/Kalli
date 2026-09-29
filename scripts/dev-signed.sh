#!/bin/sh
# dev-signed.sh — Testversion bauen, mit Developer ID signieren und starten.
#
# Warum (2026-09-29): Ein ad-hoc signierter Build verliert die Kalender-
# Berechtigung (TCC bindet sie an die Signatur). Mit Developer ID bleibt sie.
# ABER: Ein so signiertes App-Paket schützt macOS danach vor Änderungen —
# jeder weitere Build in denselben Ordner scheiterte mit „Operation not
# permitted“, und gestartet wurde still ein alter Stand. Deshalb baut Xcode in
# `build-dev/`, und signiert wird immer eine frische KOPIE unter /tmp.
# `build-test/Kalli.app` zeigt als Verweis auf die neueste Kopie.
#
# Aufruf:
#   ./scripts/dev-signed.sh                  # bauen, signieren, starten
#   ./scripts/dev-signed.sh -vollbildDemo    # dazu sofort den Vollbild-Hinweis zeigen
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

LOG=/tmp/kalli-dev-build.log
if ! make build DERIVED=build-dev >"$LOG" 2>&1; then
    grep -E '^error|error:' "$LOG" | sort -u | head -5
    echo "✗ Build fehlgeschlagen — Log: $LOG" >&2
    exit 1
fi

SRC="build-dev/Build/Products/Debug/Kalli.app"
DEST_DIR=$(mktemp -d /tmp/kalli-test.XXXXXX)
ditto "$SRC" "$DEST_DIR/Kalli.app"

IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "✗ Kein Developer-ID-Zertifikat im Schlüsselbund" >&2; exit 1; }
codesign --force --deep --options runtime \
    --entitlements Kalli/Resources/Kalli.entitlements \
    --sign "$IDENTITY" "$DEST_DIR/Kalli.app"

mkdir -p build-test
ln -sfn "$DEST_DIR/Kalli.app" build-test/Kalli.app

pkill -x Kalli || true
sleep 1   # sonst übernimmt `open` womöglich die noch endende Instanz
open "$DEST_DIR/Kalli.app" --args "$@"
echo "✓ Testversion gestartet: $DEST_DIR/Kalli.app"
