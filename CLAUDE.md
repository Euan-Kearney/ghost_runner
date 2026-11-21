# Ghost Runner

A running app where you race a "ghost": looping footstep audio placed in 3D space where the ghost would be right now. The ghost follows a route from an uploaded GPX file, either at a target pace the user sets (mm:ss per km) or at the original run's pace (racing a previous run). You hear the ghost ahead of you, behind you, or to the side, louder as it gets closer.

## Layout

- `back-end/`: Node + Express server (CommonJS). Turns a GPX file into the ghost's positions.
  - `server.js`: one endpoint, `POST /api/runs/upload` (multipart: `gpxFile`, `pace`, `dummyRoute`). Port 3000.
  - `process_route.js`: GPX → GeoJSON (`togeojson` + `xmldom`), then builds the route. `RouteError` = bad user input → 400.
  - Tests: `*.test.js` (Jest).
- `front-end/ghost_runner/`: Flutter app (Android/iOS/desktop/web scaffolding is stock).
  - `lib/main.dart`: whole UI and run loop in one `HomePage` state.
  - `lib/run_math.dart`: pure geometry/audio helpers (`displacement`, `getVolume`, `lowPassCutoff`, `bearing`, `isValidPace`, `toPoints`). Tested in `test/run_math_test.dart`.
  - `assets/audio/`: `Footsteps.mp3` and `breathing.wav` (used; breathing is CC0 "Breathing Tired" from OpenGameArt, mono, +12dB), `ghost_overtake.mp3` / `runner_overtake.mp3` (added, not wired up yet).
  - `tool/overtake.dart`: renders an overtake to mp3 using the app's audio maths (`dart run tool/overtake.dart --speed=4`; options in the file header). Needs ffmpeg.
- `scripts/dev.sh`: starts the backend, then `flutter run` with any extra args.

## How a run works

1. App uploads the GPX plus pace (`"00:00"` = original pace) to the server.
2. Server returns `route`: `[lon, lat]` ghost positions, **one per 50ms tick**.
   - Original pace: interpolate by GPX timestamps, then smooth the pace over 50m segments (total time unchanged). Needs timestamps.
   - Set pace: walk the track at constant speed.
   - `dummyRoute=true` also returns `runnerRoute`: the original run at 1 point/second, which the app replays as a fake runner for desk testing (no GPS).
3. App ticks every 50ms, indexing the route by **elapsed wall time** (not tick count) so timer jitter doesn't make the ghost lag.
4. Each tick: offset from runner to ghost, rotated into the runner's frame (`[right, forward]` metres, using GPS heading), drives `flutter_soloud` 3D position (listener faces -z, so forward = -z), volume (footsteps: 1 within 2m, 0 at 100m; breathing: 0 at 40m) and a per-sound low-pass filter (`lowPassCutoff`: clear ahead, muffled behind, since stereo panning alone can't tell front from back). Per-sound filters don't work on web, so no muffling there.

## Invariants to keep in sync

- Tick length: `TICK_SECONDS` in `process_route.js` and `_tick` in `main.dart` must match (50ms).
- Pace format: `parseSpeed` (JS) and `isValidPace` (Dart) must accept the same strings.
- Points are always `[longitude, latitude]` (GeoJSON order), not lat/lon.
- Distances use a flat-earth approximation; fine at running scale.

## Commands

```bash
bash scripts/dev.sh                 # backend + app (on Windows use Git Bash)
bash scripts/dev.sh -d chrome
bash scripts/dev.sh -d emulator-5554 --dart-define=API_URL=http://10.0.2.2:3000   # Android emulator
cd back-end && npm test             # Jest
cd back-end && npx eslint .
cd front-end/ghost_runner && flutter test
cd front-end/ghost_runner && flutter analyze
```

The app reads the server URL from `--dart-define=API_URL=...` (default `http://localhost:3000`). On a real phone use the computer's LAN IP.

## Conventions

- Keep it small: pure logic goes in `run_math.dart` / `process_route.js` with a test; `main.dart` stays the only widget file unless it gets unwieldy.
- Known shortcuts are marked with `shortcut:` comments.
