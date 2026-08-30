# App Release

A Godot 4 editor plugin that exports your project for mobile and ships it — to **TestFlight**,
the **App Store**, **Firebase App Distribution** and **Google Play** — without leaving the
editor.

It adds a **Release** tab next to 2D/3D/Script with one column per destination: the store's
recent releases on top, a Release button underneath, and a live build log at the bottom. The
work is mainly done by Godot's headless exporter and [fastlane](https://fastlane.tools).

Released in the [Godot Asset Store](https://store.godotengine.org/asset/christoph-prenissl/app-release/).

| Setup | Release |
|---|---|
| ![Setup tab](media/screenshot-setup.png) | ![Release tab](media/screenshot-release.png) |

_Godot_ | _GDScript_ | _Fastlane_ | _Shell_ | _Plugin_ | _App_Store_Connect_API_ | _Firebase_App_Distribution_ | _Google_Play_API_

---

## Contents

- [What it does](#what-it-does)
- [The building blocks](#the-building-blocks)
- [Requirements](#requirements)
- [Install](#install)
- [First-time setup](#first-time-setup)
- [Configure your targets](#configure-your-targets)
- [Daily use](#daily-use)
- [Per-store setup guides](#per-store-setup-guides)
- [Where things end up](#where-things-end-up)
- [Running it from a terminal](#running-it-from-a-terminal)
- [Releasing from CI](#releasing-from-ci)
- [Security](#security)
- [Contributing](#contributing)

## What it does

- One click per destination: patch the version, export the preset, upload the artifact.
- **Live log** streamed from the running build, with a Stop button that kills the whole
  process tree (not just the shell).
- **Fetch** pulls the current release list from each store so you can see which build
  numbers are already taken before you upload another one.
- Release notes are written once and delivered everywhere they can be: the TestFlight
  changelog, the Firebase App Distribution release note, and the Google Play changelog. They
  are also archived to `release-notes/<version>-<build>.md`. (The App Store lane is the
  deliberate exception — see [the iOS guide](docs/ios-app-store.md#the-two-lanes).)
- Version name and build number are written into `export_presets.cfg`, so a manual export
  from Project → Export produces the same build.

## The building blocks

Seven pieces, and it helps to know which one you are looking at when something goes wrong.

| Piece | What it is | Yours to edit |
|---|---|---|
| **`release_config.tres`** | The whole configuration: app identity, groups, targets. Edited in the Inspector | yes |
| **Release tab** | One panel per group, one column per target, the version/notes form, the log | — |
| **Setup tab** | A checklist of what is still missing, and the buttons that fix it | — |
| **`.release_tools/run_<target>.env`** | The resolved settings for one run, flattened to `KEY="value"` so bash and Ruby can read them. Regenerated every release | no, disposable |
| **`scripts/release.sh`** | Exports the preset (and runs `xcodebuild` for iOS), then calls fastlane. The whole pipeline lives here | it ships with the addon |
| **`fastlane/Fastfile`** | The upload lanes, copied into *your* project by the Setup tab | yes — a plugin update never touches it |
| **`scripts/list_releases.rb`** | Reads each store's release list for the **Fetch** buttons | it ships with the addon |

The flow, end to end:

```
release_config.tres  →  run.env  →  release.sh  →  godot --export / xcodebuild  →  fastlane  →  store
```

Diagrams and internals: [ARCHITECTURE.md](ARCHITECTURE.md).

### Config, groups, targets

Three resources, nested:

- **`AppReleaseConfig`** — one per project. App identity (bundle id, package name, team id),
  the paths logs and notes go to, and the list of groups.
- **`AppReleaseGroup`** — a panel in the Release tab, e.g. *Test* and *Store*. It has a name
  and a Release button that runs everything in it.
- **`AppReleaseTarget`** — one export preset plus one store. This is the unit that gets
  released, and it is what a column shows.

Each is its own resource, so targets and groups can be added, duplicated and removed freely.
Hovering a field in the Inspector shows what it does; pressing F1 and searching for
`AppReleaseTarget` shows the full documentation.

## Requirements

| | |
|---|---|
| Godot | 4.4 or newer |
| Ruby + Bundler + fastlane | required for every target |
| Xcode | required for iOS targets — **macOS only** |
| Android build template + release keystore | required for Android targets, configured in Godot's Editor Settings |

Platform support:

| Target | macOS | Linux | Windows |
|---|---|---|---|
| TestFlight, App Store | yes | no | no |
| Firebase App Distribution, Google Play | yes | yes | best-effort¹ |

¹ Windows runs through `scripts/release.ps1`, which ships **untested** — the plugin is
developed on macOS. Bug reports welcome.

## Install

**From the Asset Library:** search for *App Release*, install, then enable it under
Project → Project Settings → Plugins.

**Manually:** copy `addons/app_release/` into your project and enable it in the same place.

## First-time setup

Open the **Release** tab and switch to **Setup**. The buttons are split into **Required**
steps, numbered in the order they have to happen, and **Optional** helpers. A step that is
already done leaves its button greyed out, and the checklist underneath says what is still
missing.

1. **Create config** — writes `res://release_config.tres` with one target per store your
   export presets can serve. It only creates targets for platforms you actually have a preset
   for.
2. **Install release scripts** — copies `Gemfile` and
   `fastlane/{Fastfile,Appfile,Pluginfile}` into your project, creates `fastlane/.env` with
   placeholder values, and runs `bundle install` for you. The gem install takes a few minutes
   and runs in the background; the button reports when it is done.

   These files are yours to edit — a plugin update will never overwrite them, and anything
   that already exists is left alone. Press the button again any time to re-run
   `bundle install`.
3. **Edit credentials** — opens `fastlane/.env`, which step 2 created for you, in your text
   editor.

   `fastlane/.env` is gitignored and is the only place secrets live. The plugin never stores
   or transmits them.

   | Variable | Needed for | Scope | Guide |
   |---|---|---|---|
   | `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` | TestFlight and App Store | Your whole Apple team | [iOS](docs/ios-app-store.md) |
   | `PLAY_JSON_KEY_PATH` | Google Play | Your whole Play developer account | [Play](docs/google-play.md) |
   | `FIREBASE_APP_ID_ANDROID` | Firebase App Distribution | This one app | [Firebase](docs/firebase-app-distribution.md) |
   | `FIREBASE_SERVICE_CREDENTIALS` | Firebase — optional | Your Firebase project | [Firebase](docs/firebase-app-distribution.md) |

   Each guide walks the store's own setup — accounts, keys, permissions — from zero.

The optional buttons below do not affect a release:

- **Update .gitignore** keeps credentials, logs and build artifacts out of git. Nothing
  breaks without it, but `fastlane/.env` must never be committed.
- **Edit config** opens `release_config.tres` in the Inspector.
- **Install agent skills** copies notes for AI coding agents into `.agents/` — how to release
  this project from the command line, how to verify the setup, how to read a failed run, and
  how a Godot project is laid out. Plain markdown, yours to edit, and never overwritten.

## Configure your targets

Open `release_config.tres` in the Inspector (or press **Edit config** in the Setup tab).

### App identity

Set once for the whole project, under **App identity**:

| Field | Meaning |
|---|---|
| `ios_bundle_id` | iOS bundle identifier, e.g. `com.acme.game` |
| `android_package_name` | Android package name |
| `apple_team_id` | Apple Developer team id |

These are seeded from your export presets when the config is created, so they are usually
already correct.

Identity lives here rather than on each target on purpose. The credentials in `fastlane/.env`
are **one** App Store Connect key, **one** Play service account and **one** Firebase app id,
so the setup already assumes a single iOS app and a single Android app per project. Putting
the identifier on each target would let two targets disagree while still sharing those
credentials — which fails in confusing ways rather than loudly. If you need to ship two
different bundle ids, use two Godot projects.

### Targets

**Pick the export preset first.** Everything else follows from it — the platform is read out
of the preset, and that decides which stores you can pick, how the build modes are labelled,
and which fields are shown at all.

The Inspector groups a target's fields into **Source**, **Destination**, **Build**, **Native
project** and **Testers**:

| Field | Group | Meaning |
|---|---|---|
| `export_preset` | Source | Which preset from `export_presets.cfg` to export |
| `platform` | Source | Read-only, derived from the preset |
| `store` | Destination | Where the artifact goes. Options depend on the platform |
| `play_track` | Destination | Google Play track — `internal`, `alpha`, `beta`, `production` |
| `fastlane_lane` | Destination | Lane invoked as `fastlane <platform> <lane>` |
| `label` | Destination | Column heading. Blank derives one |
| `build_mode` | Build | See below |
| `artifact_path` | Build | What gets uploaded. Blank uses the preset's own export path |
| `debug_build`, `enabled` | Build | Debug template; whether the target appears at all |
| `native_project_path`, `xcode_scheme`, `export_options_plist`, `pck_path` | Native project | iOS only, filled in from the preset |
| `supports_tester_groups`, `test_groups` | Testers | Tester group aliases for TestFlight / Firebase |
| `skip_build_processing_wait` | Testers | iOS only. Skip waiting for App Store Connect to process the build |

### Build modes

| Mode | iOS | Android |
|---|---|---|
| **Godot export** | *not available* — a Godot iOS export produces an Xcode project, never an `.ipa` | Godot builds the APK/AAB through Gradle |
| **Regenerate native project** | Godot regenerates the Xcode project, then `xcodebuild` archives and exports it | Reinstalls the Android build template, then exports |
| **PCK only** | Exports just the `.pck`, then `xcodebuild` rebuilds your **existing, hand-maintained** `.xcodeproj` | Exports just the `.pck`, then runs `gradlew` in your existing `android/build` |

For Android, *Godot export* is the right default. For iOS, start with *Regenerate native
project* and switch to **PCK only** once you have an Xcode project you have edited by hand —
capabilities, entitlements, extra frameworks — because a full Godot export overwrites it.

## Daily use

1. Set the **version name** and **build number**. They are written into every enabled
   target's preset as soon as the field loses focus.
2. Write **release notes** — they become the TestFlight changelog, the Firebase release note
   and the Play changelog.
3. Optionally add **test groups** (comma-separated aliases as defined in App Store Connect or
   Firebase) and tick **Debug build**.
4. Press **Release to …**, confirm, and watch the log. A group's own button releases every
   target in it: the exports run one after another, then all uploads start.
5. Press **Fetch** on any column to reload that store's release list.

Notes, groups and the debug checkbox survive an editor restart. They are stored per
project — notes live in `.release_tools/last_notes.txt`, groups and the debug flag on the
target itself — so two projects never share them.

## Per-store setup guides

Each store has its own accounts, keys and rules. These walk them from zero:

- **[TestFlight and the App Store](docs/ios-app-store.md)** — Apple Developer Program, App
  Store Connect API key, signing, `ExportOptions.plist`, the two lanes, build numbers.
- **[Google Play](docs/google-play.md)** — Play Console account, keystore, the first manual
  upload, service account, tracks, AAB vs APK, `versionCode`.
- **[Firebase App Distribution](docs/firebase-app-distribution.md)** — Firebase project, App
  ID, service account vs `firebase login`, tester groups.

## Where things end up

| Path | What |
|---|---|
| `logs/release_<target>_<timestamp>.log` | One log per run; the newest 20 are kept |
| `logs/release_*.log.exit` | The run's exit code — this is what the panel reads |
| `.release_tools/` | Generated per-run config handed to bash and Ruby. Disposable |
| `release-notes/<version>-<build>.md` | Human-readable archive, safe to commit |
| `fastlane/metadata/android/en-US/changelogs/<build>.txt` | Play changelog |

### Troubleshooting

**"another release is already running"** — a previous run left `logs/.release.lock.<target>`
behind. The script clears it by itself once the owning process is gone; delete the directory
if it persists.

**Fetch shows a red error** — the full stderr is in
`.release_tools/releases_<store>.json.err`, and the short version is in the log pane.

**"Ruby"/"Bundler"/"fastlane" missing in the Setup tab** — the editor starts child processes
with a minimal `PATH`. The plugin already probes the usual locations (Homebrew, rbenv, rvm,
asdf); add anything unusual to `extra_path_entries` in `release_config.tres`.

**Uploading fails on a duplicate build** — the store rejects a build number it has already
seen. Press **Fetch** on that column to see what is taken.

Store-specific failures are covered at the end of each [store guide](#per-store-setup-guides).

## Running it from a terminal

Everything the panel does is a shell script driven by one file. Each time you confirm a
release, the plugin writes `.release_tools/run_<target>.env` — a plain, `source`-able list of
`KEY="value"` pairs holding the whole resolved configuration for that run — and then hands it
to the script:

```sh
addons/app_release/scripts/release.sh .release_tools/run_<target>.env logs/manual.log
```

Running that yourself **repeats the last release the panel configured**. It is the quick way
to retry after fixing a credential or a lane, without going back to the editor. An optional
third argument — `export`, `upload` or `all` — runs just one phase.

Note the ordering: `run.env` is produced by the editor, so it does not exist in a fresh
checkout, and it is gitignored. A terminal run is a *re-run*, not a first run. To change what
gets built — a different target, version or build mode — set it in the panel and press
Release once, or hand-edit `run.env` before invoking the script. Note that the panel also
patches the version into `export_presets.cfg` before starting; the script does not, so a
hand-edited `VERSION` will not reach the export.

## Releasing from CI

For a release triggered by a commit, `run.env` has to be generated **on the runner** — it
holds absolute paths (`PROJECT_ROOT`, `GODOT_BIN`, `EXTRA_PATH`) that mean nothing on another
machine, so a committed one would not work. `ci_release.gd` does headlessly what pressing
Release does in the editor:

```sh
godot --headless --path . \
	--script addons/app_release/scripts/ci_release.gd -- \
	--target play_internal --version 1.4.0 --build "$GITHUB_RUN_NUMBER"

bash addons/app_release/scripts/release.sh .release_tools/run_play_internal.env
```

The first command resolves the target from `release_config.tres`, runs the same validation
the panel runs, patches the version into `export_presets.cfg` and writes `run.env`. The
second does the export and the upload. Both exit non-zero on failure, so the job fails where
the problem is.

Press **CI** on any target column to copy that target's exact command — with the version,
build number, tester groups and debug flag currently in the form — to your clipboard.

`--list` prints the available target ids; `--help` documents the rest.

### Credentials on a runner

**You do not need a `fastlane/.env`.** The lanes read plain environment variables, and dotenv
ignores the file when it is missing — so export your secrets directly:

```yaml
env:
  ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
  ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
  ASC_KEY_PATH: ${{ github.workspace }}/AuthKey.p8   # written from a secret at run time
  PLAY_JSON_KEY_PATH: ${{ github.workspace }}/play.json
  FIREBASE_APP_ID_ANDROID: ${{ secrets.FIREBASE_APP_ID_ANDROID }}
  FIREBASE_SERVICE_CREDENTIALS: ${{ github.workspace }}/firebase.json
```

The two `*_PATH` variables point at files, so decode those from base64 secrets into the
workspace before the release step, and delete them afterwards.

Commit `Gemfile`, `Gemfile.lock` and `fastlane/` so the runner can `bundle install` — only
`fastlane/.env` stays out of git.

Android signing and iOS signing on a runner are covered in the
[Play](docs/google-play.md#on-ci) and [iOS](docs/ios-app-store.md#on-ci) guides.

## Security

Credentials only ever live in `fastlane/.env` and in the key files it points at, both outside
version control. The plugin does not read, store or transmit them — it hands fastlane the
environment and gets out of the way.

One detail worth knowing: when no Firebase service account is configured, the release-list
fetcher refreshes the session left by `firebase login`, using the OAuth client id and secret
of the open-source `firebase-tools` CLI. Those values are published in that project's source
— they are not secrets of yours — and you can override them with `FIREBASE_CLI_CLIENT_ID` and
`FIREBASE_CLI_CLIENT_SECRET`. Configuring `FIREBASE_SERVICE_CREDENTIALS` skips that path
entirely.

## Contributing

Working **on** the plugin rather than with it:

- [ARCHITECTURE.md](ARCHITECTURE.md) — layers, class diagram, the release sequence, the
  GDScript ↔ shell contract.
- [.agents/README.md](.agents/README.md) — project map, the rules that are not obvious from
  the code, and task guides in [.agents/skills/](.agents/skills/).

### Running the test suite

None of this ships in `addons/app_release/`, and none of it is needed to use the plugin.

The suite is split by language, matching the three places the plugin's logic actually lives:

| Language | Framework | Lives in |
|---|---|---|
| GDScript | [GUT](https://github.com/bitwes/Gut), vendored at `addons/gut/` | `tests/godot/unit/` |
| Ruby | RSpec | `tests/ruby/spec/` |
| Shell | [bats-core](https://github.com/bats-core/bats-core) | `tests/shell/` |

Shared test data — an example iOS export preset, a `run.env`, a stub `.xcodeproj`, an
`ExportOptions.plist` — lives in `tests/fixtures/ios_basic/`, used by all three suites.

**Prerequisites**, once per machine:

```sh
brew install bats-core
```

GUT is already vendored in the repo (`addons/gut/`, see `addons/gut/VENDORED_VERSION.md`) —
nothing to install. RSpec's gems install on first run.

**Run everything:**

```sh
tests/run_all.sh
```

**Run one language at a time:**

```sh
# GDScript (GUT) — first run needs an import pass, or GUT's class_names won't resolve:
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json

# Ruby (RSpec)
cd tests/ruby && bundle install && bundle exec rspec spec

# Shell (bats-core)
bats tests/shell
```

The same suite runs on every push and pull request via
[`.github/workflows/tests.yml`](.github/workflows/tests.yml).

## License

MIT — see [LICENSE](LICENSE).

Based off of the release tooling built for *Wonderfolios*.
