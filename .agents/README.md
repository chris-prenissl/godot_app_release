# Agent guide — App Release

Read this before changing anything in this repository. It is the project map; the diagrams
are in [ARCHITECTURE.md](../ARCHITECTURE.md), the user documentation in
[README.md](../README.md) and [docs/](../docs/).

## What this repository is

A Godot 4 **editor plugin** that exports a mobile project and uploads it to TestFlight, the
App Store, Firebase App Distribution and Google Play using fastlane. The repository root is
a Godot project that exists only to host and test the plugin — the shipped artifact is the
`addons/app_release/` directory alone.

The logic lives in three languages, and a feature usually touches more than one:

| Language | Where | Does |
|---|---|---|
| GDScript | `addons/app_release/**.gd` | Editor UI, config resources, writes `run.env` |
| Bash / PowerShell | `addons/app_release/scripts/release.{sh,ps1}` | Exports and uploads one target |
| Ruby | `addons/app_release/scripts/list_releases.rb`, `templates/Fastfile` | Store APIs and fastlane lanes |

## Layout

```
addons/app_release/
  app_release.gd          EditorPlugin entry point; adds the "Release" main screen
  config/                 Resources you edit in the Inspector
    release_config.gd     AppReleaseConfig  — one per project
    release_group.gd      AppReleaseGroup   — a panel of the Release tab
    release_target.gd     AppReleaseTarget  — one export preset + one store
  constants/
    release_strings.gd    Every user-facing string, path literal and run.env key
  core/                   No UI, no signals; unit-tested
    environment_check.gd  The Setup checklist
    export_presets_reader.gd  Read-only access to export_presets.cfg
    shell.gd              The only class that knows the OS
    run_files.gd          Writes .release_tools/run.env and config.json
    scaffolder.gd         Creates release_config.tres and the fastlane files
    version_patcher.gd    Rewrites a version into export_presets.cfg
    ui_layout.gd          HSplitContainer chain helper
  ui/                     Built in code; there are no .tscn files
    release_dock.gd       The Release + Setup tabs; owns the workers
    group_box.gd          One group panel
    target_column.gd      One target column
    setup_panel.gd        The Setup tab
    checklist_row.gd      One checklist row
    log_tabs.gd           One log tab per target
    release_batch_runner.gd  Starts processes, polls logs and .exit files
    batch_plan.gd         Export queue of a batch
    release_run.gd        State of one running process
    store_release_fetcher.gd  Runs list_releases.rb per store
    bundle_installer.gd   Background `bundle install`
  scripts/                release.sh, release.ps1, list_releases.rb, ci_release.gd
  templates/              Gemfile, Fastfile, Appfile, Pluginfile, env.example, bundle_config
    agents/               Agent notes + skills copied into a host project's .agents/
  docs/                   Shipped copy of the root docs/ — keep in sync
tests/                    godot/ (GUT), ruby/ (RSpec), shell/ (bats), fixtures/
```

## Rules that are not obvious from the code

1. **Never edit `addons/gut/`.** It is a vendored copy of GUT; see
   `addons/gut/VENDORED_VERSION.md`. Changes there are lost on the next re-vendor.
2. **Every plugin script starts with `@tool`.** It runs in the editor. Forgetting it makes
   the class silently unavailable.
3. **No literal strings in UI or shell-facing code.** Add a constant to
   `constants/release_strings.gd` instead.
4. **The `run.env` contract is duplicated in three files.** `env_*` in
   `release_strings.gd`, written in `core/run_files.gd`, read by **both**
   `scripts/release.sh` and `scripts/release.ps1`. Change one, change all.
5. **`addons/app_release/templates/` is a seed, not a source of truth.** Once
   `AppReleaseScaffolder` copies them into the host project, the project's copies win, and
   the scaffolder never overwrites an existing file.
6. **Comments are `##` doc comments, not `#`.** They feed Godot's Help panel and the
   Inspector. See `.agents/prompts/write-gdscript-docs.md`.
7. **The root `docs/` and `addons/app_release/docs/` must stay identical.** See
   `.agents/skills/update-docs.md`.
8. **The plugin never handles credentials.** They live in `fastlane/.env` (gitignored) and
   in the key files it points at. Do not add code that reads, logs or forwards them.

## Skills

- [run-tests](skills/run-tests.md) — the three suites and the import trap
- [add-a-store](skills/add-a-store.md) — every file a new destination touches
- [add-a-target-field](skills/add-a-target-field.md) — the GDScript ↔ shell ripple
- [edit-fastlane-lanes](skills/edit-fastlane-lanes.md) — which Fastfile is real
- [debug-a-failed-release](skills/debug-a-failed-release.md) — logs, locks, re-runs
- [update-docs](skills/update-docs.md) — README, docs/ and the shipped copies

## Prompts

- [review-plugin-change](prompts/review-plugin-change.md)
- [write-gdscript-docs](prompts/write-gdscript-docs.md)

## Before you open a PR

```sh
tests/run_all.sh
```

There is a GitHub Actions workflow (`.github/workflows/tests.yml`) that runs the same thing
on macOS.
