@tool
@icon("res://addons/app_release/icon.png")
class_name AppReleaseTarget
extends Resource

## One destination: an export preset plus the store it is uploaded to.
##
## A target is the unit the Release panel renders as a column and the unit
## [code]release.sh[/code] processes as a run. Pick [member export_preset] first — the
## platform is read out of the preset, and that decides which [member store] values are
## offered, how [member build_mode] is labelled, and which properties stay visible at all.
## [br][br]
## Targets are owned by an [AppReleaseGroup], never by [AppReleaseConfig] directly.
## [method get_configuration_error] returns the reason a target cannot run; it is what the
## Setup checklist and the release confirmation dialog display.
##
## @tutorial(Ship to TestFlight and the App Store): https://github.com/chris-prenissl/godot_app_release/blob/main/docs/ios-app-store.md
## @tutorial(Ship to Google Play): https://github.com/chris-prenissl/godot_app_release/blob/main/docs/google-play.md
## @tutorial(Ship to Firebase App Distribution): https://github.com/chris-prenissl/godot_app_release/blob/main/docs/firebase-app-distribution.md

## Where the artifact is uploaded. iOS presets can reach [constant Store.TESTFLIGHT] and
## [constant Store.APP_STORE], Android presets [constant Store.FIREBASE] and
## [constant Store.PLAY].
enum Store {
	## Apple's beta distribution, via the fastlane [code]beta[/code] lane.
	TESTFLIGHT,
	## A new App Store version, uploaded but not submitted.
	APP_STORE,
	## Firebase App Distribution — Android beta builds for tester groups.
	FIREBASE,
	## Google Play, on the track named by [member play_track].
	PLAY,
}

## How the artifact is produced before it is uploaded. See [member build_mode].
enum BuildMode {
	## Godot exports the finished artifact. Android only.
	GODOT_EXPORT,
	## Godot regenerates the native project, then Xcode builds and exports it.
	REGENERATE_NATIVE_PROJECT,
	## Only the PCK is exported; your hand-maintained native project is rebuilt around it.
	PCK_ONLY,
}

## Store ids written into [code]run.env[/code], indexed by [enum Store].
const STORE_IDS: PackedStringArray = [
	AppReleaseStrings.store_testflight,
	AppReleaseStrings.store_app_store,
	AppReleaseStrings.store_firebase,
	AppReleaseStrings.store_play,
]

## Inspector enum hint listing only the stores an iOS preset can reach.
const STORE_HINT_IOS: String = "TestFlight:0,App Store:1"
## Inspector enum hint listing only the stores an Android preset can reach.
const STORE_HINT_ANDROID: String = "Firebase App Distribution:2,Google Play:3"
## Fallback hint used while the platform is still unknown.
const STORE_HINT_ALL: String = "TestFlight:0,App Store:1,Firebase App Distribution:2,Google Play:3"
## iOS build-mode hint. [constant BuildMode.GODOT_EXPORT] is omitted on purpose: a Godot
## iOS export produces an Xcode project, never an [code].ipa[/code].
const BUILD_MODE_HINT_IOS: String = (
	"Let Godot regenerate the Xcode project:1,"
	+"Reuse my Xcode project - refresh the PCK only:2"
)
## Google Play tracks, in ascending order of exposure.
const PLAY_TRACK_HINT: String = "internal,alpha,beta,production"
## Lane picked for a freshly created target, indexed by [enum Store].
const DEFAULT_LANES: PackedStringArray = ["beta", "release", "firebase", "internal"]
## Stores that reach real users. Debug builds and tester groups are disabled for them.
const PRODUCTION_STORES: PackedInt32Array = [Store.APP_STORE, Store.PLAY]
## Release kind of a target that goes to testers.
const RELEASE_KIND_TEST: StringName = "test"
## Release kind of a target that goes to the public store listing.
const RELEASE_KIND_STORE: StringName = "store"

@export_group("Source")

## Preset from [code]export_presets.cfg[/code] to export. [b]Pick this first[/b] —
## everything else on this target follows from it.
@export var export_preset: String = "":
	set(value):
		if export_preset == value:
			return
		export_preset = value
		_sync_from_preset()
		notify_property_list_changed()

## Derived from the preset; shown read-only. Kept as storage so the shell layer
## can read it without re-parsing [code]export_presets.cfg[/code].
@export var platform: String = ""

@export_group("Destination")

## Where the artifact goes. The available options depend on [member platform].
@export var store: Store = Store.TESTFLIGHT:
	set(value):
		if store == value:
			return
		store = value
		_sync_from_store()
		notify_property_list_changed()

## Google Play track. Only meaningful when [member store] is [constant Store.PLAY].
@export var play_track: String = ""

## Lane invoked as [code]fastlane <platform> <lane>[/code]. Must exist in your project's
## [code]fastlane/Fastfile[/code].
@export var fastlane_lane: String = ""

## Shown on the column header and the release button. Blank derives one via
## [method display_label].
@export var label: String = "":
	set(value):
		label = value
		resource_name = value if not value.is_empty() else display_label()

@export_group("Build")

## How the artifact is produced. iOS only — Android always uses
## [constant BuildMode.GODOT_EXPORT]. Switch to [constant BuildMode.PCK_ONLY] once you
## edit the Xcode project by hand, because a full export overwrites it.
@export var build_mode: BuildMode = BuildMode.GODOT_EXPORT:
	set(value):
		if build_mode == value:
			return
		build_mode = value
		notify_property_list_changed()

## Artifact the store upload consumes, relative to the project root.
## Blank falls back to the preset's own [code]export_path[/code].
@export var artifact_path: String = ""

## Build this target debug instead of release on its next run. Editable from the
## Release panel's own column for this target, or here. Never available for a
## production store — see [constant PRODUCTION_STORES].
@export var debug_build: bool = false

## Unticked hides the target from the Release panel and skips it in every batch.
@export var enabled: bool = true

@export_group("Native project")

## [code]ios/MyGame.xcodeproj[/code] or [code]android/build[/code], relative to the
## project root.
@export var native_project_path: String = ""

## Xcode scheme to archive. iOS only.
@export var xcode_scheme: String = ""

## [code]ios/ExportOptionsAppStore.plist[/code], relative to the project root. iOS only.
@export var export_options_plist: String = ""

## Where the exported PCK is written, relative to the project root.
@export var pck_path: String = ""

@export_group("Testers")

## Whether this store accepts tester groups at all. Off for production stores.
@export var supports_tester_groups: bool = true

## Comma-separated tester group aliases as defined in Firebase App Distribution /
## App Store Connect. Editable from the Release panel's own column for this target, or
## here. Only meaningful when [member supports_tester_groups] is set.
@export var test_groups: String = ""

## Skip waiting for App Store Connect to finish processing the build after
## upload to TestFlight. iOS only.
@export var skip_build_processing_wait: bool = false


func store_id() -> String:
	return STORE_IDS[store]


## [member label], or a name derived from the store and the preset when it is blank.
func display_label() -> String:
	if not label.is_empty():
		return label
	var store_label: String = AppReleaseStrings.store_labels.get(store_id(), store_id())
	if store == Store.PLAY and not play_track.is_empty():
		return "%s %s" % [store_label, play_track.capitalize()]
	if export_preset.is_empty():
		return store_label
	return "%s (%s)" % [store_label, export_preset]


## Filename-safe id, also the [code]--target[/code] argument of [code]ci_release.gd[/code].
func target_id() -> String:
	var raw := "%s_%s" % [store_id(), export_preset]
	if store == Store.PLAY and not play_track.is_empty():
		raw = "%s_%s" % [store_id(), play_track]
	return raw.to_lower().replace(" ", "_").validate_filename()


## [member artifact_path], or the preset's [code]export_path[/code] when it is blank.
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


## [code]true[/code] when the build needs a native toolchain (Xcode), not just Godot.
func needs_native_project() -> bool:
	return is_ios()


## Whether this target reaches testers or the public listing.
func release_kind_id() -> String:
	match store:
		Store.TESTFLIGHT, Store.FIREBASE:
			return RELEASE_KIND_TEST
		Store.APP_STORE:
			return RELEASE_KIND_STORE
		Store.PLAY:
			return RELEASE_KIND_STORE if play_track == "production" else RELEASE_KIND_TEST
		_:
			return ""


func release_kind_label() -> String:
	return str(AppReleaseStrings.release_kind_labels.get(release_kind_id(), ""))


## Empty when the target can run, otherwise the first reason it cannot — the wording the
## Setup checklist and the release dialog show.
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
	if is_ios() and build_mode == BuildMode.GODOT_EXPORT:
		return "A Godot iOS export produces an Xcode project, not an .ipa — pick a build mode."
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
			property["hint_string"] = BUILD_MODE_HINT_IOS
			_set_visible(property, is_ios())
		&"play_track":
			property["hint"] = PROPERTY_HINT_ENUM
			property["hint_string"] = PLAY_TRACK_HINT
			_set_visible(property, store == Store.PLAY)
		&"debug_build", &"supports_tester_groups":
			_set_visible(property, not store in PRODUCTION_STORES)
		&"test_groups":
			_set_visible(property, supports_tester_groups)
		&"xcode_scheme", &"export_options_plist":
			_set_visible(property, is_ios() and needs_native_project())
		&"native_project_path", &"pck_path":
			_set_visible(property, needs_native_project())
		&"skip_build_processing_wait":
			_set_visible(property, is_ios())


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

	if is_android():
		build_mode = BuildMode.GODOT_EXPORT
	elif is_ios() and build_mode == BuildMode.GODOT_EXPORT:
		build_mode = BuildMode.REGENERATE_NATIVE_PROJECT

	_sync_from_store()


func _sync_native_paths_from_preset(preset: Dictionary) -> void:
	if not is_ios():
		return
	var export_path := str(preset["export_path"])
	if export_path.is_empty():
		return

	var base := export_path.get_basename()
	if native_project_path.is_empty():
		native_project_path = "%s.xcodeproj" % base
	if xcode_scheme.is_empty():
		xcode_scheme = base.get_file()
	if pck_path.is_empty():
		pck_path = "%s.pck" % base
	if export_options_plist.is_empty():
		export_options_plist = base.get_base_dir().path_join("ExportOptions.plist")


func _sync_from_store() -> void:
	if fastlane_lane.is_empty():
		fastlane_lane = DEFAULT_LANES[store]
	if store == Store.PLAY and play_track.is_empty():
		play_track = "internal"
	if store in PRODUCTION_STORES:
		debug_build = false
		supports_tester_groups = false
	if label.is_empty():
		resource_name = display_label()
