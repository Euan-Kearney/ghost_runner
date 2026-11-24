# Field Test 1: First iOS Build

**Date:** 24/11
**Platform:** iOS
**Build:** First build of Ghost Runner

## Purpose

This was the first field test of the app on iOS. It checked three things:

1. **UI:** does the interface built on Windows look and work the same on iOS?
2. **GPS:** does the app track the runner's position and progress along the route correctly?
3. **Audio:** does the ghost's 3D audio (footsteps, breathing, muffling, overtake sounds) work on a real device?

The test was also used to decide which features are must-haves for the next phase of the project.

## Setup

- **Route:** one of my previous runs, exported from Strava as a GPX file.
- **Ghost pace:** 07:30 /km (set pace, a brisk jog).

## Results

Overall, the app worked as intended, and much as it does in dummy test runs on Windows.

| Area | Result | Notes |
|------|--------|-------|
| UI | Pass | Matched how it looks and works on Windows. |
| GPS | Pass | My location was plotted accurately on the map. |
| 3D audio | Pass, needs tuning | Directional audio worked, but some sounds were too quiet (see below). |

### Audio issues

- **Footsteps are too quiet**, both when the ghost is in front and when it is behind. They should be louder overall, for example by raising the gain of the `Footsteps.mp3` asset.
- **Muffled breathing is too quiet when the ghost is behind.** The low-pass muffling plus the current `behindGain` boost isn't enough to make up the difference.

## Next steps

### Fixes

1. Make the footsteps louder, in front and behind.
2. Make the breathing louder when the ghost is behind.

### Proposed Features

1. **Heartbeat when neck and neck:** play a looping heartbeat while the ghost and the runner are within 15 m of each other, to make close racing more exciting.
2. **Start-position check:** before the run starts, check that the runner is near the route's first waypoint.
3. **Results screen:** when the run finishes, show the ghost's time and the runner's time.
4. **Victory screen:** if the runner beat the ghost, show a screen congratulating them.
