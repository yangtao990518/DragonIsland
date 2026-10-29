#!/usr/bin/env python3
"""Build per-character Xcode resources; preserve aspect ratio and alpha."""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Art/dragon-original.png"
CATALOG = ROOT / "Shared/Resources/Characters.json"
SHARED = ROOT / "Shared/Resources/Companion.xcassets"
APP = ROOT / "App/Resources/Assets.xcassets"


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def imageset(catalog, name, image, points):
    directory = catalog / f"{name}.imageset"
    directory.mkdir(parents=True, exist_ok=True)
    entries = []
    for scale in (1, 2, 3):
        file = f"{name}@{scale}x.png"
        width, height = (points, points) if isinstance(points, int) else points
        size = (width * scale, height * scale)
        fitted = image.copy()
        fitted.thumbnail(size, Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", size, (0, 0, 0, 0))
        canvas.alpha_composite(fitted, ((size[0] - fitted.width) // 2, (size[1] - fitted.height) // 2))
        canvas.save(directory / file)
        entries.append({"filename": file, "idiom": "universal", "scale": f"{scale}x"})
    write_json(directory / "Contents.json", {"images": entries, "info": {"author": "xcode", "version": 1}})


def main():
    source = Image.open(SOURCE).convert("RGBA")
    # Relative crop of the approved reference's head, retaining both white horns.
    w, h = source.size
    portrait = source.crop((int(w * .15), 0, int(w * .85), int(h * .70)))
    for catalog in (SHARED, APP):
        write_json(catalog / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    characters = json.loads(CATALOG.read_text(encoding="utf-8"))
    if not characters or len({c["id"] for c in characters}) != len(characters):
        raise ValueError("Character IDs must be nonempty and unique")
    for character in characters:
        chibi = Image.open(ROOT / character["chibiSource"]).convert("RGBA")
        if tiles := character.get("standingSourceTiles"):
            # Lossless source tiles keep individual source uploads small. Paste
            # straight RGBA pixels, preserving the original alpha exactly.
            parts = [Image.open(ROOT / path).convert("RGBA") for path in tiles]
            if len({part.width for part in parts}) != 1:
                raise ValueError("Standing source tiles must have identical widths")
            joined = Image.new("RGBA", (parts[0].width, sum(part.height for part in parts)))
            y = 0
            for part in parts:
                joined.paste(part, (0, y))
                y += part.height
            joined.save(ROOT / character["standingSource"])
        standing = Image.open(ROOT / character["standingSource"]).convert("RGBA")
        if standing.getchannel("A").getextrema()[0] == 255:
            raise ValueError(f"Standing art needs transparency: {character['id']}")
        imageset(SHARED, character["chibiAsset"], chibi, 26)
        imageset(SHARED, character["portraitAsset"], standing, (100, 134))
        # Normal-proportion head art for identity avatars; island actors remain Q版.
        x, y, w, h = character["avatarCrop"]
        sw, sh = standing.size
        avatar = standing.crop((round(x*sw), round(y*sh), round((x+w)*sw), round((y+h)*sh)))
        imageset(SHARED, character["portraitAsset"] + "Avatar", avatar, 64)
        imageset(APP, character["heroAsset"], standing, (300, 400))
        imageset(APP, character["chibiAsset"] + "Detail", chibi, 400)
        for photo in character.get("artworks", []):
            # Display a reviewed transparent cutout; retain immutable originals.
            image = Image.open(ROOT / photo["displaySource"]).convert("RGBA")
            if image.getchannel("A").getextrema()[0] == 255:
                raise ValueError(f"World artwork needs transparency: {photo['id']}")
            image = image.crop(image.getbbox())
            imageset(APP, photo["asset"], image, (400, 520))

    for name in ("GPT", "Claude", "DeepSeek", "Gemini", "Grok"):
        icon = Image.open(ROOT / f"Art/AppIcons/{name}.png").convert("RGB")
        asset = "AppIcon" if name == "GPT" else f"AppIcon{name}"
        icon_dir = APP / f"{asset}.appiconset"
        icon_dir.mkdir(parents=True, exist_ok=True)
        icon.resize((1024, 1024), Image.Resampling.LANCZOS).save(icon_dir / "AppIcon.png")
        write_json(icon_dir / "Contents.json", {
            "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1}
        })
        imageset(APP, f"IconPreview{name}", icon.convert("RGBA"), 64)
    print(f"Assets ready: {len(characters)} characters, separate chibi / standing / hero art, opaque app icon.")
    from prepare_video_actions import main as prepare_video_actions
    prepare_video_actions()


if __name__ == "__main__":
    main()

