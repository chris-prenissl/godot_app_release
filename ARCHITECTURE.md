# Architecture

How App Release is put together, for people working **on** the plugin. If you only want to
ship an app, the [README](README.md) and the [store guides](docs/) are enough.

## The one-paragraph version

The plugin is a thin editor UI over a shell script. Everything configurable lives in a Godot
resource (`release_config.tres`). Because bash and Ruby cannot read a `.tres`, the plugin
**flattens** the resolved settings for one run into `.release_tools/run_<target>.env` and
hands that file to `scripts/release.sh`, which exports the project with a headless Godot and
uploads the artifact with fastlane. The panel never talks to a store itself — it starts
processes and tails their log files.

```
release_config.tres  →  run.env  →  release.sh  →  godot --export / xcodebuild  →  fastlane  →  store
      (GDScript)        (plain KEY="value")            (bash)                       (Ruby)
```

## Layers

| Layer | Directory | Knows about |
|---|---|---|
| Config | `addons/app_release/config/` | Resources you edit in the Inspector |
| Core | `addons/app_release/core/` | Files, processes, the OS. No UI |
| UI | `addons/app_release/ui/` | The Release and Setup tabs. Owns no logic worth testing twice |
| Strings | `addons/app_release/constants/` | Every user-facing string and every path literal |
| Scripts | `addons/app_release/scripts/` | bash, PowerShell, Ruby, and the headless CI entry point |
| Templates | `addons/app_release/templates/` | Seed copies of `Gemfile`, `fastlane/*` and the `.agents/` skills, copied into the host project once |

## Classes

```mermaid
classDiagram
    direction LR

    class AppReleaseConfig {
        +Array~AppReleaseGroup~ release_groups
        +String ios_bundle_id
        +String android_package_name
        +String apple_team_id
        +String logs_dir
        +all_targets() Array
        +runnable_targets() Array
        +find_target(id) AppReleaseTarget
        +load_project_config()$ AppReleaseConfig
    }
    class AppReleaseGroup {
        +String name
        +Array~AppReleaseTarget~ targets
        +runnable_targets() Array
    }
    class AppReleaseTarget {
        +String export_preset
        +String platform
        +Store store
        +BuildMode build_mode
        +String fastlane_lane
        +target_id() String
        +display_label() String
        +get_configuration_error() String
    }

    class AppReleasePresets {
        <<static>>
        +list_presets() Array
        +find_preset(name) Dictionary
        +version_of(preset) Dictionary
    }
    class AppReleaseVersionPatcher {
        <<static>>
        +patch(preset, version, build) Error
    }
    class AppReleaseRunFiles {
        <<static>>
        +write_run_env(...) Error
        +write_run_config(config) Error
    }
    class AppReleaseShell {
        <<static>>
        +release_command(args) Dictionary
        +fetch_command(...) Dictionary
        +kill_process_tree(pid)
    }
    class AppReleaseEnvironment {
        <<static>>
        +run(config) Array
    }
    class AppReleaseScaffolder {
        <<static>>
        +create_default_config() AppReleaseConfig
        +scaffold_fastlane() Dictionary
        +scaffold_agent_skills() Dictionary
        +append_gitignore() PackedStringArray
    }
    class AppReleaseStrings {
        <<static>>
        +env_* keys
        +docs_* links
    }

    class app_release_gd["app_release.gd (EditorPlugin)"]
    class release_dock_gd["release_dock.gd (TabContainer)"]
    class group_box_gd["group_box.gd (PanelContainer)"]
    class target_column_gd["target_column.gd (VBoxContainer)"]
    class setup_panel_gd["setup_panel.gd (VBoxContainer)"]
    class checklist_row_gd["checklist_row.gd"]

    class AppReleaseBatchRunner {
        +start(...) bool
        +launch(...) bool
        +stop_target(id)
        ~signal~ log_appended
        ~signal~ runs_changed
    }
    class AppReleaseBatchPlan {
        +next_export(batch) String
        +upload_targets(batch) PackedStringArray
    }
    class AppReleaseRun {
        +Phase phase
        +int pid
        +String log_path
    }
    class AppReleaseStoreFetcher {
        +fetch_all(stores, config)
        +fetch_one(store, config)
    }
    class AppReleaseLogTabs

    AppReleaseConfig "1" o-- "*" AppReleaseGroup : release_groups
    AppReleaseGroup "1" o-- "*" AppReleaseTarget : targets
    AppReleaseTarget ..> AppReleasePresets : reads its preset

    app_release_gd --> release_dock_gd : adds as main screen
    release_dock_gd --> group_box_gd : one per group
    group_box_gd --> target_column_gd : one per target
    release_dock_gd --> setup_panel_gd
    setup_panel_gd --> checklist_row_gd : one per check
    setup_panel_gd ..> AppReleaseEnvironment
    setup_panel_gd ..> AppReleaseScaffolder

    release_dock_gd --> AppReleaseBatchRunner
    release_dock_gd --> AppReleaseStoreFetcher
    release_dock_gd --> AppReleaseLogTabs
    release_dock_gd ..> AppReleaseConfig : loads

    AppReleaseBatchRunner --> AppReleaseBatchPlan : export queue
    AppReleaseBatchRunner "1" o-- "*" AppReleaseRun
    AppReleaseBatchRunner ..> AppReleaseVersionPatcher
    AppReleaseBatchRunner ..> AppReleaseRunFiles
    AppReleaseBatchRunner ..> AppReleaseShell
    AppReleaseStoreFetcher ..> AppReleaseShell
    AppReleaseRunFiles ..> AppReleaseStrings : env_* keys
```

`AppReleaseStrings` is used by nearly everything; only the edges that matter for the
`run.env` contract are drawn.

## One release, start to finish

```mermaid
sequenceDiagram
    autonumber
    actor You
    participant Dock as release_dock.gd
    participant Runner as AppReleaseBatchRunner
    participant Patcher as AppReleaseVersionPatcher
    participant Files as AppReleaseRunFiles
    participant Sh as scripts/release.sh
    participant Godot as godot --headless --export
    participant FL as fastlane
    participant Store as TestFlight / Play / Firebase

    You->>Dock: Release to TestFlight
    Dock->>Dock: confirmation dialog
    Dock->>Runner: start(config, targets, version, build, notes)
    Runner->>Patcher: patch(preset, version, build)
    Patcher->>Patcher: rewrite export_presets.cfg (atomic rename)
    Runner->>Files: write_run_env() + write_run_config()
    Files-->>Runner: .release_tools/run_<target>.env
    Runner->>Sh: OS.create_process(bash release.sh run.env log)
    activate Sh
    Sh->>Sh: load_environment, acquire_lock, rotate_logs, stage notes
    Sh->>Godot: export the preset
    Godot-->>Sh: .ipa / .apk / .aab (or .pck + xcodebuild)
    Sh->>FL: bundle exec fastlane <platform> <lane>
    FL->>Store: upload artifact + changelog
    Store-->>FL: accepted
    FL-->>Sh: exit code
    Sh->>Sh: write <log>.exit
    deactivate Sh

    loop every 0.5 s while running
        Runner->>Sh: read new bytes of the log file
        Runner-->>Dock: log_appended
        Dock-->>You: live log
    end
    Runner->>Runner: read <log>.exit
    Runner-->>Dock: status_changed / runs_changed
```

There is no pipe between the editor and the script. The script owns its log file, and the
exit code arrives as a separate `.exit` sidecar — which is why the runner waits a few polls
after the process disappears before calling a run statusless.

**Batches.** Releasing a whole group runs every export one after another (they share one
exporter and one `export_presets.cfg`), then starts all uploads at once.
`AppReleaseBatchPlan` holds that queue; each process is one `AppReleaseRun` with
`Phase.EXPORT` or `Phase.UPLOAD`.

## Which build mode does what

```mermaid
flowchart TD
    A[BUILD_MODE in run.env] --> B{PLATFORM}

    B -->|android| C[godot_export]
    C --> C1[Gradle build through the Android build template]
    C1 --> Z[artifact exists?]

    B -->|ios| D{mode}
    D -->|GODOT_EXPORT| E["die: a Godot iOS export produces an .xcodeproj, never an .ipa"]
    D -->|REGENERATE_NATIVE_PROJECT| F[godot_export regenerates the Xcode project]
    F --> G[xcodebuild archive + exportArchive]
    D -->|PCK_ONLY| H[godot_export_pack writes only the .pck]
    H --> G
    G --> Z

    Z -->|no| Y[fail: expected artifact missing]
    Z -->|yes| X[run_fastlane: bundle exec fastlane platform lane]
```

Mirrors `export_project()` in [`scripts/release.sh`](addons/app_release/scripts/release.sh).
`PCK_ONLY` is the mode to use once you maintain the Xcode project by hand — capabilities,
entitlements, extra frameworks — because a full export overwrites it.

## The GDScript ↔ shell contract

This is the one place where a change has to be made in three files at once:

| File | Role |
|---|---|
| `constants/release_strings.gd` | `env_*` constants — the key names |
| `core/run_files.gd` | writes those keys into `run.env` |
| `scripts/release.sh` / `scripts/release.ps1` | `require_var` / read them back |

Adding a target field means: an `@export` on `AppReleaseTarget`, a visibility rule in
`_validate_property()`, a check in `get_configuration_error()`, an `env_*` constant, a line
in `write_run_env()`, a reader in **both** scripts, and a `tests/shell` case.

## Generated and scratch files

| Path | Written by | Committed |
|---|---|---|
| `release_config.tres` | Setup tab, then you | yes |
| `Gemfile`, `fastlane/{Fastfile,Appfile,Pluginfile}` | Setup tab, then yours to edit | yes |
| `.agents/README.md`, `.agents/skills/*.md` | Setup tab (optional), then yours to edit | yes |
| `fastlane/.env` | Setup tab (placeholders) | **no** — credentials |
| `.release_tools/run_<target>.env`, `config.json`, `releases_*.json` | the plugin, per run | no |
| `logs/release_*.log` + `.exit` | `release.sh` | no |
| `release-notes/<version>-<build>.md` | `release.sh` | yes, if you like |
| `fastlane/metadata/android/en-US/changelogs/<build>.txt` | `release.sh` | yes |

## Tests

Three suites, one per language the logic lives in — see
[.agents/skills/run-tests.md](.agents/skills/run-tests.md).

| Language | Framework | Location |
|---|---|---|
| GDScript | GUT (vendored at `addons/gut/`) | `tests/godot/unit/` |
| Ruby | RSpec | `tests/ruby/spec/` |
| Shell | bats-core | `tests/shell/` |

Shared fixtures live in `tests/fixtures/ios_basic/`. Run everything with `tests/run_all.sh`.
