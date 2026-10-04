# Sky Plank

Status: builds for visionOS 26 (Debug, simulator). Runs in the visionOS 26.2 simulator with `-skyplank YES`.
Not run on device.

RealForge (RealityHD), uncommitted, branch v5-medical:
- `Sources/RealLibrary/Scenes/RooftopPlank.swift`, scene id `rooftop-plank`, registered in `SceneCatalog`.
  Two 40-storey `OfficeBlock` towers (24 x 24 m, 154 m) set corner to corner with a 4.6 m gap. A 0.30 x 0.05 m
  `wood.weathered` board rests on both parapet copings, with a boarded galvanized deck on each roof at the same
  height. Around them is a 640 m radius grid of instanced office blocks in 9 height variants and 4 facade
  looks. Blocks within 120 m of the towers stay at 16 floors or less so the drop stays in view, and towers up
  to 56 floors stand at the edge of the skyline. The grid has paving-slab lots, asphalt far ground, lane
  markings and about 2,000 box cars. No trees. Sun at 34 deg, fog 0.0022 per meter.
- `OfficeBlock`: new `glassMaterial`, `frameMaterial`, `spandrelMaterial` vars. Defaults are unchanged.
- `docs/scenes/rooftop-plank.png` and `CATALOG.md` are regenerated.
- `realityhd perf rooftop-plank`, balanced tier: 647k tris, 390 draws. For comparison, ballpark is 3,537k
  tris and 936 draws, and office-plaza is 300k tris and 96 draws. Battery tier: 69k tris, 33 draws.
  The first version had 1,091k tris and 2,084 draws. Cars changed from rounded boxes to 24-triangle boxes,
  and the instancing cells for the block fields grew from 150 m to 640 m.

SpatialAge:
- `Design/SkyPlank.swift`. Builds the scene off the main actor and adds a 2,500 m sky dome, the sun and IBL.
  It places the near end of the board under the participant's feet, pointing the way they face. Wind is a
  16 s procedural loop with a crossfaded seam, played as ambient audio at -14 dB.
- `AppModel.skyPlank`. The "Sky Plank" button sits next to the anatomy picker in the main window. Inside the
  space, "Leave the roof" uses the same two-tap exit as the games. Starting a game session turns Sky Plank off.
- Launch arg `-skyplank YES`.

Physical space: the walk is 0.6 m of deck, then 4.94 m of board, then 3.4 m of deck. At least 6 m of clear,
straight floor is needed in full immersion. The board's start is placed when Sky Plank opens, so the
participant must stand at the start of the clear run, facing along it, before tapping the button.

Known gaps: Debug builds compile RealityHD unoptimized, so the first load takes several seconds and frame
rate on device is unmeasured. Neither tower has lit ceilings at the viewer's distance (LOD1). Distant blocks
use LOD2 boxes with no mullions. Nothing in the scene detects stepping off the board.
RealForge `swift test --filter "SceneTests|AssetContractTests"`: exit 0.
