# Character alarm voices

The ten Xiaobai recordings were supplied by the user in `sy/` on 2026-10-26.
`xiaobai/01.mp3` through `10.mp3` preserve the original bytes.
`import.json` maps original filenames, hashes and runtime hashes to stable voice IDs.

Runtime resources live in `App/Resources/VoiceSounds`, with character ownership and
text in `App/Resources/Voices.json`. They are mono 24 kHz, signed 16-bit PCM WAVs,
all shorter than 29 seconds. Outer silence was trimmed, inner pauses preserved,
and loudness normalized toward -18 LUFS with a -2 dBTP ceiling. No speech synthesis,
speed changes, pitch changes or replacement voices were introduced.

`Scripts/import_voices.py SOURCE_DIRECTORY` performs deterministic import using
ffmpeg (or imageio-ffmpeg). New characters must have their own catalog entries;
an absent voice pack must not borrow Xiaobai's recordings.
