# V1.7 natural walking and travelling rolls

The user requested ordinary, unhurried foot mechanics with a long walking path,
and actual left/right rolling travel rather than a stationary tumble.

All character artwork originates from built-in ImageGen with Xiaobai's approved
reference. `sources/` preserves the accepted artwork, and the adjacent prompt
files preserve the exact requests. High-knee candidates and sheets whose feet
did not alternate clearly were rejected. Their prompts remain as provenance;
their pixels are not used by the runtime.

- Left/right walking: four contact/passing keyposes per direction, 400ms each.
  The right-facing keyposes were individually corrected, keyed and assembled;
  the left-facing sheet derives the matching directional poses through ImageGen.
  Feet stay close to the ground, and opposite contact poses exchange which leg
  is ahead. Each complete two-step cycle takes 1.6 seconds, with six cycles during 9.6 seconds of travel.
  One leg takes ten seconds including stationary entry/settle; the return leg
  follows immediately. This is a 20-second round trip, not faster foot playback.
- Left/right rolling: twelve-frame direction-specific crouch, curled rotation,
  and recovery. One leg takes five seconds, including 3.55 seconds of translation
  during the tucked rotation. Clockwise goes right; counterclockwise goes left.
- Both actions cover the same full 100 native-pixel (about 33.3pt) root path in
  the existing 60x32pt content stage. The system island shell is unchanged.

The four genuine walk drawings are held at their authored cadence. The native
30Hz target concerns positioning and timer masks; it does not imply thirty
independently drawn foot poses per second. No synthetic intermediate foot poses
are counted as new drawings.

Processing uses the generate2dsprite processor for magenta keying, edge cleanup,
component filtering, shared scaling and frame extraction. First locate empty row
gutters with `Scripts/regrid_motion_v4.py`; this prevents clipping hair at an
approximate generated row boundary. `Scripts/import_motion_v4.py` converts those
keyed outputs into common 512x640 frames with groundY=600. Single-image edits are
normalized for their output-resolution difference by `assemble_walk_keys.py`;
their character art is not redrawn by that script. A single scale per
action preserves the shorter silhouette of a crouched body; no optical-flow,
alpha crossfades or procedurally drawn character art is used.

`import-qc.json` records source edge checks and output bounds. The native font
compiler and App previews consume the same sampled movement legs. Review GIFs
from `Scripts/preview_motion_v4.py` show those real-time timelines; they are local
art/trajectory previews, not proof of playback on an iPhone.
