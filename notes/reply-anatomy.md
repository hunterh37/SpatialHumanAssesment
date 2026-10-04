# Hand anatomy overlay

Status: builds for visionOS 26 (Release and Debug). Not run on device. Simulator has no hand
tracking, so it falls back to two demo hands; offline renders are `realityhd anatomy` in RealForge
(`out/anatomy/*.png`).

Code:
- RealForge (RealityHD), uncommitted, on branch v5-medical next to existing WIP:
  `Sources/RealCore/Anatomy/*` (pose, frames, morphometry, bone loft, bones, soft tissue),
  `Sources/RealMaterials/{Library/Anatomy.swift,Shaders/AnatomyShaders.swift}` (6 texture programs,
  12 materials), `Sources/RealKit/HandAnatomy.swift` (`RealHandAnatomy`, x-ray shader graph),
  `Sources/realityhd/Anatomy.swift`, `Tests/RealityHDTests/AnatomyTests.swift` (4 pass).
- SpatialAge: `Anatomy/AnatomyOverlay.swift`, tracker keeps all 27 joints, Off/X-ray/Muscle/Both
  segmented control at the top of the main window, opens the space in passthrough when no game runs.
  Deployment target raised 2.0 -> 26.0 (RealityHD requires it). Launch arg `-anatomy both`.

Data honesty: geometry is procedural, no scanned mesh. Bone lengths use Buchholz et al. 1992 ratios
scaled to each tracked bone; widths, carpals, muscle and vessel routes are approximations from
Gray's/Netter, not a measured dataset. Swapping in BodyParts3D or Z-Anatomy meshes (CC BY-SA) would
need skinning and breaks RealityHD's no-mesh-files rule.

Known gaps: Debug builds compile RealityHD unoptimized; per-frame soft-tissue rebuild may drop frames
in Debug on device. Joint axis conventions from ARKit are not used (frames come from positions), so
thumb twist is inferred.
