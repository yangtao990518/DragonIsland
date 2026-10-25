"""Regression checks for a missing/broken embedded Live Activity extension."""
import importlib.util
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("verify_ipa", ROOT / "Scripts/verify_ipa.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PackagingTests(unittest.TestCase):
    def fixture(self, path, *, widget=True, version="1", live=True):
        app = "Payload/DragonIsland.app"
        ext = app + "/PlugIns/DragonIslandWidget.appex"
        common = {"CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"}
        with zipfile.ZipFile(path, "w") as z:
            z.writestr(app + "/Info.plist", plistlib.dumps(dict(common,
                CFBundleIdentifier="com.dragonisle.prototype.app", CFBundleExecutable="DragonIsland",
                NSSupportsLiveActivities=live)))
            z.writestr(app + "/DragonIsland", b"binary-placeholder")
            z.writestr(app + "/Assets.car", b"assets-placeholder")
            if widget:
                z.writestr(ext + "/Info.plist", plistlib.dumps(dict(common,
                    CFBundleVersion=version, CFBundleIdentifier="com.dragonisle.prototype.app.widget",
                    CFBundleExecutable="DragonIslandWidget",
                    NSExtension={"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"})))
                z.writestr(ext + "/DragonIslandWidget", b"extension-placeholder")
                z.writestr(ext + "/Assets.car", b"assets-placeholder")

    def test_complete_bundle(self):
        with tempfile.TemporaryDirectory() as d:
            ipa = Path(d) / "test.ipa"
            self.fixture(ipa)
            module.verify(ipa)

    def test_missing_extension_fails(self):
        with tempfile.TemporaryDirectory() as d:
            ipa = Path(d) / "test.ipa"
            self.fixture(ipa, widget=False)
            with self.assertRaisesRegex(ValueError, "extension is missing"):
                module.verify(ipa)

    def test_mismatched_version_fails(self):
        with tempfile.TemporaryDirectory() as d:
            ipa = Path(d) / "test.ipa"
            self.fixture(ipa, version="2")
            with self.assertRaisesRegex(ValueError, "version differ"):
                module.verify(ipa)

    def test_disabled_live_activity_fails(self):
        with tempfile.TemporaryDirectory() as d:
            ipa = Path(d) / "test.ipa"
            self.fixture(ipa, live=False)
            with self.assertRaisesRegex(ValueError, "does not enable"):
                module.verify(ipa)


if __name__ == "__main__":
    unittest.main()
