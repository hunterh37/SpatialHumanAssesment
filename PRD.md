# Spatial Human Assessment PRD

Status: hackathon draft, v0.1. Concept deck: `concept/SpatialReactionMemory_Concept.pdf`.

## Problem

Blood and epigenetic aging clocks need a lab. Processing speed, reach control and spatial working memory decline with age along published curves, and Apple Vision Pro already tracks hands, head and the room. A five minute game in the headset can produce a cheap, repeatable functional aging biomarker.

## Product

A visionOS app that runs three tasks in the user's real room, exports one session file, and returns a functional age estimate.

1. Simple reaction. One target spawns within arm reach. Touch it with the index fingertip.
2. Choice reaction. Blue and orange targets spawn together. Touch blue only.
3. 3D Corsi. Cubes anchored on room surfaces light in sequence. Touch them back in order.

Each task starts with a short unscored familiarization round.

## Outputs

Per session: reaction time, movement time, decision time, reaction time variability, commission and omission rates, Corsi span, reach time by target eccentricity, functional age, and age gap (functional minus chronological). Definitions live in `specs/features.md`.

## Users

Participant wears the headset. Operator starts sessions and enters age, sex and handedness. Audience watches AirPlay mirroring plus the live dashboard.

## Hackathon goals

- App runs all three tasks end to end in under 6 minutes.
- Session JSON validates against `packages/schema/session.schema.json`.
- Pipeline turns a session into features and an age estimate in under 5 seconds.
- Collect 20+ sessions across a wide age range at the event.
- Report leave-one-out MAE against chronological age next to a predict-the-mean baseline.

## Stretch

HealthKit join (resting HR, HRV, VO2 max) where the participant consents. Head-turn kinematics. Test-retest on 5 participants.

## Out of scope

Clinical claims or diagnosis. Accounts and cloud storage. App Store release. Raw gaze (visionOS does not expose it to apps).

## Privacy

No names. A random participant code links sessions. Data stays on the operator laptop under `data/`, which git ignores. Consent screen before the first task.

## Risks

| Risk | Mitigation |
|---|---|
| Practice effects inflate repeat scores | Fixed familiarization round, only later trials scored |
| Small n makes the age model overfit | Few features, ridge regression, literature priors, LOO CV |
| Hand tracking dropouts | Log tracking state per frame, drop trials with gaps over 100 ms |
| Room too small for placement | Fallback spawn shell 0.4 to 0.7 m around the user |

## Workstreams

| Area | Path | Spec |
|---|---|---|
| visionOS app | `apps/vision` | `specs/tasks/*`, `specs/architecture.md` |
| Session contract | `packages/schema` | `specs/session-schema.md` |
| Features and age model | `ml` | `specs/features.md`, `specs/age-model.md` |
| Ingest service | `services/ingest` | `specs/architecture.md` |
| Live dashboard | `apps/dashboard` | `specs/dashboard.md` |

The schema is the contract between all areas. Changing it needs a version bump and a note in `specs/session-schema.md`.
