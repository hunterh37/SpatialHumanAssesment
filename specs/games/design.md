# Minigame design

Code: `apps/vision/SpatialAge/Sources/Design`.

## Stage

Full immersion. Ink sky dome (#0B0F17), a faint horizon band at eye level, a 6 m floor disc with hairline rings every meter and 12 spokes. From the countdown to the end of each block (`HUD.ambient` false) the clouds freeze and the bird keeps to its far ring, so motion near the targets is always a game signal. Hands stay visible (`upperLimbVisibility(.visible)`). Everything sits at life scale within arm reach of the dominant shoulder.

## Scenery

`Design/Scenery.swift`. Stick Drop and Spatial Tracking add a forest clearing inside the stage: pale sky dome (30 m), grass floor, two still rings of trees at 5 to 8 m and 10 to 14 m, fixed layout. Hole in the Wall adds a stone island and a moat to it. Scenery is unlit and muted, so the game colors stay the only saturated things in view.

## Bird

`Design/Bird.swift`, owned by `ImmersiveView` and parented to the stage, so it appears in every game and hides with the stage (passthrough, Sky Plank). A yellow canary at life size (body 12 cm, wingspan about 22 cm), procedural meshes: egg body, pale belly, large round head, glossy eyes with two catchlights, blush, hinged bill, crest tuft, two-segment wings with 21 feathers each, six-feather tail, legs with four toes.

| State | Behavior |
|---|---|
| Wander (ambient) | bounding finch flight, 0.5 s of flaps at 12 Hz then a 0.35 s tucked bound, loops 2.6 to 4.8 m out and 1.7 to 3.1 m up; a flight call every 5 to 10 s |
| Called | a hand held out (over 28 cm from the head, horizontally), open, palm up, above eye height minus 75 cm and still (palm under 0.4 m/s) for 0.3 s; the bird answers with a call and flies to a point 0.7 m beyond the hand, then in |
| Land | 0.32 s flare: pitched up, 15 Hz hover beats, tail spread, legs out |
| Perch | rides the palm, faces the participant, body nose-up 14 degrees; breathes, blinks every 1.8 to 5 s, saccadic head turns with curious tilts, hops and turns every 4 to 8 s, tail flicks, calls every 2.5 to 6 s with the bill opening; wings flutter for balance when the hand moves over 0.35 m/s |
| Petted | the other hand's fingertip within 5 cm of the head or back: eyes squint, feathers puff, head leans toward the finger, a trill; a fast poke (over 0.9 m/s) makes it hop with an alarm call |
| Leave | the offer lapses for 0.3 s (palm turned down, hand closed, lowered or untracked): calm takeoff with a wing whirr; palm over 1.7 m/s: startled takeoff with an alarm call; 1 to 2 s before it can be called again |
| Trials (ambient false) | leaves the hand at the countdown, no sound, bounding loops 13 to 17 m out and 6 to 8.5 m up (about 0.9 degrees of visual angle) |

Bird calls are swept sines (`Tone.Cue.chirp`, `.trill`, `.alarm`) at -20 to -26 dB. Bird yellow (#F5D547, belly #FBE7A1) is scenery and carries no meaning. Debug launch argument `-birdpreview YES` opens the stage with the bird perched in front.

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

Five primitives in `MicroInteractions.swift`, plus the reward layer below. Games use these and nothing else.

| Primitive | Behavior | Why |
|---|---|---|
| Breathe | live target scales 1.00 to 1.03 at 0.5 Hz | shows the target is touchable |
| Proximity glow | emissive 0.6 + 2.4 c^2, c = closeness inside 30 cm | feedforward as the finger lands |
| Contact pop | 90 ms scale 1 to 1.25 to 0, ring to 3x radius over 240 ms, tick pitched by reach speed | confirms contact, rewards speed with pitch |
| Miss sink | 250 ms desaturate, drop 3 cm, fade, soft low tone | a miss reads as quiet, never as punishment |
| Release snap | cord shortens and fades in 120 ms with a low tock | unused since Stick Drop, which plays the tock alone |

Appearance is 60 ms, so spawn time stays exact to a frame. Spawn time is the first frame the target is in the scene.

## Rewards

`Design/Juice.swift`, owned by `Micro` and fired from the success paths after the outcome is recorded.

| Event | Effect |
|---|---|
| Success (go touch, catch, grab, cleared wall, clean recall, correct sequence, pursuit end) | a soft halo that swells to 5 to 8 cm and fades over 0.35 s, a spark burst from the contact (10 sparks plus 4 per tier, 0.6 s, drag and light gravity), an extruded 3D praise word that springs in and rises 10 cm over 0.85 s, a bell arpeggio (`Tone.Cue.chime`) on top of the speed-pitched tick |
| Partial success (each recalled ball before the last, the second wall ring) | halo and a 6-spark burst; no word, no chime, streak unchanged |
| Streak | consecutive successes in a block: tiers at 3, 5 and 8 lift the chime register, add sparks and twinkles (`.sparkle`) and pick stronger words. Shown as a word, never a count |
| Wrong touch, miss, timeout | streak resets; nothing else changes (miss sink keeps its quiet tone) |
| Correct no-go | no reward, as before |
| End of block | confetti and burst 1.1 m ahead at eye height; scored blocks add the fanfare (`.fanfare`) |
| HUD cue | each new cue springs 1.0 to 1.22 to 1.0 with a soft gold glow |

One 3D word is in view at a time; a new word replaces the old one. Safety: effects stay within about 25 cm of the contact, never fill the view, flash once per success and fade over at least 250 ms. Reduce Motion keeps at most 6 still sparks, a word that fades in place and no cue bounce. Rewards never hold the trial loop.

## Sound

Procedural sine partials with exponential decay, rendered to WAV once (`Tone.swift`) and played spatially from the entity. Contact pitch steps 0 to 6 over reach time 0.9 to 0.3 s. Constellation stars sit on a pentatonic scale. Spark, Gate and Reach and Grab targets play a spawn cue from where they appear: a 30 ms noise click over a short tone, because broadband onsets are what the ear localizes, so the participant hears which way to turn. Gate plays it from both orbs, so the sound never tells blue from orange. Two cues add sound beyond sines: a filtered-noise rustle (Spatial Tracking audio cue) and a 2.2 s low hum with a 3 Hz wobble (Scary Balance creature).

## No score in play

The HUD sits low in front of the participant: 1.4 m out, centered 0.5 m below eye height (about 20 degrees down), re-placed at each game start from the head pose (`Theme.Layout`). It is past arm's reach, so targets and leaves pass in front of it. The in-space exit button sits 0.8 m below eye height at the same distance. The main window closes when a session starts, so nothing covers the stage, and reopens when the session finishes, is ended, or the space closes.

The HUD shows title, one instruction line, a cue line and progress dots. Numbers appear only on the results screen. Timed games (Stick Drop, Spatial Tracking, Gate, `Game.isTimed`) say "as fast as you can" in the instruction, and the scored block adds "You are timed." Every block opens with a 3, 2, 1, Go countdown on the cue line (0.7 s per digit, tock per digit) and closes with praise for 1.4 s. Gate shows a short praise word for 0.8 s after each blue touch, and Gate shows "Good, you left it." after each no-go trial left alone. Stick Drop and Spatial Tracking praise each catch or touch the same way.
