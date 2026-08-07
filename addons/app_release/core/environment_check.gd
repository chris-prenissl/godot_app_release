@tool
class_name AppReleaseEnvironment
extends RefCounted

## Inspects the machine and the project, and reports what still needs doing.
##
## Everything here is local: version probes and file existence, no network calls.
## Each entry is `{name, ok, detail, hint}` and is rendered as one row of the
## Setup tab's checklist.

enum Level {OK, WARNING, ERROR}


## Full checklist: tooling first, then project files, then per-target validation.
static func run(config: AppReleaseConfig) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append_array(check_tools())
	results.append_array(check_project_files(config))
	results.append_array(check_targets(config))
	return results


static func check_tools() -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	if AppReleaseProcess.is_windows():
		results.append(_entry(
			"PowerShell",
			AppReleaseProcess.has_command("powershell.exe"),
			"Runs the bundled release script.",
			"PowerShell ships with Windows; check your PATH if this fails."
		))
		results.append(_entry(
			"iOS support",
			false,
			"iOS targets need macOS with Xcode; Android targets work here.",
			"Run iOS releases from a Mac.",
			Level.WARNING
		))
	else:
		results.append(_entry(
			"bash",
			AppReleaseProcess.has_command("bash"),
			"Runs the bundled release script.",
			"Install bash, or run releases from a terminal instead."
		))

	var ruby := AppReleaseProcess.probe_version("ruby")
	var ruby_major := AppReleaseProcess.ruby_major_version(ruby)
	results.append(_entry(
		"Ruby",
		ruby_major >= 3,
		ruby if not ruby.is_empty() else "Not found.",
		"Install Ruby 3 or newer (brew install ruby) — fastlane cannot run on macOS's system Ruby 2.6."
	))

	var bundler := AppReleaseProcess.probe_version("bundle")
	results.append(_entry(
		"Bundler", not bundler.is_empty(), bundler,
		"gem install bundler"
	))

	var fastlane := AppReleaseProcess.probe_version("fastlane", ["--version"])
	results.append(_entry(
		"fastlane", not fastlane.is_empty(), fastlane,
		"brew install fastlane, or gem install fastlane"
	))

	if AppReleaseProcess.is_macos():
		var xcode := AppReleaseProcess.probe_version("/usr/bin/xcodebuild", ["-version"])
		results.append(_entry(
			"Xcode", not xcode.is_empty(), xcode,
			"Install Xcode from the App Store — required for iOS targets only.",
			Level.WARNING
		))

	var godot := OS.get_executable_path()
	results.append(_entry(
		"Godot binary", FileAccess.file_exists(godot), godot,
		"Set a Godot binary override in release_config.tres."
	))

	return results


static func check_project_files(config: AppReleaseConfig) -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	results.append(_entry(
		"export_presets.cfg",
		not AppReleasePresets.list_presets().is_empty(),
		"%d preset(s) found." % AppReleasePresets.list_presets().size(),
		"Add an export preset under Project > Export first."
	))

	results.append(_entry(
		"release_config.tres",
		config != null,
		str(AppReleaseStrings.config_resource_path) if config != null else "Not created yet.",
		"Press \"Create config\" at the top."
	))

	var scaffolded := AppReleaseScaffolder.is_fastlane_scaffolded()
	results.append(_entry(
		"fastlane files",
		scaffolded,
		"Gemfile + fastlane/{Fastfile,Appfile,Pluginfile}" if scaffolded else "Missing.",
		"Press \"Install release scripts\" at the top."
	))

	results.append(_entry(
		"Ruby gems installed",
		AppReleaseProcess.are_gems_installed(),
		"bundle check",
		"Press \"Install release scripts\" at the top."
	))

	var env_path := ProjectSettings.globalize_path("res://fastlane/.env")
	results.append(_entry(
		"fastlane/.env",
		FileAccess.file_exists(env_path),
		env_path,
		"Press \"Install release scripts\" at the top, then fill in your store credentials."
	))

	var gitignore_missing := PackedStringArray()
	var gitignore_path := ProjectSettings.globalize_path(AppReleaseStrings.project_gitignore_path)
	if FileAccess.file_exists(gitignore_path):
		var file := FileAccess.open(gitignore_path, FileAccess.READ)
		if file != null:
			var text := file.get_as_text()
			file.close()
			for entry in AppReleaseScaffolder.GITIGNORE_ENTRIES:
				if not entry in text:
					gitignore_missing.append(entry)
	else:
		gitignore_missing = AppReleaseScaffolder.GITIGNORE_ENTRIES
	results.append(_entry(
		".gitignore",
		gitignore_missing.is_empty(),
		"Missing: %s" % ", ".join(gitignore_missing) if not gitignore_missing.is_empty() else "Complete.",
		"Press \"Update .gitignore\" at the top — credentials and logs must stay out of git.",
		Level.WARNING
	))

	return results


static func check_targets(config: AppReleaseConfig) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if config == null:
		return results

	if config.enabled_targets().is_empty():
		results.append(_entry(
			"Targets", false, "No enabled targets.",
			"Open release_config.tres and add a target, starting with its export preset."
		))
		return results

	var platforms: PackedStringArray = []
	for target in config.enabled_targets():
		if not target.platform in platforms:
			platforms.append(target.platform)
	for platform in platforms:
		var identity_error := config.identity_error(platform)
		var label := "iOS bundle id" if platform == AppReleaseStrings.platform_ios \
			else "Android package name"
		results.append(_entry(
			label,
			identity_error.is_empty(),
			config.bundle_identifier_for(platform) if identity_error.is_empty() else "Not set.",
			"Set it under \"App identity\" in release_config.tres."
		))

	if AppReleaseStrings.platform_ios in platforms:
		results.append(_entry(
			"Apple team id",
			not config.apple_team_id.is_empty(),
			config.apple_team_id if not config.apple_team_id.is_empty() else "Not set.",
			"Set it under \"App identity\" in release_config.tres.",
			Level.WARNING
		))

	for target in config.enabled_targets():
		var error := target.get_configuration_error()
		var detail := error if not error.is_empty() else "%s / %s / %s" % [
			target.export_preset, target.store_id(),
			AppReleaseTarget.BuildMode.keys()[target.build_mode],
		]
		var hint := "Fix this target in release_config.tres."

		if error.is_empty() and target.needs_native_project():
			var native := ProjectSettings.globalize_path(
				AppReleaseStrings.resource_path_prefix + target.native_project_path
			)
			if not (FileAccess.file_exists(native) or DirAccess.dir_exists_absolute(native)):
				results.append(_entry(
					target.display_label(),
					false,
					"Native project missing: %s" % target.native_project_path,
					"Switch the target to \"Regenerate native project\" once to create it.",
					Level.WARNING
				))
				continue

		results.append(_entry(target.display_label(), error.is_empty(), detail, hint))

	return results


static func _entry(
	name: String, ok: bool, detail: String, hint: String, fail_level: Level = Level.ERROR
) -> Dictionary:
	return {
		"name": name,
		"ok": ok,
		"level": Level.OK if ok else fail_level,
		"detail": detail,
		"hint": "" if ok else hint,
	}
