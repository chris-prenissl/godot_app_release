@tool
class_name AppReleaseConfig
extends Resource

@export_tool_button("Save to disk", "Save") var save_action: Callable = save_to_disk

## Targets live inside their group, not here — see AppReleaseGroup.targets.
@export var release_groups: Array[AppReleaseGroup] = []

@export_group("App identity")
@export var ios_bundle_id: String = ""
@export var android_package_name: String = ""
@export var apple_team_id: String = ""

@export_group("Paths")
@export var logs_dir: String = "logs"
@export var release_notes_dir: String = "release-notes"
@export var play_changelogs_dir: String = "fastlane/metadata/android/en-US/changelogs"
@export_range(1, 500) var keep_logs: int = 20

@export_group("Tools")
@export var godot_binary_path_override: String = ""
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

static func load_project_config() -> AppReleaseConfig:
	if not ResourceLoader.exists(AppReleaseStrings.config_resource_path):
		return null
	var resource := ResourceLoader.load(AppReleaseStrings.config_resource_path, "AppReleaseConfig")
	return resource as AppReleaseConfig
