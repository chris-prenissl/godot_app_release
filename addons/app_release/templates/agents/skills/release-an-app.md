# Skill: release an app

Everything the plugin's Release panel does is available from the command line, so an agent
can drive it without the editor UI. Two commands: one writes the configuration, the other
builds and uploads.

> **Confirm first.** An upload cannot be undone and a build number cannot be reused. Get the
> target, version and build number from the user before running anything in this file.

## 1. See what can be released

```sh
godot --headless --path . \
    --script addons/app_release/scripts/ci_release.gd -- --list
```

Prints the target ids defined in `release_config.tres`, e.g. `testflight_ios`,
`firebase_android`, `play_internal`, `play_production`. Use `--help` for the full argument
list.

## 2. Write the run configuration

```sh
godot --headless --path . \
    --script addons/app_release/scripts/ci_release.gd -- \
    --target testflight_ios --version 1.4.0 --build 57
```

Optional: `--notes-file <path>`, `--groups <a,b>` (TestFlight / Firebase tester group
aliases), `--debug` (debug template; refused for App Store and Google Play).

This validates the target, patches the version into `export_presets.cfg` and writes
`.release_tools/run_<target>.env`.

| Exit | Meaning |
|---|---|
| 0 | `run.env` written |
| 1 | the target is misconfigured, or a file could not be written |
| 2 | bad invocation |

Stop here if it is non-zero — nothing has been uploaded, and the message says what to fix.

## 3. Build and upload

```sh
bash addons/app_release/scripts/release.sh \
    .release_tools/run_testflight_ios.env logs/agent.log
```

Takes minutes. It exports the preset (running `xcodebuild` for iOS), then calls
`fastlane <platform> <lane>`. Run it in the background and tail `logs/agent.log`; the exit
code also lands in `logs/agent.log.exit`.

An optional third argument runs one phase only:

```sh
bash addons/app_release/scripts/release.sh .release_tools/run_testflight_ios.env logs/agent.log export
bash addons/app_release/scripts/release.sh .release_tools/run_testflight_ios.env logs/agent.log upload
```

`upload` reuses the artifact an earlier `export` produced — the fast way to retry a failed
upload without rebuilding.

## Choosing version and build number

- **Version name** is user-visible (`1.4.0`). Only change it when the user says so.
- **Build number** must increase for every upload, and can never be reused — Apple and Google
  both reject a duplicate.
- The current values are in `export_presets.cfg` under the preset's options
  (`application/short_version` + `application/version` on iOS, `version/name` +
  `version/code` on Android).
- What the store has already seen is in the panel's release list; from the command line, the
  safe move is to ask the user rather than guess.

## Release notes

Write them to a file and pass `--notes-file`. They become the TestFlight changelog, the
Firebase release note and the Google Play changelog, and are archived to
`release-notes/<version>-<build>.md`.

The App Store lane deliberately uploads the build only — "What's New" is written in App Store
Connect, because pushing metadata would overwrite the whole listing.

## Which target to pick

| Target | Reaches | Safe to automate |
|---|---|---|
| `testflight_*` | your testers | yes, with confirmation |
| `firebase_*` | your tester groups | yes, with confirmation |
| `play_internal` | the internal testing track | yes, with confirmation |
| `app_store_*`, `play_production` | **real users** | only on explicit instruction |

## Before you start

Run [verify-release-setup](verify-release-setup.md) if you are not sure the machine is ready.
If a run fails, go to [troubleshoot-a-release](troubleshoot-a-release.md).
