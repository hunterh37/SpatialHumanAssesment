# Menu music

Drop the Suno tracks (working title "Golden Hour") into this folder and build. No code or `project.yml`
change: XcodeGen bundles any audio file under `Sources`, flattened into the app bundle root.

- **Name:** `music-<title>-<n>.m4a`, for example `music-golden-hour-1.m4a`, `music-golden-hour-2.m4a`.
  Lowercase, starts with `music-`. Anything else in the bundle is ignored by the music bed.
- **Formats:** m4a (AAC, 128 to 192 kbps keeps the app small), mp3, wav, aif, caf.
- **Title:** the Home mini-player shows the name without `music-`, a trailing number and the extension,
  in title case: `music-golden-hour-1.m4a` reads "Golden Hour". `music-1.m4a` falls back to "Golden Hour".
- **Length:** 2 to 4 minutes each. Tracks shorter than 12 s get a shorter crossfade.
- **Playback:** all tracks, shuffled, endless, 4 s crossfade, level 0.35. One track alone loops into itself.
- **Silence:** fades out in 0.5 s while a game block runs (practice or scored) and while Sky Plank is
  shown. Fades back in over 1.5 s on menus and results. Audio never cues timing.
- **No tracks:** the bed stays silent and the mini-player hides.
- **Listener choice:** play/pause on the mini-player is saved in UserDefaults `music.enabled`, default on.
  Launch with `-music.enabled NO` to start with it off.

This README is bundled with the app as a plain resource. It is harmless.
