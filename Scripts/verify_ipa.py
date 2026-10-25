#!/usr/bin/env python3
"""Fail if an IPA is missing the Live Activity extension or its resources."""
import argparse
import plistlib
import zipfile
from pathlib import PurePosixPath


def verify(path):
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Corrupt ZIP member: {bad}")
        names = set(archive.namelist())
        app_plists = [name for name in names if name.startswith("Payload/")
                      and len(PurePosixPath(name).parts) == 3 and name.endswith(".app/Info.plist")]
        if len(app_plists) != 1:
            raise ValueError("Expected exactly one Payload/*.app/Info.plist")
        app_root = str(PurePosixPath(app_plists[0]).parent)
        app = plistlib.loads(archive.read(app_plists[0]))
        if app.get("NSSupportsLiveActivities") is not True:
            raise ValueError("Main app does not enable Live Activities")
        executable = f"{app_root}/{app['CFBundleExecutable']}"
        if executable not in names or not archive.getinfo(executable).file_size:
            raise ValueError("Main app executable is missing")
        widget_plists = [name for name in names if name.startswith(app_root + "/PlugIns/")
                         and name.endswith(".appex/Info.plist")]
        if len(widget_plists) != 1:
            raise ValueError("Live Activity Widget extension is missing or ambiguous")
        widget_root = str(PurePosixPath(widget_plists[0]).parent)
        widget = plistlib.loads(archive.read(widget_plists[0]))
        if widget.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
            raise ValueError("Extension is not a WidgetKit extension")
        if not widget["CFBundleIdentifier"].startswith(app["CFBundleIdentifier"] + "."):
            raise ValueError("Extension bundle identifier is not nested under main app")
        for root, info in ((app_root, app), (widget_root, widget)):
            binary = f"{root}/{info['CFBundleExecutable']}"
            if binary not in names or archive.getinfo(binary).file_size == 0:
                raise ValueError(f"Missing executable: {binary}")
            if f"{root}/Assets.car" not in names:
                raise ValueError(f"Missing compiled character assets in {root}")
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            if app[key] != widget[key]:
                raise ValueError(f"App and widget version differ: {key}")
        print("IPA structure verified: main app, embedded WidgetKit extension, binaries, assets, versions.")
        print("Signing and physical-device behavior are NOT verified by this check.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa")
    verify(parser.parse_args().ipa)
