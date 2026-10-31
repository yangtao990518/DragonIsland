"""Create small identity-avatar timer fonts; never modifies approved action artwork."""
from io import BytesIO
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.sbixGlyph import Glyph
from fontTools.ttLib.tables.sbixStrike import Strike
from prepare_motion import base_font, features

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Shared/Resources/UnreadAvatarFonts"
FPS = 8
PHASES = FPS * 2
WIDTH, HEIGHT = 180, 96

def portrait(character):
    if character.get("standingSourceTiles"):
        parts = [Image.open(ROOT / p).convert("RGBA") for p in character["standingSourceTiles"]]
        source = Image.new("RGBA", (parts[0].width, sum(p.height for p in parts)))
        y = 0
        for part in parts:
            source.paste(part, (0, y)); y += part.height
    else:
        source = Image.open(ROOT / character["standingSource"]).convert("RGBA")
    x, y, w, h = character["avatarCrop"]
    crop = source.crop((round(x*source.width), round(y*source.height), round((x+w)*source.width), round((y+h)*source.height)))
    # Match the fitted avatar imageset, preserving the source head/horns.
    crop.thumbnail((80,80), Image.Resampling.LANCZOS)
    disk = Image.new("RGBA", (80,80), (224,218,242,255))
    disk.alpha_composite(crop, ((80-crop.width)//2, (80-crop.height)//2))
    mask = Image.new("L", (80,80)); ImageDraw.Draw(mask).ellipse((0,0,79,79), fill=255)
    disk.putalpha(mask)
    return disk

def frame(avatar, second, phase):
    offset = round(math.sin(2*math.pi*(phase % FPS)/FPS)*8) if second % 4 == 0 else 0
    canvas = Image.new("RGBA", (WIDTH, HEIGHT), (0,0,0,255))
    canvas.alpha_composite(avatar, (50+offset, 8))
    return canvas

def prepare(register=True):
    OUTPUT.mkdir(parents=True, exist_ok=True)
    characters = json.loads((ROOT/"Shared/Resources/Characters.json").read_text(encoding="utf-8"))
    rows = []
    for character in characters:
        if character["id"] not in ("xiaobai","dafeiyu"): continue
        avatar = portrait(character)
        prefix = "mAIverseUnread" + ("Xiaobai" if character["id"] == "xiaobai" else "Dafeiyu")
        for phase in range(PHASES):
            name = f"{prefix}F{phase}"
            order = [".notdef","space","colon"]+[f"d{i}" for i in range(10)]+[f"f{s:02}" for s in range(60)]
            font = base_font(name, order)
            strike = Strike(ppem=HEIGHT, resolution=72)
            seen = {}
            for second in range(60):
                # Match TimerMotionPortrait's one-phase preload and the second
                # set of gates. Font phases 8...15 represent the following second.
                tick = (((second + 1 - 60) % 60) * FPS + phase) % (60 * FPS)
                image = frame(avatar, tick // FPS, tick % FPS)
                buffer = BytesIO(); image.save(buffer, format="PNG"); data = buffer.getvalue()
                digest = hashlib.sha256(data).hexdigest(); glyph = f"f{second:02}"
                if digest in seen:
                    strike.glyphs[glyph] = Glyph(glyphName=glyph, graphicType="dupe", referenceGlyphName=seen[digest])
                else:
                    seen[digest] = glyph
                    strike.glyphs[glyph] = Glyph(glyphName=glyph, originOffsetX=0, originOffsetY=0, graphicType="png ", imageData=data)
            for glyph in order:
                if glyph not in strike.glyphs: strike.glyphs[glyph] = Glyph(glyphName=glyph)
            sbix = newTable("sbix"); sbix.strikes = {HEIGHT:strike}; font["sbix"] = sbix
            addOpenTypeFeaturesFromString(font, features([f"f{s:02}" for s in range(60)]))
            font.recalcTimestamp = False
            font["head"].created = font["head"].modified = 3786912000
            path = OUTPUT/f"{name}.ttf"; font.save(path)
            rows.append({"characterID":character["id"],"font":path.name,"phase":phase,
                         "sha256":hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {"version":1,"fps":FPS,"phases":PHASES,"stagePixels":[WIDTH,HEIGHT],
                "periodSeconds":4,"movingSeconds":1,"fonts":rows}
    (ROOT/"Shared/Resources/UnreadAvatarFonts.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    if register:
        spec = ROOT/"motion-fonts.yml"
        lines = [line for line in spec.read_text(encoding="utf-8").splitlines() if not line.strip().startswith("- mAIverseUnread")]
        marker = lines.index("  DragonIslandWidget:")
        lines[marker:marker] = [f'          - {row["font"]}' for row in rows]
        spec.write_text("\n".join(lines)+"\n", encoding="utf-8")
    print(f"Unread identity avatars: {len(rows)} timer fonts, original head art, bounded left/right motion.")
    return manifest

if __name__ == "__main__": prepare()
