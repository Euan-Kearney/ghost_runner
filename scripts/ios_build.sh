#!/usr/bin/env bash
# Builds the iPhone app on GitHub Actions and downloads the .ipa.
# Usage: bash scripts/ios_build.sh http://<server>:3000
# Needs the GitHub CLI (gh auth login once). Then sign + install the .ipa with Sideloadly.
set -euo pipefail

API_URL=${1:?usage: bash scripts/ios_build.sh http://<server>:3000}
OUT="$(dirname "$0")/../front-end/ghost_runner/build/ios-ipa"

gh workflow run ios-build.yml -f api_url="$API_URL"
sleep 5
# shortcut: assumes the newest run is the one just started; fine unless two builds start at once.
id=$(gh run list --workflow=ios-build.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$id" --exit-status

rm -rf "$OUT"
gh run download "$id" -n ghost_runner-ipa -D "$OUT"
echo "Done: $(cd "$OUT" && pwd)/ghost_runner.ipa — drag it into Sideloadly to install."
