@tool
@icon("res://addons/app_release/icon.png")
class_name AppReleaseConfig
extends Resource

## Everything the Release panel needs, stored as [code]res://release_config.tres[/code].
##
## One config per project. It holds the app identity shared by every target, the paths the
## release scripts write to, and the [AppReleaseGroup] list that the Release tab renders as
## panels. Create it with [b]Create config[/b] in the Setup tab (see
## [method AppReleaseScaffolder.create_default_config]) and edit it in the Inspector.
## [br][br]
## Identity lives here rather than on each target on purpose: [code]fastlane/.env[/code]
## holds one App Store Connect key, one Play service account and one Firebase app id, so
## the setup already assumes a single iOS app and a single Android app per project.
##
## @tutorial(Architecture overview): https://github.com/chris-prenissl/godot_app_release/blob/main/ARCHITECTURE.md
## @tutorial(Ship to TestFlight and the App Store): https://github.com/chris-prenissl/godot_app_release/blob/main/docs/ios-app-store.md
## @tutorial(Ship to Google Play): https://github.com/chris-prenissl/godot_app_release/blob/main/docs/google-play.md
## @tutorial(Ship to Firebase App Distribution): https://github.com/chris-prenissl/godot_app_release/blob/main/docs/firebase-app-distribution.md

## Writes this resource back to [code]res://release_config.tres[/code].
@export_tool_button("Save to disk", "Save") var save_action: Callable = save_to_disk

@export_group("Release groups")

## Panels of the Release tab, in display order. Targets live inside their group, not here —
## see [member AppReleaseGroup.targets].
@export var release_groups: Array[AppReleaseGroup] = []

@export_group("App identity")

## iOS bundle identifier, e.g. [code]com.acme.game[/code]. Seeded from your iOS export
## preset when the config is created.
@export var ios_bundle_id: String = ""

## Android package name, e.g. [code]com.acme.game[/code]. Seeded from your Android export
## preset when the config is created.
@export var android_package_name: String = ""

## Apple Developer team id, as shown in the Apple Developer portal.
@export var apple_team_id: String = ""

@export_group("Paths")

## Where build logs are written, relative to the project root. One log per run, plus an
## [code].exit[/code] sidecar the panel reads for the exit code.
@export var logs_dir: String = "logs"

## Where the release-note archive [code]<version>-<build>.md[/code] is written. Safe to
## commit.
@export var release_notes_dir: String = "release-notes"

## Where the Google Play changelog [code]<build>.txt[/code] is written, for fastlane's
## [code]supply[/code] to pick up.
@export var play_changelogs_dir: String = "fastlane/metadata/android/en-US/changelogs"

## How many logs to keep in [member logs_dir]; older ones are rotated away after each run.
@export_range(1, 500) var keep_logs: int = 20

@export_group("Tools")

## Absolute path to the Godot binary used for headless exports. Blank auto-detects the
## running editor.
@export var godot_binary_path_override: String = ""

## Extra directories prepended to the [code]PATH[/code] of every child process. The editor
## starts children with a minimal [code]PATH[/code]; add your Ruby or fastlane location here
## if the Setup tab cannot find them.
@export var extra_path_entries: PackedStringArray = []


func save_to_disk() -> void:
	var path := resource_path
	if path.is_empty():
		path = AppReleaseStrings.config_resource_path

	var result := ResourceSaver.save(self, path)
	if result != OK:
		push_error("App Release: could not save %s (%s)." % [path, error_string(result)])
		return

	print("App Release: saved %s with %d target(s)." % [path, all_targets().size()])
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func bundle_identifier_for(platform: String) -> String:
	if platform == AppReleaseStrings.platform_ios:
		return ios_bundle_id
	if platform == AppReleaseStrings.platform_android:
		return android_package_name
	return ""

func identity_error(platform: String) -> String:
	if bundle_identifier_for(platform).is_empty():
		if platform == AppReleaseStrings.platform_ios:
			return "No iOS bundle id set in release_config.tres."
		if platform == AppReleaseStrings.platform_android:
			return "No Android package name set in release_config.tres."
		return "No bundle identifier configured for platform \"%s\"." % platform
	return ""

func all_targets() -> Array[AppReleaseTarget]:
	var result: Array[AppReleaseTarget] = []
	for group in release_groups:
		if group == null:
			continue
		for target in group.targets:
			if target != null:
				result.append(target)
	return result

## Enabled targets that also pass [method AppReleaseTarget.get_configuration_error].
func runnable_targets() -> Array[AppReleaseTarget]:
	var result: Array[AppReleaseTarget] = []
	for target in all_targets():
		if target.enabled and target.get_configuration_error().is_empty():
			result.append(target)
	return result

func enabled_targets() -> Array[AppReleaseTarget]:
	var result: Array[AppReleaseTarget] = []
	for target in all_targets():
		if target.enabled:
			result.append(target)
	return result

func active_store_ids() -> PackedStringArray:
	var seen: PackedStringArray = []
	for target in enabled_targets():
		var id := target.store_id()
		if not id in seen:
			seen.append(id)
	return seen


func find_target(target_id: String) -> AppReleaseTarget:
	for target in all_targets():
		if target.target_id() == target_id:
			return target
	return null

## [code]null[/code] when the project has no [code]release_config.tres[/code] yet.
static func load_project_config() -> AppReleaseConfig:
	if not ResourceLoader.exists(AppReleaseStrings.config_resource_path):
		return null
	var resource := ResourceLoader.load(AppReleaseStrings.config_resource_path, "AppReleaseConfig")
	return resource as AppReleaseConfig
