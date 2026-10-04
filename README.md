# Spatial Human Assessment

Five Vision Pro minigames (Pendulum, Spark, Gate, Constellation, Orbit) that measure reaction, reach and spatial memory as a functional aging biomarker. Read `PRD.md`, then the spec for the area you work on in `specs/`. Games: `specs/games/`. Score: `specs/score.md`.

```
apps/vision        visionOS app (Swift, XcodeGen)
apps/dashboard     live audience dashboard (web)
services/ingest    receives sessions from the headset, pushes to dashboard
ml                 feature extraction and age model (Python)
packages/schema    session JSON schema and examples, shared by all
packages/ScoreKit  Swift scoring: metrics, norms, Spatial Age, pace of aging, CLI
showcase           showcase PDF and its build script
specs              specs per area
concept            original concept deck and figures
data               local session files, git ignored
```

Quick start without a headset:

```
make sample     # write synthetic sessions to data/synthetic
make features   # print features for each synthetic session
make test
```

Rules: branch per change, PR into `main`, one area per PR where possible. Schema changes need a version bump.
