# Architecture

```
Vision Pro app ──HTTP POST session.json──▶ ingest (laptop, :8787)
      │                                       │ writes data/sessions/<id>.json
      │ live trial events (WebSocket)          │ runs ml features + age model
      ▼                                       ▼
 AirPlay mirror                     dashboard (browser, WebSocket)
```

## visionOS app (`apps/vision`)

SwiftUI window for consent, participant entry and results. ImmersiveSpace (mixed) for tasks.

- `ARKitSession` with `HandTrackingProvider` for index tip and wrist joints, `WorldTrackingProvider` for head pose, `SceneReconstructionProvider` and `PlaneDetectionProvider` for spawn points and Corsi anchors.
- RealityKit entities for targets. Contact test is fingertip distance to target center under target radius, checked every hand update. RealityKit collisions are not used for scoring.
- All timestamps are seconds since session start from one monotonic clock (`CACurrentMediaTime` offset).
- Session builds in memory, saves to the app Documents folder, then POSTs to ingest. Upload failure keeps the file for retry.
- Live events: `trial_start`, `trial_end` sent over WebSocket to ingest if connected. Tasks never wait on the network.

Target: visionOS 2.0+, Swift 6 toolchain in Swift 5 language mode, XcodeGen `project.yml`.

## Ingest (`services/ingest`)

- `POST /sessions` validates against the schema, saves, computes features and age, returns them.
- `GET /sessions` lists summaries. `GET /sessions/{id}` returns session plus features.
- `WS /live` relays app events and finished results to dashboards.
- Runs on the operator laptop. App reads the ingest URL from settings.

## ML (`ml`)

Pure Python package `sha_biomarkers`, stdlib only for features. Model training may use numpy and scikit-learn. Ingest imports it directly.

## Dashboard (`apps/dashboard`)

Static page served by ingest. See `dashboard.md`.
