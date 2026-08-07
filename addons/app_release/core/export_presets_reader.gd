@tool
class_name AppReleasePresets
extends RefCounted

## Read-only access to `res://export_presets.cfg`.
##
## Every target in [AppReleaseConfig] starts by picking a preset from here; the preset
## then supplies the platform, the artifact path and the initial bundle identifier.
## Nothing in this class writes — patching versions is [AppReleaseVersionPatcher]'s job.

## Godot's own `platform=` values mapped onto the plugin's platform ids.
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


static func find_preset(preset_name: String) -> Dictionary:
	if preset_name.is_empty():
		return {}
	for preset in list_presets():
		if preset["name"] == preset_name:
			return preset
	return {}


static func preset_name_hint() -> String:
	var names: PackedStringArray = []
	for preset in list_presets():
		var preset_name: String = preset["name"]
		if not preset_name.is_empty():
			names.append(preset_name.replace(",", " "))
	return ",".join(names)


const FORMAT_APK: int = 0
const FORMAT_AAB: int = 1

const _ANDROID_EXPORT_FORMAT_KEYS: PackedStringArray = [
	"gradle_build/export_format",
	"export_format",
]

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
