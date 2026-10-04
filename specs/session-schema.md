# Session schema

Source of truth: `packages/schema/session.schema.json`. Example: `packages/schema/examples/session.example.json`.

One JSON file per session. Times are seconds since session start. Positions are meters in the ARKit world frame, y up.

Top level: `schema_version`, `session_id`, `participant`, `device`, `started_at` (ISO 8601), `blocks`, optional `healthkit`.

`participant`: `code` (random, no names), `age_years`, `sex`, `handedness`.

`blocks`: one per task run, `{ task, familiarization, trials }`. `task` is `simple_rt`, `choice_rt` or `corsi`.

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

Corsi trial: `index`, `span`, `sequence` (cube ids), `response` (cube ids), `correct`, `start_t`, `end_t`.

## Versioning

Semver in `schema_version`. Additive optional fields bump minor. Anything else bumps major and needs an update to `ml` in the same PR.

## Changelog

- 0.1.0 initial.
