# Ghost Runner

A running app where you race a "ghost": looping footstep audio placed in 3D space where the ghost would be right now. The ghost follows a route from an uploaded GPX file, either at a target pace the user sets (mm:ss per km) or at the original run's pace (racing a previous run). You hear the ghost ahead of you, behind you, or to the side, louder as it gets closer.

## Layout

- `back-end/`: Node + Express server (CommonJS). Turns a GPX file into the ghost's positions.
  - `server.js`: one endpoint, `POST /api/runs/upload` (multipart: `gpxFile`, `pace`, `dummyRoute`). Port 3000.
  - `process_route.js`: GPX → GeoJSON (`togeojson` + `xmldom`), then builds the route. `RouteError` = bad user input → 400.
  - Tests: `*.test.js` (Jest).
- `front-end/ghost_runner/`: Flutter app (Android/iOS/desktop/web scaffolding is stock).
  - `lib/main.dart`: whole UI and run loop in one `HomePage` state.
  - `lib/run_math.dart`: pure geometry/audio/progress helpers (`displacement`, `getVolume`, `lowPassCutoff`, `bearing`, `isValidPace`, `toPoints`, `distanceAlong`, `waypoints`, `WaypointTracker`, `ghostOffset`, `OvertakeDetector`). Tested in `test/run_math_test.dart`.
  - `assets/audio/`: `Footsteps.mp3` and `breathing.wav` (used; breathing is CC0 "Breathing Tired" from OpenGameArt, mono, +12dB), `ghost_overtake.mp3` / `runner_overtake.mp3` (played on overtakes; ghost_overtake is CC0 "Air Woosh Move" by Almitory from OpenGameArt, trimmed to 1.1s, -1dB peak).
  - `tool/overtake.dart`: renders an overtake to mp3 using the app's audio and overtake logic (`dart run tool/overtake.dart --speed=4`; `--from=100 --to=-100` for the runner overtaking; options in the file header). Needs ffmpeg.
- `scripts/dev.sh`: starts the backend, then `flutter run` with any extra args.

## How a run works

1. App uploads the GPX plus pace (`"00:00"` = original pace) to the server.
2. Server returns `route`: `[lon, lat]` ghost positions, **one per 50ms tick**.
   - Original pace: interpolate by GPX timestamps, then smooth the pace over 50m segments (total time unchanged). Needs timestamps.
   - Set pace: walk the track at constant speed.
   - `dummyRoute=true` also returns `runnerRoute`: the original run at 1 point/second, which the app replays as a fake runner for desk testing (no GPS).
3. App ticks every 50ms, indexing the route by **elapsed wall time** (not tick count) so timer jitter doesn't make the ghost lag.
4. Progress, not position: the ghost's route is split into waypoints every 5m. `WaypointTracker` advances the runner to the closest waypoint within 15m, searching only from the last one reached up to 10 missed waypoints ahead (GPS dropouts OK, shortcuts and later laps ignored). Gap = ghost's metres along the route − runner's, eased over ~1s.
5. Each tick the ghost is played at `ghostOffset(gap, side)` = `[side × 1.5, gap]` metres `[right, forward]`: straight ahead/behind, swinging round one ear (random side, re-rolled when >20m away) as it passes. That drives `flutter_soloud` 3D position (listener faces -z, so forward = -z), volume (footsteps: 1 within 2m, 0 at 100m; breathing: 0 at 40m; up to 2× louder (`behindGain`) when behind, to offset the muffling) and a per-sound low-pass filter (`lowPassCutoff`: clear ahead, muffled behind, since stereo panning alone can't tell front from back). Per-sound filters don't work on web, so no muffling there.
6. `OvertakeDetector` plays `ghost_overtake`/`runner_overtake` when the gap changes sign, at most once per 5s (a pass that still holds after the cooldown is announced then).

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
- Write tests before writing code.
