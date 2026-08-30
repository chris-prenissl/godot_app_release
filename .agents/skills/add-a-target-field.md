# Skill: add a field to a target

Anything the shell or fastlane needs travels GDScript → `run.env` → bash/PowerShell. Miss a
step and the value is silently empty at the far end.

## The seven edits

1. **`config/release_target.gd`** — the property:

   ```gdscript
   ## What it is, in one or two lines. Shown in the Inspector and the Help panel.
   @export var my_field: String = ""
   ```

   Put it under the right `@export_group` (Source / Destination / Build / Native project /
   Testers). The doc comment goes **above** the annotation.

2. **`config/release_target.gd` → `_validate_property()`** — hide it where it makes no
   sense, e.g. `_set_visible(property, is_ios())`.

3. **`config/release_target.gd` → `get_configuration_error()`** — if the field is required,
   return a sentence saying what to do. That string is what the Setup checklist and the
   confirmation dialog show.

4. **`constants/release_strings.gd`** — the key name:

   ```gdscript
   const env_my_field: StringName = "MY_FIELD"
   ```

5. **`core/run_files.gd` → `write_run_env()`** — one entry in `values`:

   ```gdscript
   AppReleaseStrings.env_my_field: target.my_field,
   ```

   Booleans are written as `"1"` / `"0"`; ints go through `str()`.

6. **`scripts/release.sh`** — read it in `load_environment()`, and `require_var MY_FIELD`
   if it is mandatory. Use it where it belongs (`export_project`, `run_fastlane`).

7. **`scripts/release.ps1`** — the same, or Windows users get an empty value with no error.

## Also check

- `scripts/ci_release.gd` if the field should be settable from the command line
- `ui/target_column.gd` if it should be editable per run from the panel (like tester groups
  and the debug checkbox), which also means threading it through
  `write_run_env()`'s override parameters
- `ui/release_dock.gd` `_ci_command_for()` if the CI command must carry it

## Tests

- `tests/godot/unit/config/release_target_test.gd` — default, visibility, validation
- `tests/shell/load_environment_test.bats` — the variable arrives
- `tests/shell/validation_test.bats` — a missing mandatory value fails loudly
- `tests/fixtures/ios_basic/run.env` — add the key so the other shell tests stay realistic
