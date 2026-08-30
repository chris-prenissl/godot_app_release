# Prompt: review a change to this plugin

Review the diff against the rules this repository actually enforces. Report findings as
`file:line — problem — fix`, most severe first, and skip praise.

## Correctness

- Does a new or changed `run.env` key exist in **all** of `constants/release_strings.gd`,
  `core/run_files.gd`, `scripts/release.sh` and `scripts/release.ps1`?
- Was a value inserted into the middle of `AppReleaseTarget.Store`, `STORE_IDS`,
  `DEFAULT_LANES` or `BuildMode`? The enum index is stored in `release_config.tres` and used
  as an array index — appending is the only safe edit.
- Does a new required target field return a message from `get_configuration_error()`, so the
  Setup checklist can explain it?
- Does new UI go through `AppReleaseStrings` instead of literal strings?
- Is every plugin script still `@tool`?
- Does anything read, log, copy or forward a credential? `fastlane/.env` and the key files
  it points at must stay untouched by GDScript.
- Are child processes still killed as a tree (`AppReleaseShell.kill_process_tree`)? Killing
  the shell alone leaves the export or fastlane running.
- Does a path assume macOS? `core/shell.gd` is the only place allowed to branch on
  the OS.

## Tests

- GDScript change without a `tests/godot/unit/**` counterpart?
- Shell change without a `tests/shell/*.bats` counterpart?
- Does a new external command need a stub in `tests/shell/fake_bin/`?
- Does a GUT test write to `res://` without the fixtures in `tests/godot/support/`?

## Documentation

- New or changed `@export`: does it have a `##` doc comment, and is it in the right
  `@export_group`?
- User-visible behaviour change: are `README.md`, `addons/app_release/README.md` and
  `docs/` updated, and is `diff -r docs addons/app_release/docs` still clean?
- Did a lane change in `templates/Fastfile`? Existing projects keep their own copy — the
  change must be called out for users, not just shipped.

## Not worth reporting

Formatting, tab-vs-space, or naming preferences that match the surrounding file.
