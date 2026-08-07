@tool
extends SceneTree

## Headless entry point: does on a CI runner what the Release panel does locally.
##
##   godot --headless --path . --script addons/app_release/scripts/ci_release.gd -- \
##       --target <id> --version <name> --build <number> [options]
##
## It resolves a target out of release_config.tres, runs the same validation the
## panel runs, patches the version into export_presets.cfg, and writes
## .release_tools/run.env. Then hand that file to the release script:
##
##   bash addons/app_release/scripts/release.sh .release_tools/run.env
##
## run.env is generated here rather than committed because it holds absolute
## paths — PROJECT_ROOT, GODOT_BIN, EXTRA_PATH — that only make sense on the
## machine that wrote it.
##
## Credentials do not need a fastlane/.env on CI: the lanes read plain
## environment variables, and dotenv ignores a missing file. Export your secrets
## as ASC_KEY_ID, PLAY_JSON_KEY_PATH and friends instead.

const _EXIT_OK := 0
const _EXIT_FAILED := 1
const _EXIT_USAGE := 2

func _print_usage() -> void:
	print("""ci_release.gd — write .release_tools/run.env for one target, headlessly.

USAGE
  godot --headless --path . --script addons/app_release/scripts/ci_release.gd -- \\
      --target <id> --version <name> --build <number> [options]

REQUIRED
  --target <id>        Target id from release_config.tres. Use --list to see them.
  --version <name>     Version name, e.g. 1.4.0. Patched into export_presets.cfg.
  --build <number>     Build number / Android version code. Must increase per upload.

OPTIONS
  --notes-file <path>  File holding the release notes.
  --groups <a,b>       Comma-separated tester groups (TestFlight / Firebase only).
  --debug              Export with the debug template. Refused by App Store and Play.
  --list               List the targets and exit.
  --help               Show this text.

EXIT STATUS
  0  run.env written
  1  the target is misconfigured, or a file could not be written
  2  bad invocation

CREDENTIALS
  No fastlane/.env is needed: the lanes read plain environment variables and
  dotenv ignores a missing file. Export ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH,
  PLAY_JSON_KEY_PATH, FIREBASE_APP_ID_ANDROID and FIREBASE_SERVICE_CREDENTIALS
  from your CI secrets instead.

  Android signing also needs GODOT_ANDROID_KEYSTORE_RELEASE_PATH (absolute — the
  shell will not expand ~), _USER and _PASSWORD, because a runner has no Godot
  Editor Settings to read the keystore from.""")

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()

	if arguments.is_empty() or "--help" in arguments or "-h" in arguments:
		_print_usage()
		quit(_EXIT_OK if not arguments.is_empty() else _EXIT_USAGE)
		return

	var options := _parse_options(arguments)
	if options.is_empty():
		quit(_EXIT_USAGE)
		return

	var config := AppReleaseConfig.load_project_config()
	if config == null:
		_fail("no %s in this project." % AppReleaseStrings.config_resource_path)
		quit(_EXIT_FAILED)
		return

	if options.has("list"):
		_print_targets(config)
		quit(_EXIT_OK)
		return

	quit(_run(config, options))


func _run(config: AppReleaseConfig, options: Dictionary) -> int:
	for required in ["target", "version", "build"]:
		if not options.has(required):
			_fail("--%s is required." % required)
			return _EXIT_USAGE

	var target := config.find_target(str(options["target"]))
	if target == null:
		_fail("no target with id \"%s\"." % options["target"])
		_print_targets(config)
		return _EXIT_USAGE

	var error := target.get_configuration_error()
	if error.is_empty():
		error = config.identity_error(target.platform)
	if not error.is_empty():
		_fail("%s: %s" % [target.display_label(), error])
		return _EXIT_FAILED

	var version := str(options["version"])
	var build := int(options["build"])
	if not AppReleaseVersionPatcher.is_valid_version(version):
		_fail("invalid --version \"%s\" (letters, digits, dot, underscore, plus, hyphen)." % version)
		return _EXIT_USAGE
	if build <= 0:
		_fail("--build must be a positive integer, got \"%s\"." % options["build"])
		return _EXIT_USAGE

	if AppReleaseVersionPatcher.patch(target.export_preset, version, build) != OK:
		_fail("could not patch preset \"%s\" — see the errors above." % target.export_preset)
		return _EXIT_FAILED


	var notes_file := ""
	if options.has("notes-file"):
		notes_file = ProjectSettings.globalize_path(str(options["notes-file"]))
		if not FileAccess.file_exists(notes_file):
			_fail("--notes-file not found: %s" % notes_file)
			return _EXIT_USAGE

	var groups := str(options.get("groups", ""))
	var debug_build := options.has("debug")

	var write_result := AppReleaseRunContext.write_run_env(
		config, target, version, build, notes_file, groups, debug_build
	)
	if write_result != OK:
		_fail("could not write run.env (%s)." % error_string(write_result))
		return _EXIT_FAILED
	AppReleaseRunContext.write_run_config(config)

	print("Target:     %s" % target.display_label())
	print("Preset:     %s [%s]" % [target.export_preset, target.platform])
	print("Build mode: %s" % AppReleaseTarget.BuildMode.keys()[target.build_mode])
	print("Version:    %s (build %d)" % [version, build])
	print("Wrote:      %s" % AppReleaseRunContext.run_env_path())
	print("")
	print("Next: bash %s/%s %s" % [
		_addon_project_path(),
		AppReleaseStrings.release_script_posix,
		_project_relative(AppReleaseRunContext.run_env_path()),
	])
	return _EXIT_OK


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	const SWITCHES: PackedStringArray = ["debug", "list"]
	var options: Dictionary = {}
	var index := 0

	while index < arguments.size():
		var argument := arguments[index]
		if not argument.begins_with("--"):
			_fail("unexpected argument \"%s\"." % argument)
			return {}

		var name := argument.substr(2)
		if name in SWITCHES:
			options[name] = true
			index += 1
			continue

		if index + 1 >= arguments.size():
			_fail("--%s needs a value." % name)
			return {}
		options[name] = arguments[index + 1]
		index += 2

	return options


func _print_targets(config: AppReleaseConfig) -> void:
	print("Targets in %s:" % AppReleaseStrings.config_resource_path)
	for target in config.enabled_targets():
		var error := target.get_configuration_error()
		print("  %-24s %s%s" % [
			target.target_id(),
			target.display_label(),
			"" if error.is_empty() else "   [unusable: %s]" % error,
		])


func _addon_project_path() -> String:
	return _project_relative(AppReleaseStrings.addon_dir())


func _project_relative(path: String) -> String:
	var trimmed := path.trim_prefix(AppReleaseStrings.resource_path_prefix)
	var resource_root := ProjectSettings.globalize_path(AppReleaseStrings.resource_path_prefix)
	return trimmed.trim_prefix(resource_root)


func _fail(message: String) -> void:
	printerr("ci_release: %s" % message)
