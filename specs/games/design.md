# Minigame design

Code: `apps/vision/SpatialAge/Sources/Design`.

## Stage

Full immersion. Ink sky dome (#0B0F17), a faint horizon band at eye level, a 6 m floor disc with hairline rings every meter and 12 spokes. Nothing in the environment moves, so any motion in view is a game signal. Hands stay visible (`upperLimbVisibility(.visible)`). Everything sits at life scale within arm reach of the dominant shoulder.

## Color

| Token | Hex | Meaning |
|---|---|---|
| go | #2F6BFF | touch it |
| nogo | #FF7A3D | leave it |
| gold | #FFC83D | catch, memory |
| teal | #14B8A6 | follow |
| paper | #F6F4EF | text, contact flash |
| mute | #8A8F99 | at rest, missed |

## Micro-interactions

Five primitives in `MicroInteractions.swift`. Games use these and nothing else.

| Primitive | Behavior | Why |
|---|---|---|
| Breathe | live target scales 1.00 to 1.03 at 0.5 Hz | shows the target is touchable |
| Proximity glow | emissive 0.6 + 2.4 c^2, c = closeness inside 30 cm | feedforward as the finger lands |
| Contact pop | 90 ms scale 1 to 1.25 to 0, ring to 3x radius over 240 ms, tick pitched by reach speed | confirms contact, rewards speed with pitch |
| Miss sink | 250 ms desaturate, drop 3 cm, fade, soft low tone | a miss reads as quiet, never as punishment |
| Release snap | cord shortens and fades in 120 ms with a low tock | marks the pendulum release instant |

Appearance is 60 ms, so spawn time stays exact to a frame. Spawn time is the first frame the target is in the scene.

## Sound

Procedural sine partials with exponential decay, rendered to WAV once (`Tone.swift`) and played spatially from the entity. Contact pitch steps 0 to 6 over reach time 0.9 to 0.3 s. Constellation stars sit on a pentatonic scale. Spark, Gate and Reach and Grab targets play a spawn cue from where they appear: a 30 ms noise click over a short tone, because broadband onsets are what the ear localizes, so the participant hears which way to turn. Gate plays it from both orbs, so the sound never tells blue from orange.

## No score in play

The HUD shows title, one instruction line, a cue line and progress dots. Numbers appear only on the results screen. Timed games (Pendulum, Spark, Gate, `Game.isTimed`) say "as fast as you can" in the instruction, and the scored block adds "You are timed." Every block opens with a 3, 2, 1, Go countdown on the cue line (0.7 s per digit, tock per digit) and closes with praise for 1.4 s. Spark and Gate show a short praise word for 0.8 s after each blue touch, and Gate shows "Good, you left it." after each no-go trial left alone. Pendulum is the exception: the ruler marks the catch height, the way the classic ruler drop reads.
