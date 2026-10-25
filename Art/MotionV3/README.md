# V1.5 walking artwork

`sources/` contains two accepted ImageGen 4x4 atlases. Each is sliced into 16 transparent frame files by `Scripts/import_walk_v3.py`; the same scale is used for every frame of a sequence. Isolated atlas-neighbor fragments are discarded by connected-component selection. Prompts and rejected-candidate prompts are preserved here; rejected images stay in ignored `build/`.

The new manifest inherits idle / roll / turn resources from MotionV2, replaces both walking sequences, and binds translation to the actual gait interval. The first candidates with wrong row count or body proportions were not used. No optical-flow interpolation or alpha crossfade was used to count fake intermediate poses.

Generation: built-in ImageGen with reference identity and left / right source pose; actual alpha output. Left and right were separately drawn. Old images remain in MotionV2. Font-only matte compositing happens later in `prepare_motion.py`, not in these transparent sprites.

The target native cadence is 30fps; model-generated details vary slightly between frames. Native playback, anatomy and device performance must be checked on actual captures, not inferred from the number of PNG files.
