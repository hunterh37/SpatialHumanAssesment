# Music bed

Five tracks ship here: `music-golden-hour-1.mp3` to `-5.mp3`. To add or replace one, drop it into this folder and build. No code or `project.yml`
change: XcodeGen bundles any audio file under `Sources`, flattened into the app bundle root.

- **Name:** `music-<title>-<n>.m4a`, for example `music-golden-hour-1.m4a`, `music-golden-hour-2.m4a`.
  Lowercase, starts with `music-`. Anything else in the bundle is ignored by the music bed.
- **Formats:** m4a (AAC, 128 to 192 kbps keeps the app small), mp3, wav, aif, caf.
- **Title:** the Home mini-player shows the name without `music-`, a trailing number and the extension,
  in title case: `music-golden-hour-1.m4a` reads "Golden Hour". `music-1.m4a` falls back to "Golden Hour".
- **Length:** 2 to 4 minutes each. Tracks shorter than 12 s get a shorter crossfade.
- **Playback:** all tracks, shuffled, endless, never the same track twice in a row. Plays constantly at a low
  level: 0.2 on menus and results, 60% of that during a game so spatial cues stay clear. The level eases
  between the two over 3 s. A track that ends crossfades into the next over 4 s.
- **Game transitions:** entering a game, moving to the next game, and leaving the last one each slide to a
  new track over an 8 s equal-power crossfade, so the change is barely noticeable. A crossfade already
  running is left to finish, never stacked.
- **Silence:** only while Sky Plank is shown (it plays its own wind): fades out in 0.5 s, back in over 1.5 s.
- **No tracks:** the bed stays silent and the mini-player hides.
- **Listener choice:** play/pause on the mini-player is saved in UserDefaults `music.enabled`, default on.
  Launch with `-music.enabled NO` to start with it off.

This README is bundled with the app as a plain resource. It is harmless.
