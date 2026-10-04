# Bird

Status: builds for visionOS 26 (Debug, simulator). Perched pose, blink, head turns and balance flutter were
checked in the visionOS 26.2 simulator with `-birdpreview YES`. Flight, the palm-up call, landing, petting and
takeoff need hand tracking, so they have not run yet; they need a device pass.

Files:
- `apps/vision/SpatialAge/Sources/Design/Bird.swift` (new): rig, flight and perch state machine, hand offer
  detection, `Meshes.blob`, `Meshes.feather`.
- `Design/Tone.swift`: cues `chirp(0...3)`, `trill`, `alarm`, `whirr`; `Tone.song` synthesizes swept syllables.
- `Stage/ImmersiveView.swift`: owns the bird, parents it to the stage, updates it each frame while the stage is on.
- `Games/Minigame.swift`: `countdown()` sets `hud.ambient = false`, so the bird leaves the hand at "3" and the
  clouds freeze 2.6 s earlier than before.
- `App/SpatialAgeApp.swift`: DEBUG `-birdpreview YES` opens the stage with the bird perched in front.
- `specs/games/design.md`: new Bird section; the Stage line on motion is updated.

Design conflict: the spec kept every moving or saturated object away from play so that motion in view is a game
signal. The bird is saturated yellow and moves during trials. To limit the effect on reaction-time scores it is
silent during trials, cannot land, and flies 13 to 17 m out and 6 to 8.5 m up (about 0.9 degrees). Whether a
far moving bird changes reaction times is unmeasured. Hiding it during trials means changing the far ring in
`Bird.pickWaypoint`.

Tuning constants on device: offer thresholds in `Bird.offer` (palm normal y > 0.55, middle tip to wrist > 12 cm,
28 cm reach), `offerHold` 0.3 s, `loseHold` 0.3 s, `startle` 1.7 m/s.
