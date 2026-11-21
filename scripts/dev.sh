#!/usr/bin/env bash
# Starts the backend, then runs the Flutter app. The backend stops when the app exits.
# Extra arguments go to `flutter run`, e.g.
#   bash scripts/dev.sh -d chrome
#   bash scripts/dev.sh -d emulator-5554 --dart-define=API_URL=http://10.0.2.2:3000
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"

[ -d "$root/back-end/node_modules" ] || npm --prefix "$root/back-end" install

# Run node directly (not `npm start`) so killing $backend kills the server itself.
node "$root/back-end/server.js" &
backend=$!
trap 'kill $backend 2>/dev/null' EXIT

cd "$root/front-end/ghost_runner"
flutter run "$@"
