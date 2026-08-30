@tool
class_name AppReleaseScaffolder
extends RefCounted

## Creates the files the plugin needs but deliberately does not own.
##
## The fastlane setup is copied into the host project rather than kept inside the
## addon, so lanes stay editable and survive a plugin update. Nothing here ever
## overwrites an existing file — existing paths are reported as skipped.
## [br][br]
## Everything in this class sits behind a button in the Setup tab.

## Template file name to destination, relative to the project root.
const FASTLANE_TEMPLATES: Dictionary = {
	"Gemfile": "Gemfile",
	"Fastfile": "fastlane/Fastfile",
	"Appfile": "fastlane/Appfile",
	"Pluginfile": "fastlane/Pluginfile",
}

## The credentials file. Seeded with placeholders and never overwritten.
const ENV_TEMPLATES: Dictionary = {
	"env.example": "fastlane/.env",
}

## Bundler configuration pinning gems to a project-local [code]vendor/bundle[/code].
const BUNDLER_TEMPLATES: Dictionary = {
	"bundle_config": ".bundle/config",
}

## Agent-facing notes and task guides, copied into the project's [code].agents/[/code].
## Optional — nothing in the plugin reads them.
const AGENT_SKILL_TEMPLATES: Dictionary = {
	"agents/README.md": ".agents/README.md",
	"agents/skills/release-an-app.md": ".agents/skills/release-an-app.md",
	"agents/skills/verify-release-setup.md": ".agents/skills/verify-release-setup.md",
	"agents/skills/troubleshoot-a-release.md": ".agents/skills/troubleshoot-a-release.md",
	"agents/skills/godot-project-basics.md": ".agents/skills/godot-project-basics.md",
}

## Entries [method append_gitignore] makes sure the project's [code].gitignore[/code] holds.
const GITIGNORE_ENTRIES: PackedStringArray = [
	"logs/",
	".release_tools/",
	"fastlane/.env",
	"fastlane/report.xml",
	"fastlane/test_output/",
	"vendor/bundle/",
	".bundle/",
]

const _GITIGNORE_HEADER: String = "# App Release plugin"

static func create_default_config() -> AppReleaseConfig:
	var config := AppReleaseConfig.new()
	config.release_groups = build_default_groups()

	var ios_preset := AppReleasePresets.get_first_preset_for_platform(AppReleaseStrings.platform_ios)
	config.ios_bundle_id = AppReleasePresets.bundle_identifier_of(ios_preset)
	config.apple_team_id = AppReleasePresets.apple_team_id_of(ios_preset)

	var android_preset := AppReleasePresets.get_first_preset_for_platform(
		AppReleaseStrings.platform_android
	)
	config.android_package_name = AppReleasePresets.bundle_identifier_of(android_preset)

	var result := ResourceSaver.save(config, AppReleaseStrings.config_resource_path)
	if result != OK:
		push_error("App Release: cannot write %s (%s)." % [
			AppReleaseStrings.config_resource_path, error_string(result),
		])
		return null
	return config


static func build_default_groups() -> Array[AppReleaseGroup]:
	var test_group := AppReleaseGroup.new()
	test_group.name = "Test"
	var store_group := AppReleaseGroup.new()
	store_group.name = "Store"

	for target in _build_default_targets():
		if target.release_kind_id() == AppReleaseTarget.RELEASE_KIND_STORE:
			store_group.targets.append(target)
		else:
			test_group.targets.append(target)

	var groups: Array[AppReleaseGroup] = []
	if not test_group.targets.is_empty():
		groups.append(test_group)
	if not store_group.targets.is_empty():
		groups.append(store_group)
	return groups


static func _build_default_targets() -> Array[AppReleaseTarget]:
	var targets: Array[AppReleaseTarget] = []

	var ios_preset := AppReleasePresets.get_first_preset_for_platform(AppReleaseStrings.platform_ios)
	if not ios_preset.is_empty():
		targets.append(_make_target(ios_preset, AppReleaseTarget.Store.TESTFLIGHT))
		targets.append(_make_target(ios_preset, AppReleaseTarget.Store.APP_STORE))

	var apk_preset := AppReleasePresets.get_first_preset_for_platform(
		AppReleaseStrings.platform_android, AppReleasePresets.FORMAT_APK
	)
	var aab_preset := AppReleasePresets.get_first_preset_for_platform(
		AppReleaseStrings.platform_android, AppReleasePresets.FORMAT_AAB
	)
	var any_android := AppReleasePresets.get_first_preset_for_platform(AppReleaseStrings.platform_android)
	if apk_preset.is_empty():
		apk_preset = any_android
	if aab_preset.is_empty():
		aab_preset = any_android

	if not apk_preset.is_empty():
		targets.append(_make_target(apk_preset, AppReleaseTarget.Store.FIREBASE))
	if not aab_preset.is_empty():
		targets.append(_make_target(aab_preset, AppReleaseTarget.Store.PLAY, "internal"))
		targets.append(_make_target(aab_preset, AppReleaseTarget.Store.PLAY, "production"))

	return targets

## Returns [code]{"created", "skipped"}[/code]; an existing file is skipped, never
## overwritten.
static func scaffold_fastlane() -> Dictionary:
	var templates: Dictionary = {}
	templates.merge(FASTLANE_TEMPLATES)
	templates.merge(ENV_TEMPLATES)
	templates.merge(BUNDLER_TEMPLATES)
	return copy_templates(templates)


## Same contract as [method scaffold_fastlane], for [constant AGENT_SKILL_TEMPLATES].
static func scaffold_agent_skills() -> Dictionary:
	return copy_templates(AGENT_SKILL_TEMPLATES)


## Copies [param templates] (template name to project-relative destination) into the project.
static func copy_templates(templates: Dictionary) -> Dictionary:
	var created: PackedStringArray = []
	var skipped: PackedStringArray = []

	for template_name: String in templates:
		var destination: String = templates[template_name]
		var destination_path := AppReleaseStrings.resource_path_prefix + destination
		var destination_absolute_path := ProjectSettings.globalize_path(destination_path)

		if FileAccess.file_exists(destination_absolute_path):
			skipped.append(destination)
			continue

		var source_path := "%s/%s/%s" % [
			AppReleaseStrings.addon_dir(), AppReleaseStrings.templates_dir, template_name,
		]
		var source := FileAccess.open(source_path, FileAccess.READ)
		if source == null:
			push_error("App Release: missing template %s." % source_path)
			continue
		var text := source.get_as_text()
		source.close()

		DirAccess.make_dir_recursive_absolute(destination_absolute_path.get_base_dir())
		var destination_file_sink := FileAccess.open(destination_absolute_path, FileAccess.WRITE)
		if destination_file_sink == null:
			push_error("App Release: cannot write %s (%s)." % [
				destination_absolute_path, error_string(FileAccess.get_open_error()),
			])
			continue
		destination_file_sink.store_string(text)
		destination_file_sink.close()
		created.append(destination)

	return {"created": created, "skipped": skipped}


## Entries of [constant GITIGNORE_ENTRIES] that [param gitignore_text] does not already list.
static func missing_gitignore_entries(gitignore_text: String) -> PackedStringArray:
	var present: PackedStringArray = []
	for line in gitignore_text.split("\n", false):
		present.append(line.strip_edges())

	var missing: PackedStringArray = []
	for entry in GITIGNORE_ENTRIES:
		if not entry in present:
			missing.append(entry)
	return missing


## Entries the project's [code].gitignore[/code] is still missing, read from disk.
static func missing_project_gitignore_entries() -> PackedStringArray:
	return missing_gitignore_entries(_read_project_gitignore())


## Adds the missing entries and returns them.
static func append_gitignore() -> PackedStringArray:
	var existing := _read_project_gitignore()
	var missing := missing_gitignore_entries(existing)
	if missing.is_empty():
		return missing

	var appended := existing
	if not appended.is_empty() and not appended.ends_with("\n"):
		appended += "\n"
	appended += "\n%s\n%s\n" % [_GITIGNORE_HEADER, "\n".join(missing)]

	var gitignore_absolute_path := ProjectSettings.globalize_path(
		AppReleaseStrings.project_gitignore_path
	)
	var gitignore_sink := FileAccess.open(gitignore_absolute_path, FileAccess.WRITE)
	if gitignore_sink == null:
		push_error("App Release: cannot write %s (%s)." % [
			gitignore_absolute_path, error_string(FileAccess.get_open_error()),
		])
		return PackedStringArray()
	gitignore_sink.store_string(appended)
	gitignore_sink.close()
	return missing


static func _read_project_gitignore() -> String:
	var path := ProjectSettings.globalize_path(AppReleaseStrings.project_gitignore_path)
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


static func is_fastlane_scaffolded() -> bool:
	return _all_exist(
		FASTLANE_TEMPLATES.values() + ENV_TEMPLATES.values() + BUNDLER_TEMPLATES.values()
	)


static func are_agent_skills_scaffolded() -> bool:
	return _all_exist(AGENT_SKILL_TEMPLATES.values())


static func _all_exist(destinations: Array) -> bool:
	for destination in destinations:
		var absolute := ProjectSettings.globalize_path(
			AppReleaseStrings.resource_path_prefix + str(destination)
		)
		if not FileAccess.file_exists(absolute):
			return false
	return true


static func _make_target(
	preset: Dictionary, store: AppReleaseTarget.Store, track: String = ""
) -> AppReleaseTarget:
	var target := AppReleaseTarget.new()
	target.export_preset = str(preset["name"])
	target.store = store
	target.fastlane_lane = track if not track.is_empty() else AppReleaseTarget.DEFAULT_LANES[store]
	target.play_track = track
	if target.is_ios():
		target.build_mode = AppReleaseTarget.BuildMode.REGENERATE_NATIVE_PROJECT
	else:
		target.build_mode = AppReleaseTarget.BuildMode.GODOT_EXPORT
	return target
