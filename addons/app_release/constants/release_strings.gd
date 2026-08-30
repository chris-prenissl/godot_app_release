@tool
class_name AppReleaseStrings
extends RefCounted

## Central string table for the App Release plugin.
##
## Keeping every user-facing string and every file/path literal in one place makes
## the plugin translatable and keeps the GDScript-to-shell contract in a single spot:
## the [code]env_*[/code] keys written into [code]run.env[/code] here must match the
## variables read by [code]scripts/release.sh[/code] and [code]scripts/release.ps1[/code].
## [br][br]
## The constants are grouped in declaration order: paths, platforms and stores,
## [code]run.env[/code] keys, editor settings, UI labels, messages, documentation links,
## validation and status colouring.
##
## @tutorial(Architecture overview): https://github.com/chris-prenissl/godot_app_release/blob/main/ARCHITECTURE.md

static var _addon_dir: String = ""

## Derived from this script's own location, so the addon can be installed anywhere.
static func addon_dir() -> String:
	if _addon_dir.is_empty():
		var script_path: String = AppReleaseStrings.new().get_script().resource_path
		_addon_dir = script_path.get_base_dir().get_base_dir()
	return _addon_dir


## Project paths the plugin reads or writes.
const resource_path_prefix: StringName = "res://"
const config_resource_path: StringName = "res://release_config.tres"
const export_presets_path: StringName = "res://export_presets.cfg"
const project_gitignore_path: StringName = "res://.gitignore"

## Per-run scratch directory handed to bash and Ruby. Disposable, and gitignored.
const work_dir_name: StringName = ".release_tools"
const run_env_file_format: StringName = "run_%s.env"
const run_config_file_name: StringName = "config.json"
const releases_file_format: StringName = "releases_%s.json"
const stderr_suffix: StringName = ".err"
const exit_code_suffix: StringName = ".exit"

## Scripts shipped with the addon, relative to [method addon_dir].
const release_script_posix: StringName = "scripts/release.sh"
const release_script_windows: StringName = "scripts/release.ps1"
const list_releases_script: StringName = "scripts/list_releases.rb"
const ci_release_script: StringName = "scripts/ci_release.gd"
const templates_dir: StringName = "templates"

## Log filename: target id, then timestamp.
const log_file_format: StringName = "release_%s_%s.log"
const log_file_phase_format: StringName = "release_%s_%s_%s.log"

const notes_temp_file_format: StringName = ".release_notes_%s.txt"

## Platform ids. Godot's own [code]platform=[/code] values are mapped onto these by
## [AppReleasePresets].
const platform_ios: StringName = "ios"
const platform_android: StringName = "android"

## Store ids, matching [constant AppReleaseTarget.STORE_IDS] and the [code]STORE[/code]
## value read by the release scripts and [code]list_releases.rb[/code].
const store_testflight: StringName = "testflight"
const store_app_store: StringName = "app_store"
const store_firebase: StringName = "firebase"
const store_play: StringName = "play"

## Where the release notes end up per store, shown under the notes field.
const notes_destination: Dictionary = {
	"testflight": "Notes become the TestFlight changelog.",
	"app_store": "Notes are NOT uploaded — write \"What's New\" in App Store Connect.",
	"firebase": "Notes become the Firebase App Distribution release note.",
	"play": "Notes become the Google Play changelog.",
}

## Display names per store id.
const store_labels: Dictionary = {
	"testflight": "TestFlight",
	"app_store": "App Store",
	"firebase": "Firebase App Distribution",
	"play": "Google Play",
}

## Display names per release kind — see [method AppReleaseTarget.release_kind_id].
const release_kind_labels: Dictionary = {
	"test": "Test",
	"store": "Store",
}

## Keys written into [code]run.env[/code] by [method AppReleaseRunFiles.write_run_env].
## [b]Must stay in sync[/b] with the variables read by [code]scripts/release.sh[/code] and
## [code]scripts/release.ps1[/code] — adding one means editing all three files.
const env_target_id: StringName = "TARGET_ID"
const env_target_label: StringName = "TARGET_LABEL"
const env_platform: StringName = "PLATFORM"
const env_store: StringName = "STORE"
const env_lane: StringName = "LANE"
const env_export_preset: StringName = "EXPORT_PRESET"
const env_build_mode: StringName = "BUILD_MODE"
const env_artifact_path: StringName = "ARTIFACT_PATH"
const env_play_track: StringName = "PLAY_TRACK"
const env_app_identifier: StringName = "APP_IDENTIFIER"
const env_android_package_name: StringName = "ANDROID_PACKAGE_NAME"
const env_apple_team_id: StringName = "APPLE_TEAM_ID"
const env_native_project_path: StringName = "NATIVE_PROJECT_PATH"
const env_xcode_scheme: StringName = "XCODE_SCHEME"
const env_ios_export_options: StringName = "IOS_EXPORT_OPTIONS"
const env_pck_path: StringName = "PCK_PATH"
const env_project_root: StringName = "PROJECT_ROOT"
const env_godot_bin: StringName = "GODOT_BIN"
const env_logs_dir: StringName = "LOGS_DIR"
const env_release_notes_dir: StringName = "RELEASE_NOTES_DIR"
const env_play_changelogs_dir: StringName = "PLAY_CHANGELOGS_DIR"
const env_keep_logs: StringName = "KEEP_LOGS"
const env_extra_path: StringName = "EXTRA_PATH"
const env_debug_build: StringName = "DEBUG_BUILD"
const env_version: StringName = "VERSION"
const env_build: StringName = "BUILD"
const env_release_notes_file: StringName = "RELEASE_NOTES_FILE"
const env_release_groups: StringName = "RELEASE_GROUPS"
const env_ios_skip_build_processing_wait: StringName = "IOS_SKIP_BUILD_PROCESSING_WAIT"

## Editor-settings key the release notes are cached under, so they survive a restart.
const setting_last_notes: StringName = "app_release/last_notes"

## Name of the main-screen tab the plugin adds, next to 2D/3D/Script.
const plugin_screen_name: StringName = "Release"
const tab_release: StringName = "Release"
const tab_setup: StringName = "Setup"

## Labels, placeholders and tooltips of the Release tab's controls.
const label_version_name: StringName = "Version name"
const label_build_number: StringName = "Build number"
const label_release_notes: StringName = "Release notes"
const label_log: StringName = "Log"
const label_debug_build: StringName = "Debug build"
const label_stop: StringName = "Stop all running releases"
const label_stop_target_format: StringName = "Stop %s"
const label_follow_output: StringName = "Jump to latest"
const tooltip_follow_output: StringName = (
	"Scroll back to the end of the log and keep following new output."
)
const label_fetch: StringName = "Fetch"
const ci_command_label: StringName = "CI Command"
const label_copy_ci: StringName = "Copy"
const placeholder_ci_command: StringName = "CI command"
const tooltip_copy_ci: StringName = (
	"The command that runs this exact release on a CI runner, using the version, "
	+ "build number and options currently in the form. Copy it to the clipboard."
)
const status_ci_copied_format: StringName = "CI command for %s copied to the clipboard."
const status_pid_copied_format: StringName = "PID for %s copied to the clipboard."
const label_pid: StringName = "PID"
const tooltip_pid: StringName = (
	"Process id of the running release. Copy it to look the process up (ps, Activity "
	+ "Monitor, Task Manager) or to stop it by hand."
)
const label_release_to_format: StringName = "Release to %s"
const label_release_group_format: StringName = "Release %s"
const label_unnamed_group: StringName = "(unnamed group)"

const label_idle: StringName = "Idle"
const label_open_setup: StringName = "Open Setup"
const tooltip_open_setup: StringName = (
	"Go to the Setup tab to create release_config.tres and check what else is missing."
)
const label_press_fetch: StringName = "Press Fetch to load"

const placeholder_version: StringName = "0.1.0"
const placeholder_groups: StringName = "group aliases, e.g. internal-testers"
const placeholder_notes: StringName = "What changed in this build..."

const tooltip_groups: StringName = (
	"Comma-separated tester group aliases as defined in Firebase App Distribution / "
	+ "App Store Connect. Leave empty to upload without group assignment."
)
const tooltip_debug: StringName = (
	"Export with the debug template. Not available for App Store or Google Play targets."
)
const tooltip_fetch: StringName = "Load the release list from the store API"
const tooltip_ios_needs_macos: StringName = "iOS releases require macOS with Xcode installed."

const tree_columns: PackedStringArray = ["Date", "Version", "Status"]

const dialog_title: StringName = "Start release?"
const dialog_ok: StringName = "Release"
const dialog_text_format: StringName = "Really execute this release?\n\n%s"

## Status-line, error and log messages, in [method String.format] form.
const status_running_format: StringName = "Running: %s [%s] (pid %d)"
const status_running_batch_format: StringName = "Releasing %d targets [%s]..."
const status_nothing_to_release_format: StringName = "Nothing to release — %s"
const status_success_format: StringName = "Success: %s"
const status_failed_format: StringName = "FAILED (exit %d): %s"
const status_stopped_format: StringName = "Stopped: %s"
const status_fetching: StringName = "Fetching..."
const status_releases_format: StringName = "%d releases (fetched %s)"
const status_error_format: StringName = "Error: %s"
const status_presets_updated_format: StringName = "Presets updated: %s (%d)"

const error_no_config: StringName = (
	"No release_config.tres yet — open the Setup tab and create one."
)
const error_no_targets: StringName = "release_config.tres has no enabled targets."
const error_targets_need_setup_format: StringName = "Setup is missing for: %s"
const status_target_setup_missing_format: StringName = "⚠ Setup missing: %s"
const error_start_failed: StringName = "Failed to start the release script."
const error_no_stderr: StringName = "(no stderr captured)"
const error_empty_stderr: StringName = "(stderr empty)"

const log_stopped_by_user: StringName = "\n--- Stopped by user ---\n"
const log_waiting_for_turn: StringName = (
	"Waiting for the other targets to finish exporting...\n"
)
const log_not_started: StringName = "Not started — the release group was stopped.\n"
const warning_quit_while_running_format: StringName = (
	"Still releasing: %s. Quitting cancels the running release(s)."
)
const log_fetch_failed_format: StringName = "\n--- Fetch %s failed ---\n%s\n"

## Pages the Setup checklist links to from its [code]Docs ↗[/code] buttons.
const docs_ruby: StringName = "https://www.ruby-lang.org/en/documentation/installation/"
const docs_bundler: StringName = "https://bundler.io/guides/getting_started.html"
const docs_fastlane_install: StringName = "https://docs.fastlane.tools/#installing-fastlane"
const docs_fastlane_ios: StringName = "https://docs.fastlane.tools/getting-started/ios/setup/"
const docs_fastlane_android: StringName = (
	"https://docs.fastlane.tools/getting-started/android/setup/"
)
const docs_fastlane_keys: StringName = "https://docs.fastlane.tools/best-practices/keys/"
const docs_app_store_connect_api: StringName = "https://docs.fastlane.tools/app-store-connect-api/"
const docs_play_service_account: StringName = "https://docs.fastlane.tools/actions/supply/#setup"
const docs_firebase_fastlane: StringName = (
	"https://firebase.google.com/docs/app-distribution/android/distribute-fastlane"
)
const docs_godot_export: StringName = (
	"https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html"
)
const docs_godot_export_android: StringName = (
	"https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html"
)
const docs_godot_export_ios: StringName = (
	"https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html"
)
const docs_godot_gradle_build: StringName = (
	"https://docs.godotengine.org/en/stable/tutorials/export/android_gradle_build.html"
)
const docs_godot_command_line: StringName = (
	"https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html"
)
const docs_godot_version_control: StringName = (
	"https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html"
)
const docs_xcode: StringName = "https://developer.apple.com/documentation/xcode"

## This plugin's own per-store setup guides, also shipped as
## [code]addons/app_release/docs/[/code].
const docs_guide_ios: StringName = (
	"https://github.com/chris-prenissl/godot_app_release/blob/main/docs/ios-app-store.md"
)
const docs_guide_play: StringName = (
	"https://github.com/chris-prenissl/godot_app_release/blob/main/docs/google-play.md"
)
const docs_guide_firebase: StringName = (
	"https://github.com/chris-prenissl/godot_app_release/blob/main/docs/firebase-app-distribution.md"
)

const label_docs: StringName = "Docs ↗"
const tooltip_docs_format: StringName = "Click to open this page in your browser:\n%s"

## Characters a version name may contain — see [method AppReleaseVersionPatcher.is_valid_version].
const version_pattern: StringName = "^[A-Za-z0-9._+-]+$"

## Store status values rendered green in a target column's release list.
const status_good: PackedStringArray = [
	"completed", "distributed", "valid", "processing", "ready_for_sale", "prepare_for_submission",
]
## Store status values rendered red in a target column's release list.
const status_bad: PackedStringArray = [
	"failed", "invalid", "halted", "rejected", "developer_rejected",
]
