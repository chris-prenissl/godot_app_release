# Skill: verify the release setup

Run these before a release, or when a release failed for a reason that looks environmental.
All of them are read-only.

## Tools

```sh
ruby --version      # must be 3 or newer; macOS's system Ruby 2.6 cannot run fastlane
bundle --version
bundle exec fastlane --version
xcodebuild -version # iOS only, macOS only
```

If Ruby or Bundler is missing from a command the plugin runs but works in your shell, the
editor's `PATH` is the problem — the fix is `extra_path_entries` in `release_config.tres`.

## Project files

```sh
ls export_presets.cfg release_config.tres Gemfile fastlane/Fastfile
bundle check                      # are the gems installed
grep -c . fastlane/.env           # exists and is non-empty — do NOT print its contents
```

Missing `Gemfile` or `fastlane/` means the plugin's *Install release scripts* button was
never pressed.

## Targets

```sh
godot --headless --path . \
    --script addons/app_release/scripts/ci_release.gd -- --list
```

Every target that prints here loaded and parsed. To validate one fully — preset exists, store
allowed for the platform, lane set, artifact path resolvable, iOS native project present —
write its run configuration without releasing:

```sh
godot --headless --path . \
    --script addons/app_release/scripts/ci_release.gd -- \
    --target <id> --version 0.0.1 --build 1
```

Exit 0 means the target is releasable. **This patches `export_presets.cfg`**, so use the
project's real current version and build number, or restore the file afterwards
(`git checkout export_presets.cfg`).

## Credentials

Check that the variables *exist*, never what they contain:

```sh
grep -oE '^[A-Z_]+=' fastlane/.env
```

| Variable | Needed for |
|---|---|
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` | TestFlight, App Store |
| `PLAY_JSON_KEY_PATH` | Google Play |
| `FIREBASE_APP_ID_ANDROID` | Firebase App Distribution |
| `FIREBASE_SERVICE_CREDENTIALS` | Firebase, optional |

The `*_PATH` and `*_CREDENTIALS` variables point at files; `test -f "$(...)"` is a fair check,
reading the file is not.

## Android signing

Godot reads the release keystore from the editor's own settings, which a headless run does
not have. For a release build outside the editor, these must be set:

```
GODOT_ANDROID_KEYSTORE_RELEASE_PATH      absolute path — the shell will not expand ~
GODOT_ANDROID_KEYSTORE_RELEASE_USER
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
```

Set all three or none — a partial `GODOT_ANDROID_KEYSTORE_*` group can break the export.

## The editor's own checklist

The Setup tab in the Release panel runs all of the above and renders it as a list with fix
hints. When you can, ask the user to open it rather than guessing from a shell.
