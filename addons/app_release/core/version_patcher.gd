@tool
class_name AppReleaseVersionPatcher
extends RefCounted

## Writes a version name and build number into a single preset of
## [code]res://export_presets.cfg[/code].
##
## Godot rewrites that file itself, so this is a section-aware line rewrite rather
## than a [ConfigFile] round-trip: only the [code][preset.N.options][/code] block belonging
## to the named preset is touched, and every other byte of the file is preserved.
## [br][br]
## Patching before the export is what makes a later manual export from
## [b]Project → Export[/b] produce the same build.

const _VERSION_KEYS: PackedStringArray = ["version/name=", "application/short_version="]
const _BUILD_KEYS: PackedStringArray = ["version/code=", "application/version="]
const _UNQUOTED_BUILD_KEYS: PackedStringArray = ["version/code="]


## Rewrites one preset through a temporary file and a rename, so a crash cannot leave a
## half-written [code]export_presets.cfg[/code] behind.
static func patch(preset_name: String, version: String, build: int) -> Error:
	if preset_name.is_empty():
		push_error("App Release: no preset name given.")
		return ERR_INVALID_PARAMETER
	if not is_valid_version(version):
		push_error("App Release: invalid version \"%s\" (allowed: letters, digits, . _ + -)." % version)
		return ERR_INVALID_PARAMETER
	if build <= 0:
		push_error("App Release: build number must be a positive integer, got %d." % build)
		return ERR_INVALID_PARAMETER

	var preset := AppReleasePresets.find_preset(preset_name)
	if preset.is_empty():
		push_error("App Release: preset \"%s\" is not in export_presets.cfg." % preset_name)
		return ERR_DOES_NOT_EXIST

	var path := ProjectSettings.globalize_path(AppReleaseStrings.export_presets_path)
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		push_error("App Release: cannot read %s (%s)." % [
			path, error_string(FileAccess.get_open_error()),
		])
		return FileAccess.get_open_error()
	var text := source.get_as_text()
	source.close()

	var patched := _patch_text(text, str(preset["options_section"]), version, build)
	if patched == text:
		return OK

	var temp_path := path + ".apprelease.tmp"
	var release_notes_sink := FileAccess.open(temp_path, FileAccess.WRITE)
	if release_notes_sink == null:
		push_error("App Release: cannot write %s (%s)." % [
			temp_path, error_string(FileAccess.get_open_error()),
		])
		return FileAccess.get_open_error()
	release_notes_sink.store_string(patched)
	release_notes_sink.close()

	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		DirAccess.remove_absolute(temp_path)
		push_error("App Release: cannot open %s." % path.get_base_dir())
		return ERR_CANT_OPEN
	var rename_result := dir.rename(temp_path, path)
	if rename_result != OK:
		DirAccess.remove_absolute(temp_path)
		push_error("App Release: cannot replace %s (%s)." % [path, error_string(rename_result)])
	return rename_result


static func is_valid_version(version: String) -> bool:
	if version.is_empty():
		return false
	var regex := RegEx.new()
	if regex.compile(AppReleaseStrings.version_pattern) != OK:
		return false
	return regex.search(version) != null


static func _patch_text(
	text: String, options_section: String, version: String, build: int
) -> String:
	var section_header := "[%s]" % options_section
	var lines := text.split("\n")
	var inside := false

	for i in lines.size():
		var line: String = lines[i]
		var trimmed := line.strip_edges()

		if trimmed.begins_with("[") and trimmed.ends_with("]"):
			inside = trimmed == section_header
			continue
		if not inside:
			continue

		for key in _VERSION_KEYS:
			if trimmed.begins_with(key):
				lines[i] = "%s\"%s\"" % [key, version]
		for key in _BUILD_KEYS:
			if trimmed.begins_with(key):
				if key in _UNQUOTED_BUILD_KEYS:
					lines[i] = "%s%d" % [key, build]
				else:
					lines[i] = "%s\"%d\"" % [key, build]

	return "\n".join(lines)
