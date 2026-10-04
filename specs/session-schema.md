# Session schema

Source of truth: `packages/schema/session.schema.json`. Example: `packages/schema/examples/session.example.json`.

One JSON file per session. Times are seconds since session start. Positions are meters in the ARKit world frame, y up.

Top level: `schema_version`, `session_id`, `participant`, `device`, `started_at` (ISO 8601), `blocks`, optional `healthkit`.

`participant`: `code` (random, no names), `age_years`, `sex`, `handedness`.

`blocks`: one per task run, `{ task, familiarization, seed, trials }`. `task` is `simple_rt` (Spark), `choice_rt` (Gate), `corsi` (Constellation), `pendulum` (Pendulum) or `pursuit` (Orbit). Decoders pick the trial type from `task`.

Reaction trial (`simple_rt`, `choice_rt`):

| Field | Meaning |
|---|---|
| `index` | trial number in block |
| `kind` | `go` (blue) or `nogo` (orange) |
| `spawn_t` | target visible |
| `move_t` | hand movement onset, null if none |
| `contact_t` | fingertip entered radius, null if none |
| `position` | target center `[x,y,z]` |
| `eccentricity_deg` | angle between head forward and target at spawn |
| `outcome` | `hit`, `miss` (omission), `false_alarm` (commission), `correct_reject` |
| `tracking_gap_ms` | longest hand tracking gap during trial |
| `endpoint_error_m` | optional, fingertip to target center at contact |
| `trace` | optional, fingertip path `{t: [], p: [[x,y,z]]}` at about 90 Hz, from 0.35 s before spawn to contact |

Corsi trial: `index`, `span`, `sequence` (cube ids), `response` (cube ids), `correct`, `start_t`, `end_t`, optional `tap_t` (time of each response touch).

Pendulum trial:

| Field | Meaning |
|---|---|
| `length_m`, `amplitude_deg` | cord length and swing amplitude |
| `release_t` | cord releases |
| `release_angle_deg`, `release_position`, `release_velocity` | bob state at release, the start of the ballistic fall |
| `catch_t`, `catch_position` | grasp closed on the bob, null on a drop |
| `outcome` | `catch`, `drop`, `anticipation` (grasp under 100 ms after release) |
| `aperture_release_m`, `aperture_catch_m` | thumb to index distance |
| `tracking_gap_ms`, `trace` | as reaction trials |

Pursuit trial: `start_t`, `duration_s`, `path` (Lissajous `center`, `amplitude`, `frequency_hz`, `phase`; target = center + amplitude * sin(2 pi f (t - start_t) + phase)), sample arrays `t`, `target`, `finger` (null while untracked), `hand`, `tracking_gap_ms`.

## Versioning

Semver in `schema_version`. Additive optional fields bump minor. Anything else bumps major and needs an update to `ml` in the same PR.

## Changelog

- 0.1.0 initial.
- 0.2.0 tasks `pendulum` and `pursuit`; optional `trace`, `endpoint_error_m`, `tap_t`. 0.1 files still validate. Python `ml` ignores the new tasks; scoring for them lives in `packages/ScoreKit`.
- 0.3.0 adds the `reach_grab`, `wall` and `color_dots` tasks and their trial types (Reach and Grab, Hole in the Wall, Color Dots). Additive, so existing sessions still validate.
- 0.4.0 aligns the five catalog games with the Games Ideas deck. Optional fields only: `cue` on reaction trials (Spatial Tracking), `stick_index`, `eccentricity_deg`, `gravity_scale` on pendulum trials (Stick Drop), `stand_at` and `freeze` on reach-grab trials (Scary Balance), `rule`, `rule_match`, `colors`, `radii`, `selected`, `select_t`, `recall_mode` on color-dots trials (Spatial Memory). Task names are unchanged, so 0.3 files still validate and score.
