@tool
class_name AppReleasePresets
extends RefCounted

## Read-only access to [code]res://export_presets.cfg[/code].
##
## Every target in [AppReleaseConfig] starts by picking a preset from here; the preset
## then supplies the platform, the artifact path and the initial bundle identifier.
## Nothing in this class writes — patching versions is [AppReleaseVersionPatcher]'s job.
## [br][br]
## A preset is returned as a [Dictionary] of [code]{name, platform, godot_platform,
## export_path, section, options_section, options}[/code].

## Godot's own [code]platform=[/code] values mapped onto the plugin's platform ids.
const _PLATFORM_IDS: Dictionary = {
	"iOS": AppReleaseStrings.platform_ios,
	"Android": AppReleaseStrings.platform_android,
}

static func list_presets() -> Array[Dictionary]:
	var presets: Array[Dictionary] = []
	var cfg := ConfigFile.new()
	if cfg.load(AppReleaseStrings.export_presets_path) != OK:
		return presets

	for section in cfg.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var options_section := "%s.options" % section
		var godot_platform := str(cfg.get_value(section, "platform", ""))
		var options: Dictionary = {}
		if cfg.has_section(options_section):
			for key in cfg.get_section_keys(options_section):
				options[key] = cfg.get_value(options_section, key)
		presets.append({
			"name": str(cfg.get_value(section, "name", "")),
			"platform": _PLATFORM_IDS.get(godot_platform, godot_platform.to_lower()),
			"godot_platform": godot_platform,
			"export_path": str(cfg.get_value(section, "export_path", "")),
			"section": section,
			"options_section": options_section,
			"options": options,
		})
	return presets

static func presets_modified_time() -> int:
	var path := ProjectSettings.globalize_path(AppReleaseStrings.export_presets_path)
	if not FileAccess.file_exists(path):
		return 0
	return int(FileAccess.get_modified_time(path))


static func uses_gradle_build(preset: Dictionary) -> bool:
	if preset.is_empty():
		return false
	var options: Dictionary = preset["options"]
	return bool(options.get("gradle_build/use_gradle_build", false))


static func android_build_template_dir(preset: Dictionary) -> String:
	if preset.is_empty():
		return "android/build"
	var options: Dictionary = preset["options"]
	var gradle_dir := str(options.get("gradle_build/gradle_build_directory", "")).strip_edges()
	if gradle_dir.is_empty():
		gradle_dir = "android"
	return gradle_dir.trim_prefix(AppReleaseStrings.resource_path_prefix).path_join("build")


static func find_preset(preset_name: String) -> Dictionary:
	if preset_name.is_empty():
		return {}
	for preset in list_presets():
		if preset["name"] == preset_name:
			return preset
	return {}


## Inspector enum hint for [member AppReleaseTarget.export_preset].
static func preset_name_hint() -> String:
	var names: PackedStringArray = []
	for preset in list_presets():
		var preset_name: String = preset["name"]
		if not preset_name.is_empty():
			names.append(preset_name.replace(",", " "))
	return ",".join(names)


## Android export format: a plain APK.
const FORMAT_APK: int = 0
## Android export format: an Android App Bundle, the format Google Play wants.
const FORMAT_AAB: int = 1

const _ANDROID_EXPORT_FORMAT_KEYS: PackedStringArray = [
	"gradle_build/export_format",
	"export_format",
]

## Falls back to the export path's extension when the preset does not say.
static func get_android_export_format(preset: Dictionary) -> int:
	if preset.is_empty():
		return FORMAT_APK
	var options: Dictionary = preset["options"]
	for key in _ANDROID_EXPORT_FORMAT_KEYS:
		if options.has(key):
			return int(options[key])
	return FORMAT_AAB if str(preset["export_path"]).get_extension().to_lower() == "aab" else FORMAT_APK


static func get_first_preset_for_platform(platform: String, android_export_format_id: int = -1) -> Dictionary:
	for preset in list_presets():
		if preset["platform"] != platform:
			continue
		if android_export_format_id >= 0 and get_android_export_format(preset) != android_export_format_id:
			continue
		return preset
	return {}


static func bundle_identifier_of(preset: Dictionary) -> String:
	if preset.is_empty():
		return ""
	var options: Dictionary = preset["options"]
	if preset["platform"] == AppReleaseStrings.platform_ios:
		return str(options.get("application/bundle_identifier", ""))
	if preset["platform"] == AppReleaseStrings.platform_android:
		return str(options.get("package/unique_name", ""))
	return ""


static func apple_team_id_of(preset: Dictionary) -> String:
	if preset.is_empty() or preset["platform"] != AppReleaseStrings.platform_ios:
		return ""
	var options: Dictionary = preset["options"]
	return str(options.get("application/app_store_team_id", ""))


## [code]{version, build}[/code] the Release panel pre-fills its fields with.
static func version_of(preset: Dictionary) -> Dictionary:
	var fallback := {"version": AppReleaseStrings.placeholder_version, "build": 1}
	if preset.is_empty():
		return fallback
	var options: Dictionary = preset["options"]
	var version := str(options.get("version/name", options.get("application/short_version", "")))
	var build := int(options.get("version/code", int(str(options.get("application/version", "0")))))
	if version.is_empty():
		version = fallback["version"]
	if build <= 0:
		build = 1
	return {"version": version, "build": build}
