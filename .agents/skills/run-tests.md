# Skill: run the tests

## Everything

```sh
tests/run_all.sh
```

Set `GODOT_BIN` if `godot` is not on your `PATH`:

```sh
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot tests/run_all.sh
```

## One suite at a time

**GDScript (GUT).** The import pass is not optional — without it Godot has not registered
the `class_name`s and every test fails with `Nonexistent function ... in base 'Nil'`:

```sh
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
```

Config is `.gutconfig.json`: it collects `res://tests/godot/unit/**/*_test.gd`.

**Ruby (RSpec).**

```sh
cd tests/ruby && bundle install && bundle exec rspec spec
```

**Shell (bats-core).** Needs `brew install bats-core` once.

```sh
bats tests/shell
```

## Where a test belongs

| Changed | Test in |
|---|---|
| `config/`, `core/`, `ui/` GDScript | `tests/godot/unit/<same subdirectory>/<file>_test.gd` |
| `scripts/release.sh` | `tests/shell/<function>_test.bats` — one file per shell function |
| `scripts/list_releases.rb`, `templates/Fastfile` | `tests/ruby/spec/` |

Shared fixtures — an iOS export preset, a `run.env`, a stub `.xcodeproj`, an
`ExportOptions.plist` — are in `tests/fixtures/ios_basic/` and are used by all three suites.
Add to them rather than inventing a second fixture project.

## Traps

- GUT tests that touch real project files use the helpers in `tests/godot/support/`
  (`FixtureSeededProjectFile`, `RealProjectFileFixture`) so the repository's own
  `export_presets.cfg` is restored afterwards. Use them; do not write to `res://` directly.
- `tests/shell` runs `release.sh` with `tests/shell/fake_bin/` first on `PATH`, which stubs
  `godot`, `bundle` and `xcodebuild`. A new external command needs a new fake there.
- The bats suite sources `release.sh` rather than executing it — the script guards its
  `main` with `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]`. Keep that guard.
