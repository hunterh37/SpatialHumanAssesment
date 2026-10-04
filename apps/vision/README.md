visionOS app. Specs: `specs/architecture.md`, `specs/tasks/`.

```
make app    # xcodegen generate && open SpatialAge.xcodeproj
```

Set `DEVELOPMENT_TEAM` in `project.yml` locally. The `.xcodeproj` is generated and git ignored.

`Sources/Design` tokens, tones, meshes, micro-interactions. `Sources/Stage` immersive stage, frame clock, director. `Sources/Games` one file per minigame. `Sources/Catalog` catalog and results. `Sources/Tracking` wraps ARKit. `Sources/Session` records into the ScoreKit session model. `Sources/Network` talks to ingest. Scoring lives in `packages/ScoreKit`, linked as a local package.
