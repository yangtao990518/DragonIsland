#!/usr/bin/env python3
"""Fail if an IPA is missing the Live Activity extension or its resources."""
import argparse
import hashlib
from io import BytesIO
import json
import plistlib
import zipfile
import wave
from pathlib import PurePosixPath
import struct


def verify_builtin_stickers(archive, app_root, widget_root):
    names = set(archive.namelist())
    catalog = json.loads(archive.read(f'{app_root}/BuiltinStickers.json'))
    stickers = catalog['stickers']
    if catalog['version'] != 1 or len(stickers) != 40 or len({s['id'] for s in stickers}) != 40:
        raise ValueError('Missing built-in sticker catalog')
    if any(sum(s['characterID'] == character for s in stickers) != 20 for character in ('xiaobai', 'dafeiyu')):
        raise ValueError('Expected 20 built-in stickers for each character')
    for sticker in stickers:
        asset = sticker['asset']
        digest = asset['sha256']
        if len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest) or asset['fileExtension'] != 'png':
            raise ValueError('Invalid bundled sticker path')
        locations = (f'{app_root}/{digest}.png', f'{app_root}/BuiltinStickers/{digest}.png')
        path = next((path for path in locations if path in names), None)
        if path is None:
            raise ValueError('Sticker image is missing from App bundle')
        data = archive.read(path)
        if hashlib.sha256(data).hexdigest() != digest or len(data) != asset['byteCount']:
            raise ValueError(f'Bundled sticker differs from catalog: {path}, expected {asset["byteCount"]} bytes, got {len(data)}')
        if (len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[25] != 6
                or struct.unpack('>II', data[16:24]) != (asset['width'], asset['height'])
                or not 0 < max(asset['width'], asset['height']) <= 450):
            raise ValueError('Invalid bundled transparent sticker format or dimensions')
        if f'{widget_root}/{digest}.png' in names or f'{widget_root}/BuiltinStickers/{digest}.png' in names:
            raise ValueError('Chat stickers must not bloat the Widget extension')
    if any(name.startswith(app_root + '/') and PurePosixPath(name).name in {'DafeiyuDogWalkTest.mp4', 'DafeiyuDogWalkTest.json'} for name in names):
        raise ValueError('Retired video comparison must not be included')
    print('Built-in stickers verified: 20 Xiaobai + 20 Dafeiyu, transparent bytes, App only.')


def verify_current_timelines(archive, root, characters):
    """Check every character bank, including two-minute indexed dance plans."""
    for character in characters:
        profile = character.get('motion', {})
        resource = profile.get('timelineResource', 'MotionTimeline')
        data = json.loads(archive.read(f'{root}/{resource}.json'))
        actions = {a['id'] for a in profile.get('dailyActions', [])}
        dances = actions & {'dance1', 'dance2'}
        period, banks = (120, 128) if dances else (60, 32 if 'pet_walk' in actions else 16)
        if (data['fps'] != 30 or data['period'] != period or len(data['plans']) != banks
                or data['scenes'] != ['black', 'meadow', 'night']
                or data['stagePixels'] != [180, 96] or data['travelPixels'] != 100):
            raise ValueError(f'Incomplete automatic-motion plans: {character["id"]}')
        if {p['id'] for p in data['plans']} != set(range(banks)):
            raise ValueError('Missing motion bank')
        for plan in data['plans']:
            if 'frameIndices' in plan:
                table = data.get('frameTable', [])
                indices = plan['frameIndices']
                if (len(indices) != period * 30 or not table
                        or any(type(i) is not int or not 0 <= i < len(table) for i in indices)):
                    raise ValueError('Invalid indexed motion sequence')
                frames = [table[i] for i in indices]
            else:
                frames = plan['frames']
            if len(frames) != period * 30:
                raise ValueError('Incomplete motion sequence')
            for action, bit in (('dance1', 16), ('dance2', 32)):
                selected = [f for f in frames if f['action'] == action]
                enabled = action in dances and bool(plan['mask'] & bit)
                if bool(selected) != enabled:
                    raise ValueError('Dance selection differs from motion bank')
                if enabled and (selected[0]['sourceFrame'] != 0 or selected[-1]['sourceFrame'] != 719
                                or len(selected) / 30 < 12.096009):
                    raise ValueError('Dance was shortened in automatic motion plan')


def verify_current_video_atlases(archive, root):
    names = set(archive.namelist())
    clips = json.loads(archive.read(f'{root}/VideoActions.json'))
    if {c['action'] for c in clips} != {'dance1', 'dance2'} or len(clips) != 2:
        raise ValueError('Missing full dance atlas catalog')
    for clip in clips:
        starts, holds = clip['frameStartMs'], clip['frameDurationsMs']
        if (clip['frameCount'] != 720 or len(starts) != 720 or len(holds) != 720
                or abs(clip['durationMs'] - 12096.009) > .001
                or abs(sum(holds) - clip['durationMs']) > .001
                or starts[0] != 0 or any(b <= a for a, b in zip(starts, starts[1:]))
                or any(hold <= 0 for hold in holds)):
            raise ValueError('Incomplete original dance timing')
        for a, b, hold in zip(starts, starts[1:], holds):
            if abs(b - a - hold) > .001:
                raise ValueError('Dance presentation timestamps differ')
        if (len(clip['atlases']) * clip['grid'][0] * clip['grid'][1] < 720
                or any(f'{root}/{name}.png' not in names for name in clip['atlases'])):
            raise ValueError('Missing full dance atlas resources')


def verify_survivor(archive, app_root, widget_root):
    from PIL import Image
    base = app_root + '/SurvivorGame/'
    manifest = json.loads(archive.read(base + 'manifest.json'))
    required = {'dafeiyu-run', 'demon-run', 'mushroom-run'} | {f'thunder-{i}' for i in range(1, 6)}
    if {c['id'] for c in manifest['clips']} != required or manifest['dropped_frames'] or manifest['synthesized_frames'] or manifest['playback_speed'] != 1:
        raise ValueError('Incomplete or retimed survivor clips')
    for clip in manifest['clips']:
        if len(clip['frames']) != 240: raise ValueError('Survivor frame count differs')
        end = 0
        for index, frame in enumerate(clip['frames']):
            if frame['source_index'] != index or abs(frame['start_ms']-end) > .01 or frame['duration_ms'] <= 0:
                raise ValueError('Broken survivor source timeline')
            end = frame['start_ms'] + frame['duration_ms']
        if abs(end-clip['duration_ms']) > .01 or abs(end-4096.009) > .01:
            raise ValueError('Survivor final hold was changed')
        for page in clip['pages']:
            if '..' in page['file'] or page['file'].startswith('/'): raise ValueError('Invalid survivor page path')
            raw = archive.read(base + page['file'])
            if hashlib.sha256(raw).hexdigest() != page['sha256']: raise ValueError('Survivor atlas bytes differ')
            with Image.open(BytesIO(raw)) as image:
                if image.mode != 'RGBA' or image.size != tuple(a*b for a,b in zip(clip['cell_size'],clip['grid'])):
                    raise ValueError('Invalid survivor atlas format')
    bubble = json.loads(archive.read(base + 'water-bubble.json'))
    if hashlib.sha256(archive.read(base+'water-bubble.png')).hexdigest() != bubble['sha256']:
        raise ValueError('Basic attack bubble differs')
    idle = json.loads(archive.read(base + 'dafeiyu-idle.json'))
    if hashlib.sha256(archive.read(base+'dafeiyu-idle.png')).hexdigest() != idle['sha256']:
        raise ValueError('Approved idle artwork differs')
    if any(name.startswith(widget_root+'/SurvivorGame/') for name in archive.namelist()):
        raise ValueError('Game atlases must be App-only')
    print('Survivor verified: eight full 240-frame clips, original holds, PNG hashes and water bubble, App only.')


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
                characters=json.loads(archive.read(f'{root}/Characters.json'))
                expected_fonts=1+180*sum(c['id']=='xiaobai' or bool(c.get('motion')) for c in characters) if scenes_version else 61 if required_fps==30 else 129
                if tuple(map(int, app['CFBundleShortVersionString'].split('.'))) >= (1,8) and int(app['CFBundleVersion']) >= 20:
                    unread = json.loads(archive.read(f'{root}/UnreadAvatarFonts.json'))
                    expected_names = {f'mAIverseUnread{role}F{i}.ttf' for role in ('Xiaobai', 'Dafeiyu') for i in range(16)}
                    if unread.get('fps') != 8 or unread.get('phases') != 16 or unread.get('stagePixels') != [180, 96] or {f['font'] for f in unread['fonts']} != expected_names or len(unread['fonts']) != 32:
                        raise ValueError('Invalid unread avatar font manifest')
                    for item in unread['fonts']:
                        if item['font'] not in fonts or hashlib.sha256(archive.read(f'{root}/{item["font"]}')).hexdigest() != item['sha256']:
                            raise ValueError('Missing or changed registered unread avatar font')
                    expected_fonts += len(expected_names)
                if len(fonts)!=expected_fonts or any(f'{root}/{font}' not in names for font in fonts):
                    raise ValueError(f'Missing registered system-timer motion fonts in {root}')
                current = tuple(map(int,app['CFBundleShortVersionString'].split('.'))) >= (1,8) and int(app['CFBundleVersion']) >= 16
                if current:
                    verify_current_timelines(archive, root, characters)
                elif fps!=required_fps or period!=60 or len(data['plans'])!=8 or any(len(p['frames'])!=fps*period for p in data['plans']):
                    raise ValueError(f'Incomplete automatic-motion plans in {root}')
                if scenes_version and (data.get('scenes')!=['black','meadow','night'] or data.get('stagePixels')!=[180,96] or data.get('travelPixels')!=100):
                    raise ValueError(f'Missing scenery or full-width walking resources in {root}')
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            if app[key] != widget[key]:
                raise ValueError(f"App and widget version differ: {key}")
        if tuple(map(int, app['CFBundleShortVersionString'].split('.'))) >= (1, 8):
            verify_voices(archive, app_root, app)
            if int(app['CFBundleVersion']) >= 16:
                verify_current_video_atlases(archive, app_root)
            if int(app['CFBundleVersion']) >= 18:
                verify_builtin_stickers(archive, app_root, widget_root)
            if int(app['CFBundleVersion']) >= 21:
                verify_survivor(archive, app_root, widget_root)
        print("IPA structure verified: main app, embedded WidgetKit extension, binaries, assets, versions.")
        print("Signing and physical-device behavior are NOT verified by this check.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa")
    verify(parser.parse_args().ipa)

