#!/usr/bin/env python3
"""Fail if an IPA is missing the Live Activity extension or its resources."""
import argparse
from io import BytesIO
import json
import plistlib
import zipfile
import wave
from pathlib import PurePosixPath


def verify_voices(archive, app_root, app):
    if not app.get('NSAlarmKitUsageDescription'):
        raise ValueError('Missing AlarmKit permission usage description')
    voices = json.loads(archive.read(f'{app_root}/Voices.json'))
    if not voices or len({v['id'] for v in voices}) != len(voices):
        raise ValueError('Missing or duplicate character voices')
    characters = {c['id'] for c in json.loads(archive.read(f'{app_root}/Characters.json'))}
    for voice in voices:
        if voice['characterID'] not in characters or PurePosixPath(voice['file']).name != voice['file']:
            raise ValueError('Invalid character voice mapping')
        with wave.open(BytesIO(archive.read(f"{app_root}/{voice['file']}")), 'rb') as sound:
            duration = sound.getnframes() / sound.getframerate()
            if sound.getsampwidth() != 2 or sound.getnchannels() != 1 or not 0.5 < duration < 29:
                raise ValueError('Invalid bundled alarm sound format or duration')
            if abs(duration - voice['duration']) > 0.001:
                raise ValueError('Bundled voice duration differs from catalog')
    print(f'Alarm resources verified: {len(voices)} character voices, short mono PCM sounds, permission text.')


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
            if tuple(map(int, app['CFBundleShortVersionString'].split('.'))) >= (1,4):
                fonts=info.get('UIAppFonts',[])
                data=json.loads(archive.read(f'{root}/MotionTimeline.json'))
                fps=data.get('fps',0)
                period=data.get('period',0)
                required_fps=30 if tuple(map(int,app['CFBundleShortVersionString'].split('.'))) >= (1,5) else 8
                scenes_version=tuple(map(int,app['CFBundleShortVersionString'].split('.'))) >= (1,6)
                expected_fonts=181 if scenes_version else 61 if required_fps==30 else 129
                if len(fonts)!=expected_fonts or any(f'{root}/{font}' not in names for font in fonts):
                    raise ValueError(f'Missing registered system-timer motion fonts in {root}')
                if fps!=required_fps or period!=60 or len(data['plans'])!=8 or any(len(p['frames'])!=fps*period for p in data['plans']):
                    raise ValueError(f'Incomplete automatic-motion plans in {root}')
                if scenes_version and (data.get('scenes')!=['black','meadow','night'] or data.get('stagePixels')!=[180,96] or data.get('travelPixels')!=100):
                    raise ValueError(f'Missing scenery or full-width walking resources in {root}')
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            if app[key] != widget[key]:
                raise ValueError(f"App and widget version differ: {key}")
        if tuple(map(int, app['CFBundleShortVersionString'].split('.'))) >= (1, 8):
            verify_voices(archive, app_root, app)
        print("IPA structure verified: main app, embedded WidgetKit extension, binaries, assets, versions.")
        print("Signing and physical-device behavior are NOT verified by this check.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa")
    verify(parser.parse_args().ipa)
