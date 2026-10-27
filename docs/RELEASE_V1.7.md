# mAIverse V1.7 candidate (1.7 / build 13)

- Replace the left/right gait sheets with clearer contact, weight-transfer and
  low-clearance passing poses. The earlier high-knee sheets were rejected after
  user feedback. Four individually corrected contact/passing keyposes make up a
  1.6-second two-step cycle, with feet kept near the ground; one direction
  takes ten seconds. Cover the full existing stage by extending the trip, rather
  than increasing the speed of the feet. Walk to the far edge, then return.
- Replace the stationary roll with separate clockwise/right and
  counterclockwise/left curled-body sequences. The body moves across the stage
  during its rotation, then recovers. Five seconds per direction, ten per trip.
- A walking round trip reserves four five-second slots; a rolling round trip
  reserves two. Neither is cut short by the next randomly chosen action. The
  offline plan still loops every sixty seconds with two possible starting seeds.
- Task-page previews now share the same position and frame samples as the
  island, so walking and rolling previews also travel and return.
- Keep the three scene backgrounds, opaque frame coverage, preloaded native
  glyph timing, static low-luminance/reduced-motion fallbacks and embedded Widget.
- Add regression coverage for rolling travel, complete slow gait cycles,
  loop closure, selection filters and identical App/island movement samples.
  System-video QA now measures both walking and rolling legs in both directions.

Local validation: the resource tests cover both
rolling directions, full slow gait cycles, consistent character scale and matching preview/native timelines.
The compiler generates 181 registered fonts and eight complete 1,800-frame
plans. The fourteen motion-resource tests pass; four packaging checks passed
before the final artwork revision, with packaging logic unchanged. Cloud Xcode,
native CoreText and system-video validation are pending for this candidate.
Local generated-art previews do not replace actual
system playback. This branch has not been signed or tested on the user's phone;
no claim is made about physical-device frame rate, battery use or background
stability. End any old activity before starting a new one after upgrading, and
sign both the application and its embedded Widget extension.
