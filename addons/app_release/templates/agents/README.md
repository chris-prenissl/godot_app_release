# Agent guide

Notes for AI coding agents working in this project. Installed by the **App Release** Godot
plugin (*Release → Setup → Install agent skills*) and yours to edit — the plugin never
overwrites this file.

## This project

A Godot 4 project that ships to mobile stores through the
[App Release](https://github.com/chris-prenissl/godot_app_release) plugin.

| Path | What |
|---|---|
| `project.godot` | Godot project file |
| `export_presets.cfg` | Export presets. Version and build number are patched in here |
| `release_config.tres` | Release targets: preset + store + build mode |
| `fastlane/Fastfile` | Upload lanes. Yours to edit |
| `fastlane/.env` | **Credentials. Never read, print, commit or copy this file** |
| `logs/` | One log per release run, plus a `.exit` sidecar |
| `.release_tools/` | Scratch data regenerated on every run. Disposable |

## Skills

- [release-an-app](skills/release-an-app.md) — run a release from the command line
- [verify-release-setup](skills/verify-release-setup.md) — check the machine and the project
  before releasing
- [troubleshoot-a-release](skills/troubleshoot-a-release.md) — read the logs, re-run a failed
  attempt
- [godot-project-basics](skills/godot-project-basics.md) — headless Godot, presets, `res://`
  paths, `.import`

## Rules

1. **Uploading is irreversible.** A build that reaches TestFlight, App Store Connect, Google
   Play or Firebase cannot be un-sent, and a build number can never be reused. Never start a
   release the user did not ask for, and confirm the target, version and build number before
   you run it.
2. **Never touch credentials.** `fastlane/.env` and the key files it points at
   (`.p8`, service-account `.json`, keystores) stay unread and unquoted. If a value is
   missing, say which variable is missing — do not go looking for its content.
3. **Never invent a version or build number.** Ask, or read the current values out of
   `export_presets.cfg`.
4. **Prefer a test destination.** TestFlight and Firebase App Distribution reach testers;
   App Store and Google Play production reach real users. When the user is not specific, ask.
5. **A release takes minutes.** Run it in the background and tail its log rather than
   blocking on it.
