@tool
class_name AppReleaseStoreFetcher
extends RefCounted

## Loads each store's recent releases, so you can see which build numbers are taken.
##
## Runs [code]scripts/list_releases.rb[/code] one subprocess at a time, draining a queue for
## [method fetch_all] or jumping the queue for a single [method fetch_one] request (e.g. a
## column's own [b]Fetch[/b] button). Results are read back from
## [code].release_tools/releases_<store>.json[/code], errors from the [code].err[/code]
## file beside it.

## Status text for one store's column changed.
signal store_status_changed(store_id: String, text: String)
## A store's release list arrived. [param rows] is the parsed JSON.
signal store_fetched(store_id: String, rows: Array)
## A fetch failed; [param error] is the short version, the full stderr is in the
## [code].err[/code] file.
signal fetch_failed(store_id: String, error: String)

const _POLL_INTERVAL := 0.5

var _config: AppReleaseConfig
var _timer: Timer
var _pid := -1
var _store_id := ""
var _out_path := ""
var _queue: PackedStringArray = []


func _init(timer_parent: Node) -> void:
	_timer = Timer.new()
	_timer.wait_time = _POLL_INTERVAL
	_timer.timeout.connect(_on_poll)
	timer_parent.add_child(_timer, false, Node.INTERNAL_MODE_BACK)


func fetch_all(store_ids: PackedStringArray, config: AppReleaseConfig) -> void:
	_config = config
	_queue = store_ids
	if _pid <= 0 and not _queue.is_empty():
		_start(_pop_queue())


## Jumps the queue: [param store_id] is fetched next.
func fetch_one(store_id: String, config: AppReleaseConfig) -> void:
	_config = config
	_start(store_id)


func stop() -> void:
	if _pid > 0:
		if OS.is_process_running(_pid):
			AppReleaseShell.kill_process_tree(_pid)
		_pid = -1
	_queue = PackedStringArray()
	if _timer != null and is_instance_valid(_timer):
		_timer.stop()


func _start(store_id: String) -> void:
	if store_id.is_empty() or _config == null:
		return
	if _pid > 0:
		if OS.is_process_running(_pid):
			AppReleaseShell.kill_process_tree(_pid)
		_pid = -1
		_timer.stop()

	AppReleaseRunFiles.write_run_config(_config)
	_out_path = AppReleaseRunFiles.releases_path(store_id)
	var stderr_path := _out_path + AppReleaseStrings.stderr_suffix
	DirAccess.remove_absolute(_out_path)
	DirAccess.remove_absolute(stderr_path)
	_store_id = store_id

	var command := AppReleaseShell.fetch_command(
		store_id, _out_path, stderr_path, _config.extra_path_entries
	)
	_pid = OS.create_process(str(command["executable"]), command["arguments"])
	if _pid <= 0:
		store_status_changed.emit(store_id, AppReleaseStrings.status_error_format % "cannot start ruby")
		return
	store_status_changed.emit(store_id, AppReleaseStrings.status_fetching)
	_timer.start()


func _on_poll() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		return
	_timer.stop()
	_pid = -1

	var rows: Array = []
	var error := ""
	var file := FileAccess.open(_out_path, FileAccess.READ)
	if file == null:
		error = "list_releases.rb wrote no output: %s" % _read_stderr()
	else:
		var text := file.get_as_text()
		file.close()
		var data: Variant = JSON.parse_string(text)
		if data == null or not data is Dictionary:
			error = "invalid JSON from list_releases.rb: %s" % _read_stderr()
		elif data.has("error"):
			error = str(data["error"])
		else:
			rows = data.get("releases", [])

	if error.is_empty():
		store_fetched.emit(_store_id, rows)
	else:
		store_status_changed.emit(_store_id, AppReleaseStrings.status_error_format % error)
		fetch_failed.emit(_store_id, error)

	if not _queue.is_empty():
		_start(_pop_queue())


func _pop_queue() -> String:
	if _queue.is_empty():
		return ""
	var next := _queue[0]
	_queue.remove_at(0)
	return next


func _read_stderr() -> String:
	var file := FileAccess.open(_out_path + AppReleaseStrings.stderr_suffix, FileAccess.READ)
	if file == null:
		return AppReleaseStrings.error_no_stderr
	var text := file.get_as_text().strip_edges()
	file.close()
	if text.is_empty():
		return AppReleaseStrings.error_empty_stderr

	var meaningful: PackedStringArray = []
	for raw_line in text.split("\n", false):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("from ") or line.begins_with("/"):
			continue
		meaningful.append(line)
		if meaningful.size() >= 4:
			break
	var summary := "\n".join(meaningful) if not meaningful.is_empty() else text
	return summary.left(600)
