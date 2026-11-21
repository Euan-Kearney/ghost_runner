# ghost_runner
Interactive running app where you can race against yourself and friends

## Running locally
From the repo root (on Windows, use Git Bash or `bash` from PowerShell):

```
bash scripts/dev.sh              # backend + Flutter app (pick a device)
bash scripts/dev.sh -d chrome    # extra args go to `flutter run`
```

Android emulator: add `--dart-define=API_URL=http://10.0.2.2:3000`. Real phone: use your computer's LAN IP.
