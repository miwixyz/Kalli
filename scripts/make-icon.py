#!/usr/bin/env python3
"""make-icon.py — baut Kalli/Resources/AppIcon.icns aus assets/Kalli-App_Icon.png.

Warum (2026-09-29): Die bisherige AppIcon.icns zeigte in ALLEN Größen nur einen
winzigen Ausschnitt unten links, der Rest war leer. Die Vorlage selbst war gut,
nur der Weg dahin kaputt und nicht nachvollziehbar. Dieses Skript ist der Weg.

Die Vorlage ist ein JPEG (trotz .png-Endung) ohne Transparenz: Die Icon-Fläche
sitzt auf Weiß. Deshalb:
  1. Icon-Fläche ausschneiden (gemessen: x 86–937, y 85–938)
  2. Ecken per Superellipse (Exponent 5,3, gemessen an der Vorlage) durchsichtig
     machen, 2 px nach innen, damit kein weißer Saum bleibt
  3. nach Apples Raster setzen: 824 px Icon mit 100 px Rand im 1024er-Feld
  4. alle zehn Größen erzeugen, `iconutil` baut die .icns

Aufruf:  python3 scripts/make-icon.py
"""
import os
import subprocess
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "assets", "Kalli-App_Icon.png")
MASTER = os.path.join(ROOT, "assets", "Kalli-App_Icon-1024.png")
ICNS = os.path.join(ROOT, "Kalli", "Resources", "AppIcon.icns")

CROP = (86, 85, 938, 938)      # Icon-Fläche in der Vorlage (gemessen)
EXPONENT = 5.3                 # Eckenform der Vorlage (gemessen an der Diagonale)
INSET = 2                      # px nach innen gegen weißen Saum
CANVAS = 1024
ICON = 824                     # Apples Raster für macOS-App-Icons
SUPERSAMPLE = 4


def superellipse_mask(size: int) -> Image.Image:
    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    px = mask.load()
    a = (big / 2) - INSET * SUPERSAMPLE
    c = big / 2
    for y in range(big):
        dy = abs((y + 0.5 - c) / a)
        if dy >= 1:
            continue
        # |x|^n + |y|^n <= 1  →  |x| <= (1 - |y|^n)^(1/n)
        half = a * (1 - dy ** EXPONENT) ** (1 / EXPONENT)
        x0 = int(round(c - half))
        x1 = int(round(c + half))
        for x in range(max(0, x0), min(big, x1)):
            px[x, y] = 255
    return mask.resize((size, size), Image.LANCZOS)


def main() -> None:
    art = Image.open(SOURCE).convert("RGB").crop(CROP)
    side = min(art.size)
    art = art.resize((side, side), Image.LANCZOS).convert("RGBA")
    art.putalpha(superellipse_mask(side))

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
