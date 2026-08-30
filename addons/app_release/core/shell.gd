@tool
class_name AppReleaseShell
extends RefCounted

## The one place in the plugin that knows which operating system it is running on.
##
## Everything else deals in "run this script with these arguments" and lets this
## class pick the interpreter, assemble a usable [code]PATH[/code], and tear a process tree
## down again.
## [br][br]
## The [code]*_command[/code] methods return
## [code]{"executable": String, "arguments": PackedStringArray}[/code], ready for
## [method OS.create_process].

const _BASH_CANDIDATES: PackedStringArray = [
	"/bin/bash",
	"/usr/bin/bash",
	"/usr/local/bin/bash",
	"/opt/homebrew/bin/bash",
	"bash",
]

const _POWERSHELL_CANDIDATES: PackedStringArray = [
	"powershell.exe",
	"pwsh.exe",
]

const _PATH_CANDIDATES_FOR_RUBY: PackedStringArray = [
	"~/.rbenv/shims",
	"~/.rbenv/bin",
	"~/.rvm/bin",
	"~/.asdf/shims",
	"/opt/homebrew/opt/ruby/bin",
	"/opt/homebrew/bin",
	"/opt/homebrew/sbin",
	"/usr/local/opt/ruby/bin",
	"/usr/local/bin",
	"~/.local/bin",
	"~/bin",
	"/usr/bin",
	"/bin",
]


static func is_windows() -> bool:
	return OS.get_name() == "Windows"


static func is_macos() -> bool:
	return OS.get_name() == "macOS"


static func release_command(arguments: PackedStringArray) -> Dictionary:
	var script_name := (
		AppReleaseStrings.release_script_windows if is_windows()
		else AppReleaseStrings.release_script_posix
	)
	var script_path := ProjectSettings.globalize_path(
		"%s/%s" % [AppReleaseStrings.addon_dir(), script_name]
	)

	if is_windows():
		var argv: PackedStringArray = [
			"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path,
		]
		argv.append_array(arguments)
		return {"executable": _first_available(_POWERSHELL_CANDIDATES), "arguments": argv}

	var posix_argv: PackedStringArray = [script_path]
	posix_argv.append_array(arguments)
	return {"executable": _first_available(_BASH_CANDIDATES), "arguments": posix_argv}


static func fetch_command(
	store_id: String,
	output_path: String,
	stderr_path: String,
	extra_path_entries: PackedStringArray = PackedStringArray(),
) -> Dictionary:
	var root := ProjectSettings.globalize_path(AppReleaseStrings.resource_path_prefix)
	var script_path := ProjectSettings.globalize_path(
		"%s/%s" % [AppReleaseStrings.addon_dir(), AppReleaseStrings.list_releases_script]
	)
	var path_value := build_ruby_paths_sorted_by_usability(extra_path_entries)
	var command := "bundle exec ruby %s %s %s > %s 2>&1" % [
		_quote(script_path), _quote(store_id), _quote(output_path), _quote(stderr_path),
	]

	if is_windows():
		var argv: PackedStringArray = [
			"-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
			"$env:PATH = %s; Set-Location %s; %s" % [
				_quote(path_value), _quote(root), command,
			],
		]
		return {"executable": _first_available(_POWERSHELL_CANDIDATES), "arguments": argv}

	var posix_argv: PackedStringArray = [
		"-c", "export PATH=%s; cd %s && %s" % [_quote(path_value), _quote(root), command],
	]
	return {"executable": _first_available(_BASH_CANDIDATES), "arguments": posix_argv}


static func bundle_install_command(
	log_path: String, extra_path_entries: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var root := ProjectSettings.globalize_path(AppReleaseStrings.resource_path_prefix)
	var path_value := build_ruby_paths_sorted_by_usability(extra_path_entries)
	var command := "bundle install > %s 2>&1" % _quote(log_path)

	if is_windows():
		var argv: PackedStringArray = [
			"-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
			"$env:PATH = %s; Set-Location %s; %s" % [
				_quote(path_value), _quote(root), command,
			],
		]
		return {"executable": _first_available(_POWERSHELL_CANDIDATES), "arguments": argv}

	var posix_argv: PackedStringArray = [
		"-c", "export PATH=%s; cd %s && %s" % [_quote(path_value), _quote(root), command],
	]
	return {"executable": _first_available(_BASH_CANDIDATES), "arguments": posix_argv}


## Kills [param pid] [b]and every descendant[/b] — killing only the shell would leave the
## export or fastlane running.
static func kill_process_tree(pid: int) -> void:
	if pid <= 0:
		return
	if is_windows():
		OS.execute("taskkill.exe", ["/T", "/F", "/PID", str(pid)])
		return
	for child_pid in _child_pids(pid):
		kill_process_tree(child_pid)
	OS.kill(pid)


## [code]PATH[/code] for child processes, with pre-3 Ruby directories demoted. The editor
## hands children a minimal [code]PATH[/code], so this is what makes [code]bundle[/code]
## findable at all.
static func build_ruby_paths_sorted_by_usability(extra_entries: PackedStringArray) -> String:
	var preferred: PackedStringArray = []
	var demoted: PackedStringArray = []

	var candidates: PackedStringArray = []
	candidates.append_array(extra_entries)
	candidates.append_array(_PATH_CANDIDATES_FOR_RUBY)

	var inherited := OS.get_environment("PATH")
	if not inherited.is_empty():
		candidates.append_array(inherited.split(_path_separator(), false))

	for candidate in candidates:
		var expanded := candidate.replace("~", OS.get_environment("HOME"))
		if expanded.is_empty() or expanded in preferred or expanded in demoted:
			continue
		if not DirAccess.dir_exists_absolute(expanded):
			continue
		if _ruby_dir_is_usable(expanded):
			preferred.append(expanded)
		else:
			demoted.append(expanded)

	preferred.append_array(demoted)
	return _path_separator().join(preferred)


const _MINIMUM_RUBY_MAJOR: int = 3
static var _ruby_dir_cache: Dictionary = {}

static func _ruby_dir_is_usable(directory: String) -> bool:
	if _ruby_dir_cache.has(directory):
		return _ruby_dir_cache[directory]

	var usable := true
	var ruby := directory.path_join("ruby")
	if FileAccess.file_exists(ruby):
		var output: Array = []
		var code := OS.execute(ruby, ["--version"], output, true)
		var text := "\n".join(PackedStringArray(output)).strip_edges()
		usable = code == 0 and ruby_major_version(text) >= _MINIMUM_RUBY_MAJOR

	_ruby_dir_cache[directory] = usable
	return usable


static func ruby_major_version(version_text: String) -> int:
	var regex := RegEx.new()
	if regex.compile("ruby (\\d+)\\.") != OK:
		return 0
	var found := regex.search(version_text)
	return int(found.get_string(1)) if found != null else 0


static func godot_binary(override_path: String) -> String:
	return override_path if not override_path.is_empty() else OS.get_executable_path()

static func has_command(command: String) -> bool:
	return not _resolve_command(command).is_empty()


## First line of [code]<command> --version[/code], or empty when it is missing or fails.
static func probe_version(command: String, arguments: PackedStringArray = ["--version"]) -> String:
	var resolved := _resolve_command(command)
	if resolved.is_empty():
		return ""
	var output: Array = []
	if OS.execute(resolved, arguments, output, true) != 0:
		return ""
	var text := "\n".join(PackedStringArray(output)).strip_edges()
	return text.split("\n", false)[0] if not text.is_empty() else ""


static func _resolve_command(command: String) -> String:
	if command.is_absolute_path():
		return command if FileAccess.file_exists(command) else ""

	for directory in build_ruby_paths_sorted_by_usability(PackedStringArray()).split(_path_separator(), false):
		var candidate := directory.path_join(command)
		if FileAccess.file_exists(candidate):
			return candidate

	var locator := "where.exe" if is_windows() else "/usr/bin/which"
	var output: Array = []
	if OS.execute(locator, [command], output, true) == 0:
		var found := "\n".join(PackedStringArray(output)).strip_edges().split("\n", false)
		if not found.is_empty():
			return found[0].strip_edges()
	return ""

static func are_gems_installed() -> bool:
	var bundle := _resolve_command("bundle")
	if bundle.is_empty():
		return false
	var root := ProjectSettings.globalize_path(AppReleaseStrings.resource_path_prefix)
	if not FileAccess.file_exists(root.path_join("Gemfile")):
		return false
	var output: Array = []
	var command := "export PATH=%s; cd %s && bundle check" % [
		_quote(build_ruby_paths_sorted_by_usability(PackedStringArray())), _quote(root),
	]
	return OS.execute(_first_available(_BASH_CANDIDATES), ["-c", command], output, true) == 0


static func _child_pids(pid: int) -> PackedInt32Array:
	var pids: PackedInt32Array = []
	var output: Array = []
	
	OS.execute("/usr/bin/pgrep", ["-P", str(pid)], output, true)
	for line in "\n".join(PackedStringArray(output)).split("\n", false):
		var child_pid := int(line.strip_edges())
		if child_pid > 0:
			pids.append(child_pid)
	return pids


static func _first_available(candidates: PackedStringArray) -> String:
	for candidate in candidates:
		if candidate.is_absolute_path():
			if FileAccess.file_exists(candidate):
				return candidate
		else:
			return candidate
	return candidates[candidates.size() - 1]


static func _path_separator() -> String:
	return ";" if is_windows() else ":"


static func _quote(value: String) -> String:
	if is_windows():
		return "'%s'" % value.replace("'", "''")
	return "'%s'" % value.replace("'", "'\\''")
