# Minigame design

Code: `apps/vision/SpatialAge/Sources/Design`.

## Stage

Full immersion. Ink sky dome (#0B0F17), a faint horizon band at eye level, a 6 m floor disc with hairline rings every meter and 12 spokes. Nothing in the environment moves, so any motion in view is a game signal. Hands stay visible (`upperLimbVisibility(.visible)`). Everything sits at life scale within arm reach of the dominant shoulder.

## Scenery

`Design/Scenery.swift`. Stick Drop and Spatial Tracking add a forest clearing inside the stage: pale sky dome (30 m), grass floor, two still rings of trees at 5 to 8 m and 10 to 14 m, fixed layout. Hole in the Wall adds a stone island and a moat to it. Scenery is unlit and muted, so the game colors stay the only saturated things in view.

## Color

| Token | Hex | Meaning |
|---|---|---|
| go | #2F6BFF | touch it |
| nogo | #FF7A3D | leave it |
| gold | #FFC83D | catch, memory |
| teal | #14B8A6 | follow |
| paper | #F6F4EF | text, contact flash |
| mute | #8A8F99 | at rest, missed |
| creature | #5F3E8A | Scary Balance creature: freeze |

Scenery tokens (sky #98B0BD, grass #3B4D34, bark #3E3128, canopy #2D422E, far canopy #576D68, water #265775, stone #9E988C) carry no meaning.

## Micro-interactions

Five primitives in `MicroInteractions.swift`. Games use these and nothing else.

| Primitive | Behavior | Why |
|---|---|---|
| Breathe | live target scales 1.00 to 1.03 at 0.5 Hz | shows the target is touchable |
| Proximity glow | emissive 0.6 + 2.4 c^2, c = closeness inside 30 cm | feedforward as the finger lands |
| Contact pop | 90 ms scale 1 to 1.25 to 0, ring to 3x radius over 240 ms, tick pitched by reach speed | confirms contact, rewards speed with pitch |
| Miss sink | 250 ms desaturate, drop 3 cm, fade, soft low tone | a miss reads as quiet, never as punishment |
| Release snap | cord shortens and fades in 120 ms with a low tock | unused since Stick Drop, which plays the tock alone |

Appearance is 60 ms, so spawn time stays exact to a frame. Spawn time is the first frame the target is in the scene.

## Sound

Procedural sine partials with exponential decay, rendered to WAV once (`Tone.swift`) and played spatially from the entity. Contact pitch steps 0 to 6 over reach time 0.9 to 0.3 s. Constellation stars sit on a pentatonic scale. Two cues add sound beyond sines: a filtered-noise rustle (Spatial Tracking audio cue) and a 2.2 s low hum with a 3 Hz wobble (Scary Balance creature).

## No score in play

The HUD sits low in front of the participant: 1.4 m out, centered 0.5 m below eye height (about 20 degrees down), re-placed at each game start from the head pose (`Theme.Layout`). It is past arm's reach, so targets and leaves pass in front of it. The in-space exit button sits 0.8 m below eye height at the same distance. The main window closes when a session starts, so nothing covers the stage, and reopens when the session finishes, is ended, or the space closes.

The HUD shows title, one instruction line, a cue line and progress dots. Numbers appear only on the results screen. Timed games (Stick Drop, Spatial Tracking, Gate, `Game.isTimed`) say "as fast as you can" in the instruction, and the scored block adds "You are timed." Every block opens with a 3, 2, 1, Go countdown on the cue line (0.7 s per digit, tock per digit) and closes with praise for 1.4 s. Gate shows a short praise word for 0.8 s after each blue touch, and Gate shows "Good, you left it." after each no-go trial left alone. Stick Drop and Spatial Tracking praise each catch or touch the same way.
