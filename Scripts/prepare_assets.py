#!/usr/bin/env python3
"""Prepare size-specific Xcode assets from the approved character; no repainting."""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Art/dragon-original.png"
SHARED = ROOT / "Shared/Resources/Companion.xcassets"
APP = ROOT / "App/Resources/Assets.xcassets"


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def imageset(catalog, name, image, points):
    directory = catalog / f"{name}.imageset"
    directory.mkdir(parents=True, exist_ok=True)
    entries = []
    for scale in (1, 2, 3):
        file = f"{name}@{scale}x.png"
        image.resize((points * scale, points * scale), Image.Resampling.LANCZOS).save(directory / file)
        entries.append({"filename": file, "idiom": "universal", "scale": f"{scale}x"})
    write_json(directory / "Contents.json", {"images": entries, "info": {"author": "xcode", "version": 1}})


def main():
    source = Image.open(SOURCE).convert("RGBA")
    # Relative crop of the approved reference's head, retaining both white horns.
    w, h = source.size
    portrait = source.crop((int(w * .15), 0, int(w * .85), int(h * .70)))
    for catalog in (SHARED, APP):
        write_json(catalog / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    imageset(SHARED, "DragonCompact", portrait, 22)
    imageset(SHARED, "DragonFull", source, 88)
    imageset(APP, "DragonHero", source, 256)

    # iOS 17+ supports a single universal 1024px app icon. Flatten alpha for it.
    icon = Image.new("RGBA", (1024, 1024), (31, 25, 49, 255))
    face = portrait.resize((930, 930), Image.Resampling.LANCZOS)
    icon.alpha_composite(face, (47, 55))
    icon_dir = APP / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    icon.convert("RGB").save(icon_dir / "AppIcon.png")
    write_json(icon_dir / "Contents.json", {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1}
    })
    print("Assets ready: compact 22pt, expanded 88pt, hero 256pt, opaque app icon.")


if __name__ == "__main__":
    main()
