#!/usr/bin/env python3
"""Turn the chosen logo SVG into the app icons both targets ship.

The source art draws its own rounded square. iOS masks corners itself and
wants full bleed, macOS wants the rounded shape with Apple's own margin, so
the container is dropped here and rebuilt per platform.
"""
import re
import subprocess
import sys
from pathlib import Path

SOURCE = Path.home() / "Documents/Claude-Ciktilari/2026-08-22-dsh-studio-logo/direction-24-continuous.svg"
REPO = Path(__file__).resolve().parent.parent
IOS_ICON = REPO / "Sources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
MAC_ICONSET = REPO / "Resources/AppIcon.iconset"
MAC_ICNS = REPO / "Resources/AppIcon.icns"
WIN_ICO = REPO.parent / "DshStudioWin/src/Assets/AppIcon.ico"
WIN_PNG = REPO.parent / "DshStudioWin/src/Assets/AppIcon.png"
WIN_MARK = REPO.parent / "DshStudioWin/src/Assets/LogoMark.png"
MARK_IMAGESET = REPO / "Sources/Assets.xcassets/LogoMark.imageset"
MARK_BASE = 64

INK = "#111113"
PAPER = "#FFFFFF"
GLYPH_FRACTION_IOS = 0.60
GLYPH_FRACTION_MAC = 0.62
MAC_PLATE_FRACTION = 0.80
MAC_CORNER_FRACTION = 0.225
WIN_PLATE_FRACTION = 0.94
WIN_CORNER_FRACTION = 0.16
WIN_SIZES = (16, 24, 32, 48, 64, 128, 256)


def glyph_only_svg() -> str:
    text = SOURCE.read_text()
    paths = re.findall(r"<path[^>]*>(?:</path>)?", text)
    if len(paths) < 4:
        sys.exit(f"expected 4 paths in the source art, found {len(paths)}")
    glyph = "".join(paths[2:])
    glyph = glyph.replace("rgb(254,254,254)", PAPER).replace("rgb(30,31,39)", INK)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2048 2048" '
        f'width="2048" height="2048">{glyph}</svg>'
    )


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def main() -> int:
    work = Path("/tmp/dsh-icon")
    work.mkdir(exist_ok=True)
    raw = work / "glyph.svg"
    raw.write_text(glyph_only_svg())

    trimmed = work / "glyph.png"
    run("magick", "-background", "none", str(raw), "-trim", "+repage", str(trimmed))

    IOS_ICON.parent.mkdir(parents=True, exist_ok=True)
    side = 1024
    run(
        "magick", str(trimmed),
        "-resize", f"{int(side * GLYPH_FRACTION_IOS)}x{int(side * GLYPH_FRACTION_IOS)}",
        "-background", INK, "-gravity", "center", "-extent", f"{side}x{side}",
        "-alpha", "remove", "-alpha", "off", str(IOS_ICON),
    )

    def plated(name: str, plate_fraction: float, corner_fraction: float, glyph_fraction: float) -> Path:
        plate = work / f"plate-{name}.png"
        plate_side = int(side * plate_fraction)
        radius = int(plate_side * corner_fraction)
        run(
            "magick", "-size", f"{plate_side}x{plate_side}", "xc:none",
            "-fill", INK, "-draw",
            f"roundrectangle 0,0,{plate_side - 1},{plate_side - 1},{radius},{radius}",
            str(plate),
        )
        master = work / f"{name}.png"
        glyph_side = int(plate_side * glyph_fraction)
        run(
            "magick", str(plate),
            "(", str(trimmed), "-resize", f"{glyph_side}x{glyph_side}", ")",
            "-gravity", "center", "-composite",
            "-background", "none", "-gravity", "center", "-extent", f"{side}x{side}",
            str(master),
        )
        return master

    mac_master = plated("mac", MAC_PLATE_FRACTION, MAC_CORNER_FRACTION, GLYPH_FRACTION_MAC)

    MAC_ICONSET.mkdir(parents=True, exist_ok=True)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        run("magick", str(mac_master), "-resize", f"{size}x{size}",
            str(MAC_ICONSET / f"icon_{size}x{size}.png"))
    for base in (16, 32, 128, 256, 512):
        source = MAC_ICONSET / f"icon_{base * 2}x{base * 2}.png"
        (MAC_ICONSET / f"icon_{base}x{base}@2x.png").write_bytes(source.read_bytes())
    for size in (64, 1024):
        (MAC_ICONSET / f"icon_{size}x{size}.png").unlink()
    run("iconutil", "-c", "icns", str(MAC_ICONSET), "-o", str(MAC_ICNS))

    win_master = plated("win", WIN_PLATE_FRACTION, WIN_CORNER_FRACTION, GLYPH_FRACTION_MAC)
    WIN_ICO.parent.mkdir(parents=True, exist_ok=True)
    layers = []
    for size in WIN_SIZES:
        layer = work / f"win-{size}.png"
        run("magick", str(win_master), "-resize", f"{size}x{size}", str(layer))
        layers.append(str(layer))
    run("magick", *layers, str(WIN_ICO))
    run("magick", str(win_master), "-resize", "256x256", str(WIN_PNG))

    # The in-app badge draws its own rounded corners, so its art is the full
    # bleed square the iOS icon already is.
    MARK_IMAGESET.mkdir(parents=True, exist_ok=True)
    entries = []
    for scale in (1, 2, 3):
        name = f"LogoMark@{scale}x.png" if scale > 1 else "LogoMark.png"
        run("magick", str(IOS_ICON), "-resize", f"{MARK_BASE * scale}x{MARK_BASE * scale}",
            str(MARK_IMAGESET / name))
        entries.append(f'{{"filename":"{name}","idiom":"universal","scale":"{scale}x"}}')
    (MARK_IMAGESET / "Contents.json").write_text(
        '{"images":[' + ",".join(entries) + '],"info":{"author":"xcode","version":1}}\n'
    )
    (MARK_IMAGESET.parent / "Contents.json").write_text(
        '{"info":{"author":"xcode","version":1}}\n'
    )
    run("magick", str(IOS_ICON), "-resize", f"{MARK_BASE * 3}x{MARK_BASE * 3}", str(WIN_MARK))

    print(IOS_ICON)
    print(MAC_ICNS)
    print(WIN_ICO)
    print(MARK_IMAGESET)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
