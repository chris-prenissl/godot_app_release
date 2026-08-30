# Skill: troubleshoot a release

## Where the evidence is

| Path | What |
|---|---|
| `logs/release_<target>_<timestamp>.log` | The whole run: export, `xcodebuild`, fastlane |
| `logs/<log>.exit` | The exit code. A missing one means the process died without a status |
| `logs/.release.lock.<target>/pid` | A run in flight |
| `.release_tools/run_<target>.env` | The exact configuration that run used |
| `.release_tools/releases_<store>.json.err` | Full stderr of a failed **Fetch** |

Read in that order: the last ~40 lines of the newest log first — the script dies with a
sentence naming what was missing.

## Re-run without rebuilding

`run.env` is still on disk after a failure, so a fixed credential or lane can be retried
directly:

```sh
bash addons/app_release/scripts/release.sh .release_tools/run_<target>.env logs/retry.log upload
```

`upload` reuses the artifact from the failed attempt. Use `all` (or omit the argument) if the
export itself was the problem.

The version is **not** patched by this script — the panel and `ci_release.gd` do that. Editing
`VERSION` inside `run.env` alone will not reach the export.

## Common failures

| Message | Cause | Fix |
|---|---|---|
| `another release is already running (pid N)` | A live run holds the lock | Wait, or stop it. A stale lock clears itself once the owning process is gone |
| `expected artifact missing after export` | The export wrote somewhere else | Compare `ARTIFACT_PATH` in `run.env` with the preset's `export_path` |
| `BUILD_MODE=GODOT_EXPORT cannot work for iOS` | A Godot iOS export produces an `.xcodeproj`, never an `.ipa` | Set the target's build mode to *Regenerate native project* or *PCK only* |
| `no Gemfile in …` | The plugin's *Install release scripts* was never pressed | Press it, or run `bundle install` |
| `The provided entity includes an attribute with a value that has already been used` | Duplicate iOS build number | Bump the build number |
| `Version code N has already been used` | Duplicate Android `versionCode` | Bump the build number |
| `No suitable application record was found` | The App Store Connect app record does not exist, or the bundle id differs | Create it in App Store Connect |
| `The caller does not have permission` | The Play service account has no access to the app | Grant it in the Play Console |
| `Firebase denied access to app …` | Service account lacks *Firebase App Distribution Admin*, or App Distribution is not enabled | Fix the role in Google Cloud |
| Ruby/Bundler/fastlane "not found" | The editor's minimal `PATH` | Add the directory to `extra_path_entries` in `release_config.tres` |

## What not to do

- Do not print or paste the contents of `fastlane/.env`, a `.p8`, a service-account `.json` or
  a keystore into the conversation, a log or a commit — a failing credential is reported by
  **name**.
- Do not raise the build number "to be safe" without saying so; every number is spent forever.
- Do not delete `logs/` while a release is running — the panel reads the `.exit` file from
  there.
