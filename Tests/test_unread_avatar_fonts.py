import hashlib
from io import BytesIO
import json
from pathlib import Path
import sys
import unittest
from PIL import Image
from fontTools.ttLib import TTFont
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"Scripts"))
import prepare_unread_avatar as unread

class UnreadAvatarFontTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = unread.prepare(register=False)
        cls.characters = json.loads((ROOT/"Shared/Resources/Characters.json").read_text(encoding="utf-8"))
    def test_avatar_frames_only_translate_the_same_fitted_identity_without_clipping(self):
        for character in self.characters:
            avatar = unread.portrait(character)
            crops=[]; positions=[]
            for phase in range(8):
                frame = unread.frame(avatar,0,phase)
                self.assertEqual(frame.size,(180,96))
                self.assertEqual(frame.getchannel("A").getextrema(),(255,255))
                box=frame.convert("RGB").getbbox()
                self.assertTrue(0<box[0]<box[2]<180 and 0<box[1]<box[3]<96)
                positions.append(box[0]); crops.append(frame.crop(box).tobytes())
            self.assertGreater(max(positions)-min(positions),0)
            self.assertEqual(len(set(crops)),1, "Changing expression or body is not an avatar shake")
            self.assertEqual(unread.frame(avatar,1,0).tobytes(),unread.frame(avatar,1,5).tobytes())
    def test_each_role_has_all_registered_phase_families_and_valid_png_payloads(self):
        manifest=self.manifest
        self.assertEqual((manifest["fps"],manifest["phases"]),(8,16))
        self.assertEqual(len(manifest["fonts"]),32)
        for role in ("xiaobai","dafeiyu"):
            self.assertEqual({row["phase"] for row in manifest["fonts"] if row["characterID"]==role},set(range(16)))
        for row in manifest["fonts"]:
            path=unread.OUTPUT/row["font"]
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),row["sha256"])
            with TTFont(path) as font:
                self.assertIn("GSUB",font); strike=font["sbix"].strikes[96]
                for second in range(60):
                    glyph=strike.glyphs[f"f{second:02}"]
                    if glyph.graphicType=="dupe": glyph=strike.glyphs[glyph.referenceGlyphName]
                    self.assertEqual(glyph.graphicType,"png ")
                    with Image.open(BytesIO(glyph.imageData)) as image:
                        self.assertEqual(image.size,(180,96))
                        self.assertEqual(image.getchannel("A").getextrema(),(255,255))
    def test_generated_font_bytes_are_reproducible(self):
        first={row["font"]:row["sha256"] for row in self.manifest["fonts"]}
        second=unread.prepare(register=False)
        self.assertEqual(first,{row["font"]:row["sha256"] for row in second["fonts"]})
    def test_compiled_timer_samples_show_the_intended_four_second_shake_cycle(self):
        for character in self.characters:
            avatar=unread.portrait(character)
            prefix="mAIverseUnread"+("Xiaobai" if character["id"]=="xiaobai" else "Dafeiyu")
            for elapsed in range(8):
                timer_second=(elapsed-(elapsed%2)-1)%60
                for phase in range(8):
                    font_phase=(elapsed%2)*8+phase
                    with TTFont(unread.OUTPUT/f"{prefix}F{font_phase}.ttf") as font:
                        strike=font["sbix"].strikes[96]; glyph=strike.glyphs[f"f{timer_second:02}"]
                        if glyph.graphicType=="dupe": glyph=strike.glyphs[glyph.referenceGlyphName]
                        with Image.open(BytesIO(glyph.imageData)) as image:
                            self.assertEqual(image.tobytes(),unread.frame(avatar,elapsed,phase).tobytes())

if __name__=="__main__": unittest.main()
