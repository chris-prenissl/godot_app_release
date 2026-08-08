@tool
class_name AppReleaseTarget
extends Resource

enum Store {
	TESTFLIGHT,
	APP_STORE,
	FIREBASE,
	PLAY,
}

enum BuildMode {
	GODOT_EXPORT,
	REGENERATE_NATIVE_PROJECT,
	PCK_ONLY,
}

const STORE_IDS: PackedStringArray = [
	AppReleaseStrings.store_testflight,
	AppReleaseStrings.store_app_store,
	AppReleaseStrings.store_firebase,
	AppReleaseStrings.store_play,
]

const STORE_HINT_IOS: String = "TestFlight:0,App Store:1"
const STORE_HINT_ANDROID: String = "Firebase App Distribution:2,Google Play:3"
const STORE_HINT_ALL: String = "TestFlight:0,App Store:1,Firebase App Distribution:2,Google Play:3"
const BUILD_MODE_HINT_IOS: String = (
	"Godot export (regenerates Xcode project):0,"
	+"Regenerate Xcode project + xcodebuild:1,"
	+"Reuse Xcode project - refresh PCK only:2"
)
const BUILD_MODE_HINT_ANDROID: String = (
	"Godot export (Gradle):0,"
	+"Reinstall build template + Godot export:1,"
	+"Reuse Gradle project - refresh PCK only:2"
)
const BUILD_MODE_HINT_GENERIC: String = (
	"Godot export:0,Regenerate native project:1,Refresh PCK only:2"
)
const PLAY_TRACK_HINT: String = "internal,alpha,beta,production"
const DEFAULT_LANES: PackedStringArray = ["beta", "release", "firebase", "internal"]
const PRODUCTION_STORES: PackedInt32Array = [Store.APP_STORE, Store.PLAY]

@export var export_preset: String = "":
	set(value):
		if export_preset == value:
			return
		export_preset = value
		_sync_from_preset()
		notify_property_list_changed()

## Derived from the preset; shown read-only. Kept as storage so the shell layer
## can read it without re-parsing `export_presets.cfg`.
@export var platform: String = ""

## Shown on the column header and the release button. Blank derives one.
@export var label: String = "":
	set(value):
		label = value
		resource_name = value

@export var store: Store = Store.TESTFLIGHT:
	set(value):
		if store == value:
			return
		store = value
		_sync_from_store()
		notify_property_list_changed()

@export var build_mode: BuildMode = BuildMode.GODOT_EXPORT:
	set(value):
		if build_mode == value:
			return
		build_mode = value
		notify_property_list_changed()

## Lane invoked as `fastlane <platform> <lane>`.
@export var fastlane_lane: String = ""

## Google Play track. Only meaningful when [member store] is [constant Store.PLAY].
@export var play_track: String = ""

## Artifact the store upload consumes, relative to the project root.
## Blank falls back to the preset's own `export_path`.
@export var artifact_path: String = ""

@export var allow_debug_build: bool = true
@export var supports_tester_groups: bool = true
@export var enabled: bool = true


## `ios/MyGame.xcodeproj` or `android/build`, relative to the project root.
@export var native_project_path: String = ""
## Xcode scheme to archive. iOS only.
@export var xcode_scheme: String = ""
## `ios/ExportOptionsAppStore.plist`, relative to the project root. iOS only.
@export var export_options_plist: String = ""
## Where the exported PCK is written, relative to the project root.
@export var pck_path: String = ""
## Gradle task to run, e.g. `bundleRelease`. Android only.
@export var gradle_task: String = ""


var _presets_modified_time := 0

func _init() -> void:
	if not Engine.is_editor_hint():
		return
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem != null and not filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
		filesystem.filesystem_changed.connect(_on_filesystem_changed)

func _on_filesystem_changed() -> void:
	var current := AppReleasePresets.presets_modified_time()
	if current == _presets_modified_time:
		return
	_presets_modified_time = current
	notify_property_list_changed()


func store_id() -> String:
	return STORE_IDS[store]

func display_label() -> String:
	if not label.is_empty():
		return label
	var store_label: String = AppReleaseStrings.store_labels.get(store_id(), store_id())
	if store == Store.PLAY and not play_track.is_empty():
		return "%s %s" % [store_label, play_track.capitalize()]
	if export_preset.is_empty():
		return store_label
	return "%s (%s)" % [store_label, export_preset]


func target_id() -> String:
	var raw := "%s_%s" % [store_id(), export_preset]
	if store == Store.PLAY and not play_track.is_empty():
		raw = "%s_%s" % [store_id(), play_track]
	return raw.to_lower().replace(" ", "_").validate_filename()


func resolved_artifact_path() -> String:
	if not artifact_path.is_empty():
		return artifact_path
	var preset := AppReleasePresets.find_preset(export_preset)
	return str(preset.get("export_path", ""))

func release_notes_destination() -> String:
	return str(AppReleaseStrings.notes_destination.get(store_id(), ""))

func release_notes_are_not_possible() -> bool:
	return store == Store.APP_STORE

func is_ios() -> bool:
	return platform == AppReleaseStrings.platform_ios

func is_android() -> bool:
	return platform == AppReleaseStrings.platform_android

func needs_native_project() -> bool:
	return build_mode != BuildMode.GODOT_EXPORT


func get_configuration_error() -> String:
	if export_preset.is_empty():
		return "No export preset selected."
	if AppReleasePresets.find_preset(export_preset).is_empty():
		return "Export preset \"%s\" no longer exists in export_presets.cfg." % export_preset
	if not (is_ios() or is_android()):
		return "Platform \"%s\" has no supported store." % platform
	if not STORE_IDS[store] in _allowed_store_ids():
		return "Store \"%s\" is not available for %s." % [store_id(), platform]
	if fastlane_lane.is_empty():
		return "No fastlane lane set."
	if resolved_artifact_path().is_empty():
		return "Preset \"%s\" has no export_path and no artifact path is set." % export_preset
	if store == Store.PLAY and play_track.is_empty():
		return "Google Play targets need a track."
	if needs_native_project() and native_project_path.is_empty():
		return "Build mode \"%s\" needs a native project path." % BuildMode.keys()[build_mode]
	if needs_native_project() and pck_path.is_empty():
		return "Build mode \"%s\" needs a PCK path." % BuildMode.keys()[build_mode]
	if is_ios() and needs_native_project():
		if export_options_plist.is_empty():
			return "xcodebuild needs an export options plist."

		var plist := ProjectSettings.globalize_path(
			AppReleaseStrings.resource_path_prefix + export_options_plist
		)
		if not FileAccess.file_exists(plist):
			return "Export options plist not found: %s" % export_options_plist
	return ""


func _validate_property(property: Dictionary) -> void:
	var property_name: StringName = property["name"]

	match property_name:
		&"export_preset":
			property["hint"] = PROPERTY_HINT_ENUM
			property["hint_string"] = AppReleasePresets.preset_name_hint()
		&"platform":
			property["usage"] = int(property["usage"]) | PROPERTY_USAGE_READ_ONLY
		&"store":
			property["hint"] = PROPERTY_HINT_ENUM
			property["hint_string"] = _store_hint()
		&"build_mode":
			property["hint"] = PROPERTY_HINT_ENUM
			property["hint_string"] = _build_mode_hint()
		&"play_track":
			property["hint"] = PROPERTY_HINT_ENUM
			property["hint_string"] = PLAY_TRACK_HINT
			_set_visible(property, store == Store.PLAY)
		&"allow_debug_build", &"supports_tester_groups":
			_set_visible(property, not store in PRODUCTION_STORES)
		&"xcode_scheme", &"export_options_plist":
			_set_visible(property, is_ios() and needs_native_project())
		&"gradle_task":
			_set_visible(property, is_android() and needs_native_project())
		&"native_project_path", &"pck_path":
			_set_visible(property, needs_native_project())


static func _set_visible(property: Dictionary, visible: bool) -> void:
	var usage := int(property["usage"])
	if visible:
		property["usage"] = usage | PROPERTY_USAGE_EDITOR
	else:
		property["usage"] = usage & ~PROPERTY_USAGE_EDITOR


func _store_hint() -> String:
	if is_ios():
		return STORE_HINT_IOS
	if is_android():
		return STORE_HINT_ANDROID
	return STORE_HINT_ALL


func _build_mode_hint() -> String:
	if is_ios():
		return BUILD_MODE_HINT_IOS
	if is_android():
		return BUILD_MODE_HINT_ANDROID
	return BUILD_MODE_HINT_GENERIC


func _allowed_store_ids() -> PackedStringArray:
	if is_ios():
		return [AppReleaseStrings.store_testflight, AppReleaseStrings.store_app_store]
	if is_android():
		return [AppReleaseStrings.store_firebase, AppReleaseStrings.store_play]
	return STORE_IDS


func _sync_from_preset() -> void:
	var preset := AppReleasePresets.find_preset(export_preset)
	if preset.is_empty():
		return

	platform = str(preset["platform"])

	if artifact_path.is_empty():
		artifact_path = str(preset["export_path"])
	_sync_native_paths_from_preset(preset)

	if not STORE_IDS[store] in _allowed_store_ids():
		store = Store.TESTFLIGHT if is_ios() else Store.FIREBASE
	_sync_from_store()


func _sync_native_paths_from_preset(preset: Dictionary) -> void:
	var export_path := str(preset["export_path"])
	if export_path.is_empty():
		return
	var base := export_path.get_basename()

	if is_ios():
		if native_project_path.is_empty():
			native_project_path = "%s.xcodeproj" % base
		if xcode_scheme.is_empty():
			xcode_scheme = base.get_file()
		if pck_path.is_empty():
			pck_path = "%s.pck" % base
		if export_options_plist.is_empty():
			export_options_plist = base.get_base_dir().path_join("ExportOptions.plist")
		return

	if not is_android():
		return

	var options: Dictionary = preset["options"]
	var gradle_dir := str(options.get("gradle_build/gradle_build_directory", "")).strip_edges()
	if gradle_dir.is_empty():
		gradle_dir = "android"
	gradle_dir = gradle_dir.trim_prefix(AppReleaseStrings.resource_path_prefix)

	if native_project_path.is_empty():
		native_project_path = gradle_dir.path_join("build")
	if pck_path.is_empty():
		pck_path = native_project_path.path_join("assets").path_join("%s.pck" % base.get_file())
	if gradle_task.is_empty():
		var builds_aab := (
			AppReleasePresets.get_android_export_format(preset) == AppReleasePresets.FORMAT_AAB
		)
		gradle_task = "bundleRelease" if builds_aab else "assembleRelease"


func _sync_from_store() -> void:
	if fastlane_lane.is_empty():
		fastlane_lane = DEFAULT_LANES[store]
	if store == Store.PLAY and play_track.is_empty():
		play_track = "internal"
	if store in PRODUCTION_STORES:
		allow_debug_build = false
		supports_tester_groups = false
