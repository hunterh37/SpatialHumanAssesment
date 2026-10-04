visionOS app. Specs: `specs/architecture.md`, `specs/tasks/`.

```
make app    # xcodegen generate && open SpatialAge.xcodeproj
```

Set `DEVELOPMENT_TEAM` in `project.yml` locally. The `.xcodeproj` is generated and git ignored.

`Sources/Session` mirrors the schema. `Sources/Tracking` wraps ARKit. `Sources/Tasks` holds one file per task. `Sources/Network` talks to ingest.
