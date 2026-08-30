# Skill: debug a failed release

## Where the evidence is

| Path | What |
|---|---|
| `logs/release_<target>_<timestamp>.log` | The whole run: export, xcodebuild, fastlane |
| `logs/release_*.log.exit` | The exit code. **This** is what the panel reads |
| `logs/.release.lock.<target>/pid` | Lock of a run in flight, one per target |
| `.release_tools/run_<target>.env` | The exact configuration the run used |
| `.release_tools/config.json` | Identity data handed to `list_releases.rb` |
| `.release_tools/releases_<store>.json.err` | Full stderr of a failed **Fetch** |

Logs rotate: the newest `keep_logs` (default 20) survive.

## Read it in this order

1. The last 40 lines of the log — the script prints `=== RELEASE <target> FAILED (exit N)`
   and dies with a sentence saying what was missing.
2. `.exit` — a missing one means the process disappeared without writing a status (killed,
   or the machine slept). The panel reports "exited without a status".
3. `run_<target>.env` — an empty `KEY=""` where you expected a value means the field never
   made it out of GDScript. See [add-a-target-field](add-a-target-field.md).

## Re-run without the editor

`run.env` is still on disk, so the failed run can be repeated after fixing a credential or a
lane:

```sh
addons/app_release/scripts/release.sh .release_tools/run_<target>.env logs/manual.log
```

Optional third argument: `export`, `upload` or `all` (default). `upload` skips straight to
fastlane, reusing the artifact the export already produced — the fast way to retry a failed
upload.

Note the version is **not** patched by the script: the panel does that before it starts.
Editing `VERSION` in `run.env` alone will not reach the export.

## Common failures

**"another release is already running (pid N)"** — a live run holds
`logs/.release.lock.<target>`. The script clears a stale lock itself once the owning process
is gone; delete the directory if it persists.

**"expected artifact missing after export"** — the export succeeded but wrote somewhere
else. Compare `ARTIFACT_PATH` in `run.env` with the preset's `export_path`.

**"BUILD_MODE=GODOT_EXPORT cannot work for iOS"** — a Godot iOS export produces an
`.xcodeproj`, never an `.ipa`. Pick a build mode that runs `xcodebuild`.

**Ruby / Bundler / fastlane "not found" in the Setup tab** — the editor starts children with
a minimal `PATH`. `AppReleaseShell.build_ruby_paths_sorted_by_usability()` probes the usual
locations (Homebrew, rbenv, rvm, asdf); anything unusual goes into `extra_path_entries` in
`release_config.tres`.

**Duplicate build number** — the store rejects a build number it has already seen. Press
**Fetch** on that column to see what is taken.

**Fetch shows a red error** — the short version is in the log pane, the full stderr in
`.release_tools/releases_<store>.json.err`.

## While reproducing

`OS.create_process` gives no console. To watch a run, either use the panel's live log, or
run `release.sh` yourself as above — it prints to stdout as well as to the log file.
