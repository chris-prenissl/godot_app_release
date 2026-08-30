# Skill: add a store

A "store" is an upload destination (TestFlight, App Store, Firebase App Distribution,
Google Play). Adding one touches all three languages. Work in this order.

## 1. GDScript — the target

`addons/app_release/config/release_target.gd`

- add the value to `enum Store` **at the end** — the enum index is used as an array index;
  inserting in the middle silently repoints every saved `release_config.tres`
- append the store id to `STORE_IDS`
- append the default lane to `DEFAULT_LANES` (same order as the enum)
- add it to `STORE_HINT_IOS` / `STORE_HINT_ANDROID` / `STORE_HINT_ALL`
- add it to `_allowed_store_ids()` for its platform
- if it publishes to real users, add it to `PRODUCTION_STORES` (that disables debug builds
  and tester groups) and to `release_kind_id()`
- extend `_sync_from_store()` with any defaults the store needs
- new store-specific properties: give them a `##` doc comment, put them under the right
  `@export_group`, and hide them for other stores in `_validate_property()`

## 2. GDScript — the strings

`addons/app_release/constants/release_strings.gd`

- `store_<name>` id constant
- an entry in `store_labels` (display name)
- an entry in `notes_destination` (what happens to the release notes)
- a `docs_guide_<name>` link if you write a guide for it

## 3. GDScript — defaults and checks

- `core/scaffolder.gd` — `_build_default_targets()` if a fresh config should offer it
- `core/environment_check.gd` — `_target_docs()` so the Setup row links to the right guide

## 4. Ruby — the release list

`addons/app_release/scripts/list_releases.rb`

- a `<name>_releases` function that calls the store API
- a `map_<name>_...` function that maps the response onto the row shape the panel renders:
  `{date, version, status}` — see `map_testflight_build` for the shape
- a branch in the dispatch at the bottom of the file
- credentials come from the environment (`need_env`) or from `config.json` (`store_config`),
  never from arguments

## 5. Ruby — the lane

`addons/app_release/templates/Fastfile`

- a lane inside the right `platform` block, named exactly as your `DEFAULT_LANES` entry
- read the artifact through the existing `artifact` helper, notes through `release_notes`,
  groups through `tester_groups`

Remember that this file is only a **seed**. Projects that already scaffolded keep their own
copy, so mention new lanes in the release notes and in `docs/`.

## 6. Shell

`scripts/release.sh` and `scripts/release.ps1` usually need nothing — they call
`fastlane $PLATFORM $LANE`. If the store needs an extra variable, follow
[add-a-target-field](add-a-target-field.md).

## 7. Tests

- `tests/godot/unit/config/release_target_test.gd` — store id, default lane, allowed
  stores per platform, release kind
- `tests/ruby/spec/list_releases_mapping_spec.rb` — the response mapping
- `tests/shell/` — only if the shell layer changed

## 8. Documentation

- a guide in `docs/`, copied to `addons/app_release/docs/` — see
  [update-docs](update-docs.md)
- the store table in both READMEs
