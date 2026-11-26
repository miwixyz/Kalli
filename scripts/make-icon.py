#!/usr/bin/env python3
"""make-icon.py — baut Kalli/Resources/AppIcon.icns aus assets/Kalli-App_Icon-quelle.png.

Ab 2026-11-26 ist die Vorlage das freigestellte Kalli-Maskottchen der App-Familie
(Vault: 07 Anhänge/Brand-Characters/familie/freigestellt/kalli.png). Geometrie wie
bei Tippi, TippAI und Seam: Squircle 1000 × 1000 im 1024er-Feld, 12 px Rand,
transparente Ecken.

Die Vorlage (1649 × 1664, RGBA) trägt unten einen grauen Schattensaum, der nicht
zum Symbol gehört. Deshalb:
  1. Squircle ausschneiden (gemessen: x 3–1646, y 0–1638; darunter beginnt der Saum)
  2. Maske = eigene Transparenz ∩ ihr vertikales Spiegelbild. Die obere Kante ist
     sauber, gespiegelt schneidet sie die untere Kante samt Saumresten in Form.
  3. auf 1000 × 1000 skalieren, mit 12 px Rand ins 1024er-Feld setzen
  4. alle zehn Größen erzeugen, `iconutil` baut die .icns

Die alte Vorlage (Glas-JPEG bis 0.18.0) liegt in design/Kalli-App_Icon-alt.jpg.

Aufruf:  python3 scripts/make-icon.py   (braucht Pillow)
"""
import os
import subprocess
import tempfile

from PIL import Image, ImageChops, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "assets", "Kalli-App_Icon-quelle.png")
MASTER = os.path.join(ROOT, "assets", "Kalli-App_Icon-1024.png")
ICNS = os.path.join(ROOT, "Kalli", "Resources", "AppIcon.icns")

CROP = (3, 0, 1647, 1639)      # Squircle ohne Schattensaum (gemessen, Ende exklusiv)
CANVAS = 1024
ICON = 1000                    # wie Tippi: 12 px Rand


def main() -> None:
    art = Image.open(SOURCE).convert("RGBA").crop(CROP)
    alpha = art.getchannel("A")
    art.putalpha(ImageChops.darker(alpha, ImageOps.flip(alpha)))

    icon = art.resize((ICON, ICON), Image.LANCZOS)
    master = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    offset = (CANVAS - ICON) // 2
    master.paste(icon, (offset, offset), icon)
    master.save(MASTER)

    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.mkdir(iconset)
        for base in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = base * scale
                name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
                master.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
        # Voller Pfad statt PATH-Suche (rafter R-E617E, 2026-09-29).
        subprocess.run(["/usr/bin/iconutil", "-c", "icns", iconset, "-o", ICNS], check=True)
    print(f"✓ {os.path.relpath(MASTER, ROOT)} und {os.path.relpath(ICNS, ROOT)} erzeugt")


if __name__ == "__main__":
    main()
