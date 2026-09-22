#!/usr/bin/env bash
# release.sh — signiertes, notarisiertes Kalli-ZIP und GitHub-Release.
#
# Warum es das gibt (2026-09-22):
#
# Kalli lief bis dahin nur über `make install` — ad-hoc signiert. Das hat zwei
# Folgen, die erst im Zwei-Mac-Betrieb weh tun:
#
#   1. **TCC bindet die Kalender-Berechtigung an die Code-Signatur.** Ad-hoc
#      signiert bei jedem Build anders, also fragt macOS immer wieder neu. Mit
#      einer stabilen Developer-ID-Signatur fragt es einmal — auf jedem Mac.
#   2. Der zweite Mac bräuchte volles Xcode, nur um eine App zu installieren.
#
# Bewusst **kein Sparkle und kein Appcast**: Kalli liegt in einem privaten
# Repo, ein öffentlicher Appcast geht damit nicht (entschieden 2026-09-21).
# Ein Release-Asset geht trotzdem — `gh release download` läuft mit der
# Anmeldung des Besitzers.
#
# Bewusst **ZIP statt DMG**: Ein DMG lohnt sich, wenn ein Installationsfenster
# mit Hintergrundbild etwas erklären muss. Hier zieht einer eine App nach
# /Applications.
#
# Aufruf:
#   make release                 # bauen, notarisieren, veröffentlichen
#   make release PUBLISH=0       # alles außer dem GitHub-Release
#
# Voraussetzungen (beide auf dem Mac, der released):
#   - Developer-ID-Zertifikat im Schlüsselbund
#   - notarytool-Profil im Schlüsselbund. Gesucht wird in dieser Reihenfolge:
#     kalli-notary, notary, tippi-notary. Eigenes: NOTARY_PROFILE=... make release
#     Neu anlegen:    xcrun notarytool store-credentials

set -euo pipefail
cd "$(dirname "$0")/.."

APP="Kalli"
BUNDLE="${APP}.app"
DIST="dist"
PUBLISH="${PUBLISH:-1}"
# Bevorzugt ein projekteigenes Profil; faellt auf ein vorhandenes zurueck, damit
# dieses oeffentliche Script keinen fremden Projektnamen als Pflichtwert vorgibt.
# Welches genommen wurde, wird gemeldet — ein stiller Rueckfall waere eine
# Ueberraschung beim Debuggen.
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# release.env ist optional und enthält keine Geheimnisse — nur den Namen des
# Zertifikats und des Schlüsselbund-Profils. Die Zugangsdaten selbst liegen im
# Schlüsselbund, nicht in einer Datei.
[ -f release.env ] && . ./release.env

fail() { echo "✗ $*" >&2; exit 1; }
step() { echo ""; echo "▶ $*"; }

# ---------------------------------------------------------------------------
# 0. Vorbedingungen. Alle messen, keine annehmen.
# ---------------------------------------------------------------------------
step "[0/8] Vorbedingungen"

command -v gh >/dev/null || fail "gh fehlt — brew install gh"
command -v xcodegen >/dev/null || fail "xcodegen fehlt — brew install xcodegen"

# Ein Release aus einem verschmutzten Baum ist nicht reproduzierbar: Das
# Artefakt enthält Änderungen, die in keinem Commit stehen.
git diff --quiet && git diff --cached --quiet \
    || fail "Arbeitsbaum ist nicht sauber. Erst committen, dann releasen."

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
[ -n "${VERSION}" ] || fail "MARKETING_VERSION nicht in project.yml gefunden"
TAG="v${VERSION}"

git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null \
    && fail "Tag ${TAG} existiert schon. Version in project.yml anheben."

grep -q "\[${VERSION}\]" CHANGELOG.md \
    || fail "CHANGELOG hat keinen Abschnitt [${VERSION}]"

# Das Zertifikat wird GEPRÜFT, nicht vorausgesetzt. Ohne diese Zeile fällt der
# Fehler erst nach dem Archivieren auf — oder gar nicht, weil xcodebuild
# stillschweigend ad-hoc signiert und das Ergebnis erst auf dem anderen Mac
# scheitert.
DEVELOPER_ID="${DEVELOPER_ID:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
[ -n "${DEVELOPER_ID}" ] || fail "Kein 'Developer ID Application'-Zertifikat im Schlüsselbund"

if [ -n "${NOTARY_PROFILE}" ]; then
    xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 \
        || fail "notarytool-Profil '${NOTARY_PROFILE}' antwortet nicht. Anlegen: xcrun notarytool store-credentials"
else
    for candidate in kalli-notary notary tippi-notary; do
        if xcrun notarytool history --keychain-profile "${candidate}" >/dev/null 2>&1; then
            NOTARY_PROFILE="${candidate}"
            break
        fi
    done
    [ -n "${NOTARY_PROFILE}" ] || fail "Kein notarytool-Profil gefunden (gesucht: kalli-notary, notary, tippi-notary). Anlegen: xcrun notarytool store-credentials, oder NOTARY_PROFILE=... setzen"
fi

echo "  ✓ Version ${VERSION} · Tag ${TAG} frei · Baum sauber"
echo "  ✓ Zertifikat: ${DEVELOPER_ID}"
echo "  ✓ notarytool-Profil: ${NOTARY_PROFILE}"

# ---------------------------------------------------------------------------
# 1. Doku-Gate — derselbe Prüfer wie bei `make install`
# ---------------------------------------------------------------------------
step "[1/8] Doku-Gate"
bash scripts/docs-gate.sh

# ---------------------------------------------------------------------------
# 2. Bauen: archive + exportArchive, NICHT `build`
# ---------------------------------------------------------------------------
# Lehre aus Tippi v2.3.0: Manuelles Signieren ohne Profil-Angabe bettet gar
# kein Provisioning-Profil ein. Das bleibt unsichtbar, solange die App keine
# Entitlements hat — sobald doch, killt amfid sie beim Start mit -413 "No
# matching profile found". Der Export-Pfad lässt Xcode das
# "Mac Team Direct"-Profil holen, das auf jedem Mac gilt statt nur auf
# registrierten.
#
# Kallis Entitlements-Datei ist heute leer (bewusst ohne Sandbox), das Risiko
# also gering. Der richtige Weg kostet hier aber nichts und trägt, sobald
# jemand eine Berechtigung ergänzt.
BUILD_NUMBER="$(git rev-list --count HEAD)"
step "[2/8] Release-Build, Hardened Runtime (Build ${BUILD_NUMBER})"

rm -rf build/Kalli.xcarchive build/export "${DIST}"
mkdir -p "${DIST}"
make docs >/dev/null
xcodegen generate >/dev/null

xcodebuild \
    -project "${APP}.xcodeproj" \
    -scheme "${APP}" \
    -configuration Release \
    -derivedDataPath ./build \
    -archivePath "./build/${APP}.xcarchive" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    -allowProvisioningUpdates \
    archive >/dev/null

xcodebuild -exportArchive \
    -archivePath "./build/${APP}.xcarchive" \
    -exportPath ./build/export \
    -exportOptionsPlist scripts/exportOptions-developer-id.plist \
    -allowProvisioningUpdates >/dev/null

APP_PATH="build/export/${BUNDLE}"
[ -d "${APP_PATH}" ] || fail "Export hat kein ${BUNDLE} erzeugt"

# ---------------------------------------------------------------------------
# 3. Signatur prüfen — messen, nicht glauben
# ---------------------------------------------------------------------------
step "[3/8] Signatur prüfen"
SIGN_INFO="$(codesign -dv --verbose=4 "${APP_PATH}" 2>&1)"
echo "${SIGN_INFO}" | grep -q "Authority=Developer ID Application" \
    || fail "Nicht mit Developer ID signiert. Ein ad-hoc signiertes Release würde auf dem anderen Mac scheitern."
echo "${SIGN_INFO}" | grep -q "flags=.*runtime" \
    || fail "Hardened Runtime fehlt — Apple würde die Notarisierung ablehnen"
echo "  ✓ Developer ID + Hardened Runtime bestätigt"

# ---------------------------------------------------------------------------
# 4. Notarisieren
# ---------------------------------------------------------------------------
# Notarisiert wird ein ZIP, geheftet wird an die .app: Ein Ticket lässt sich
# nicht an ein ZIP heften. Deshalb zweimal packen — einmal zum Einreichen,
# einmal danach mit Ticket.
step "[4/8] Bei Apple einreichen (dauert meist 1–3 Minuten)"
ditto -c -k --keepParent "${APP_PATH}" "${DIST}/notarize.zip"

xcrun notarytool submit "${DIST}/notarize.zip" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait \
    --output-format json > "${DIST}/notarization.json"

STATUS="$(/usr/bin/plutil -extract status raw -o - "${DIST}/notarization.json")"
if [ "${STATUS}" != "Accepted" ]; then
    cat "${DIST}/notarization.json"
    fail "Notarisierung: ${STATUS}"
fi
echo "  ✓ Notarisierung angenommen"

# ---------------------------------------------------------------------------
# 5. Ticket anheften und unabhängig gegenprüfen
# ---------------------------------------------------------------------------
step "[5/8] Ticket anheften"
xcrun stapler staple "${APP_PATH}" >/dev/null
xcrun stapler validate "${APP_PATH}" >/dev/null || fail "Ticket ist nicht angeheftet"

# spctl urteilt so, wie Gatekeeper es auf dem anderen Mac tun wird. Das ist die
# eigentliche Prüfung — alles davor ist die eigene Behauptung.
SPCTL="$(spctl --assess --type execute -vv "${APP_PATH}" 2>&1 || true)"
echo "${SPCTL}" | grep -q "accepted" \
    || { echo "${SPCTL}"; fail "Gatekeeper lehnt die App ab"; }
echo "  ✓ Gatekeeper akzeptiert (source: $(echo "${SPCTL}" | awk -F'=' '/source/ { print $2 }'))"

# ---------------------------------------------------------------------------
# 6. Endgültiges ZIP
# ---------------------------------------------------------------------------
step "[6/8] ZIP packen und ALS AUSGELIEFERTES ARTEFAKT pruefen"
ZIP="${DIST}/${APP}-${VERSION}.zip"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP}"
rm -f "${DIST}/notarize.zip"
echo "  ✓ ${ZIP} ($(du -h "${ZIP}" | cut -f1))"

# Der Schritt davor prueft den Build VOR dem Packen — das ist die eigene
# Behauptung. Was zaehlt, ist das ZIP, das der andere Mac laedt: auspacken und
# Gatekeeper noch einmal fragen.
#
# Warum das hier steht (2026-09-22): Der erste Lauf meldete "Gatekeeper
# akzeptiert" und das heruntergeladene Bundle wurde trotzdem abgelehnt —
# "a sealed resource is missing or invalid". Ursache war nicht das Artefakt,
# sondern die Entpack-Methode in der Anleitung (`unzip` statt `ditto`).
# Ein Gate, das eine Stufe vor der Auslieferung prueft, findet das nie.
VERIFY_DIR="$(mktemp -d)"
ditto -x -k "${ZIP}" "${VERIFY_DIR}/"
[ -d "${VERIFY_DIR}/${BUNDLE}" ] || fail "Das ZIP enthaelt kein ${BUNDLE}"
xcrun stapler validate "${VERIFY_DIR}/${BUNDLE}" >/dev/null \
    || fail "Im ausgelieferten ZIP ist kein Notarisierungs-Ticket angeheftet"
SHIPPED="$(spctl --assess --type execute -vv "${VERIFY_DIR}/${BUNDLE}" 2>&1 || true)"
echo "${SHIPPED}" | grep -q "accepted" \
    || { echo "${SHIPPED}"; fail "Gatekeeper lehnt das ausgelieferte ZIP ab"; }
rm -rf "${VERIFY_DIR}"
echo "  ✓ Ausgeliefertes ZIP: $(echo "${SHIPPED}" | awk -F'=' '/source/ { print $2 }')"

if [ "${PUBLISH}" -eq 0 ]; then
    echo ""
    echo "🛑 PUBLISH=0 — kein GitHub-Release. Artefakt liegt in ${ZIP}"
    exit 0
fi

# ---------------------------------------------------------------------------
# 7. GitHub-Release
# ---------------------------------------------------------------------------
step "[7/8] GitHub-Release ${TAG}"
# Release-Notizen aus dem CHANGELOG-Abschnitt dieser Version — eine Quelle,
# nicht zwei, die auseinanderlaufen.
awk -v v="[${VERSION}]" '
    $0 ~ "^## \\" v { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md > "${DIST}/notes.md"
[ -s "${DIST}/notes.md" ] || fail "Keine Release-Notizen für ${VERSION} aus dem CHANGELOG gelesen"

git tag -a "${TAG}" -m "${APP} ${VERSION}"
git push origin "${TAG}"
gh release create "${TAG}" "${ZIP}" \
    --title "${APP} ${VERSION}" \
    --notes-file "${DIST}/notes.md"

# ---------------------------------------------------------------------------
# 8. Am Remote gegenprüfen, nicht lokal
# ---------------------------------------------------------------------------
# Ein lokal erfolgreicher Ablauf sagt nichts darüber, was tatsächlich
# veröffentlicht ist. Gefragt wird deshalb GitHub.
step "[8/8] Veröffentlichung am Remote prüfen"
ASSET="$(gh release view "${TAG}" --json assets --jq '.assets[].name' 2>/dev/null || true)"
[ -n "${ASSET}" ] || fail "Release ${TAG} hat auf GitHub kein Asset"
echo "  ✓ ${TAG} veröffentlicht, Asset: ${ASSET}"

echo ""
echo "✅ ${APP} ${VERSION} released."
echo ""
echo "→ ZU TUN auf dem anderen Mac:"
echo "     gh release download ${TAG} --repo miwixyz/Kalli --pattern '*.zip'"
echo "     ditto -x -k ${APP}-${VERSION}.zip . && mv ${BUNDLE} /Applications/ && open /Applications/${BUNDLE}"
echo ""
echo "   WICHTIG: ditto, nicht unzip. unzip zerstoert die Bundle-Metadaten"
echo "   eines signierten .app — Gatekeeper meldet dann 'a sealed resource is"
echo "   missing or invalid' und die App sieht beschaedigt aus."
echo ""
echo "   Kein Xcode nötig. macOS fragt dort einmal nach Kalender- und"
echo "   Erinnerungszugriff — danach nicht mehr, weil die Signatur stabil bleibt."
