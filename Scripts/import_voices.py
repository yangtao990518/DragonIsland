#!/usr/bin/env python3
"""Import user-provided Xiaobai recordings; retain originals and make bundled PCM sounds.

Requires ffmpeg on PATH or imageio-ffmpeg. Never overwrites the user's source folder.
Original MP3 files are retained under Art/Voices; runtime sounds are short mono WAVs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
LINES = [
    ("早安，该醒啦", "温柔早安", "早安，该醒啦。今天也让小白陪着你吧。"),
    ("你定好的时间", "温柔提醒", "你定好的时间到了哦。先睁开眼睛，好不好？"),
    ("叮咚", "俏皮报到", "叮咚，你的小白来报到了！被窝里的你，听见了吗？"),
    ("唔", "一起起床", "唔……天亮了呀。我们一起起床吧。"),
    ("还困的话", "慢慢清醒", "还困的话，先伸个懒腰。慢慢来，我陪你清醒一下。"),
    ("今天可是我先醒", "我先醒啦", "今天可是我先醒的哦。这一次，换我来叫你起床！"),
    ("再睡下去", "轻声催促", "再睡下去，可要错过约好的时间啦。来，先坐起来。"),
    ("起床任务", "起床任务", "起床任务已经送达。完成之后，奖励你一句……早安呀。"),
    ("新的一天", "新的一天", "新的一天开始了。不用一下子打起精神，先迈出第一步就好。"),
    ("醒了吗", "早餐约定", "醒了吗？今天也有很多事情等着你。不过现在，先好好吃顿早餐吧。"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    originals = ROOT / "Art/Voices/xiaobai"
    sounds = ROOT / "App/Resources/VoiceSounds"
    originals.mkdir(parents=True, exist_ok=True)
    sounds.mkdir(parents=True, exist_ok=True)
    voices, provenance = [], []
    for index, (keyword, title, text) in enumerate(LINES, 1):
        matches = [p for p in args.source.iterdir() if keyword in p.name and p.suffix.lower() in (".mp3", ".mp4", ".m4a", ".wav")]
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one source for {keyword!r}, found {len(matches)}")
        source = matches[0]
        original = originals / f"{index:02d}{source.suffix.lower()}"
        shutil.copy2(source, original)
        file = f"xiaobai-alarm-{index:02d}.wav"
        output = sounds / file
        # Only trim outer silence, preserving pauses inside the spoken line.
        trim = "silenceremove=start_periods=1:start_duration=0.12:start_threshold=-48dB,areverse," \
               "silenceremove=start_periods=1:start_duration=0.12:start_threshold=-48dB,areverse"
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(original), "-vn",
                        "-af", trim + ",loudnorm=I=-18:TP=-2:LRA=7,afade=t=in:d=0.015",
                        "-ac", "1", "-ar", "24000", "-c:a", "pcm_s16le", str(output)], check=True)
        with wave.open(str(output), "rb") as audio:
            duration = audio.getnframes() / audio.getframerate()
            if not 0.5 < duration < 29:
                raise ValueError(f"Audio must be 0.5–29 seconds, got {duration}: {output}")
        voices.append(dict(id=f"xiaobai-{index:02d}", characterID="xiaobai", title=title, text=text,
                           file=file, duration=round(duration, 4)))
        provenance.append(dict(id=voices[-1]["id"], original=str(original.relative_to(ROOT)).replace("\\", "/"),
                               sourceFilename=source.name, sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),
                               outputSHA256=hashlib.sha256(output.read_bytes()).hexdigest()))
    (ROOT / "App/Resources/Voices.json").write_text(json.dumps(voices, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (originals.parent / "import.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(voices, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
