"""Check real bundled audio, stable IDs and provenance rather than mock sounds."""
import array
import hashlib
import json
import math
from pathlib import Path
import sys
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]


def inspect_sounds():
    voices = json.loads((ROOT / "App/Resources/Voices.json").read_text(encoding="utf-8"))
    result = []
    for voice in voices:
        with wave.open(str(ROOT / "App/Resources/VoiceSounds" / voice["file"]), "rb") as sound:
            samples = array.array("h", sound.readframes(sound.getnframes()))
            if sys.byteorder != "little":
                samples.byteswap()
            duration = len(samples) / sound.getframerate()
            peak = max(abs(x) for x in samples)
            rms = math.sqrt(sum(x * x for x in samples) / len(samples))
            result.append(dict(id=voice["id"], duration=duration, rate=sound.getframerate(), channels=sound.getnchannels(),
                               sampleWidth=sound.getsampwidth(), peak=peak, rms=rms,
                               clippedSamples=sum(abs(x) >= 32767 for x in samples)))
    return voices, result


class VoiceResourceTests(unittest.TestCase):
    def test_all_ten_recordings_have_unique_ids_and_short_pcm_sound(self):
        voices, sounds = inspect_sounds()
        self.assertEqual(len(voices), 10)
        self.assertEqual(len({v["id"] for v in voices}), 10)
        self.assertEqual(len({v["file"] for v in voices}), 10)
        for voice, sound in zip(voices, sounds):
            self.assertEqual(voice["characterID"], "xiaobai")
            self.assertEqual(Path(voice["file"]).name, voice["file"])
            self.assertEqual((sound["rate"], sound["channels"], sound["sampleWidth"]), (24000, 1, 2))
            self.assertTrue(0.5 < sound["duration"] < 29)
            self.assertAlmostEqual(sound["duration"], voice["duration"], places=3)
            self.assertEqual(sound["clippedSamples"], 0)
            self.assertGreater(sound["rms"], 100)

    def test_originals_and_runtime_files_match_import_record(self):
        provenance = json.loads((ROOT / "Art/Voices/import.json").read_text(encoding="utf-8"))
        voices, _ = inspect_sounds()
        self.assertEqual(len(provenance), 10)
        for source, voice in zip(provenance, voices):
            self.assertEqual(source["id"], voice["id"])
            self.assertEqual(hashlib.sha256((ROOT / source["original"]).read_bytes()).hexdigest(), source["sourceSHA256"])
            self.assertEqual(hashlib.sha256((ROOT / "App/Resources/VoiceSounds" / voice["file"]).read_bytes()).hexdigest(),
                             source["outputSHA256"])


if __name__ == "__main__":
    unittest.main()
