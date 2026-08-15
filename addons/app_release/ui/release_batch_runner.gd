@tool
class_name AppReleaseBatchRunner
extends RefCounted

signal log_appended(text: String, label: String)
signal log_cleared()
signal status_changed(text: String)
signal runs_changed()

const _EXIT_FILE_GRACE_TICKS := 4
const _POLL_INTERVAL := 0.5

var _config: AppReleaseConfig
var _runs: Dictionary = {}
var _batch_targets: Dictionary = {}
var _batch_export_queue: Dictionary = {}
var _poll_timer: Timer


func _init(timer_parent: Node) -> void:
	_poll_timer = Timer.new()
	_poll_timer.wait_time = _POLL_INTERVAL
	_poll_timer.timeout.connect(_on_poll)
	timer_parent.add_child(_poll_timer, false, Node.INTERNAL_MODE_BACK)


func is_running() -> bool:
	return not _runs.is_empty()


func pid_for(target_id: String) -> int:
	var run: AppReleaseRun = _runs.get(target_id)
	return run.pid if run != null else -1


func running_label(target_id: String) -> String:
	if _config == null:
		return target_id
	var target := _config.find_target(target_id)
	return target.display_label() if target != null else target_id

func start(
	config: AppReleaseConfig, targets: Array[AppReleaseTarget], version: String, build: int,
	notes_file: String, debug_build: bool
) -> bool:
	if config == null or targets.is_empty():
		return false
	_config = config

	var patched_presets: PackedStringArray = []
	for target in targets:
		if target.export_preset in patched_presets:
			continue
		if AppReleaseVersionPatcher.patch(target.export_preset, version, build) != OK:
			status_changed.emit("Could not patch %s — see the Output panel." % target.export_preset)
			return false
		patched_presets.append(target.export_preset)

	for target in targets:
		if AppReleaseRunContext.write_run_env(
			_config, target, version, build, notes_file, debug_build
		) != OK:
			status_changed.emit(AppReleaseStrings.error_start_failed)
			return false
	AppReleaseRunContext.write_run_config(_config)
	log_cleared.emit()

	if targets.size() == 1:
		if _spawn_run(targets[0], "", AppReleaseRun.Phase.SINGLE) == null:
			return false
		_poll_timer.start()
		runs_changed.emit()
		return true

	var batch_id := Time.get_datetime_string_from_system().replace(":", "-")
	var ids: PackedStringArray = []
	for target in targets:
		ids.append(target.target_id())
	_batch_targets[batch_id] = ids
	_batch_export_queue[batch_id] = ids.duplicate()

	_spawn_next_batch_export(batch_id)
	_poll_timer.start()
	runs_changed.emit()
	return true


func stop() -> void:
	for run: AppReleaseRun in _runs.values().duplicate():
		AppReleaseProcess.kill_process_tree(run.pid)
		_read_new_log_output(run)
		log_appended.emit(AppReleaseStrings.log_stopped_by_user, _log_label_for(run))
		_finish_run(run, AppReleaseStrings.status_stopped_format % running_label(run.target_id), false)
	_poll_timer.stop()


func _spawn_next_batch_export(batch_id: String) -> void:
	if not _batch_export_queue.has(batch_id):
		return

	var queue: PackedStringArray = _batch_export_queue[batch_id]
	if queue.is_empty():
		_batch_export_queue.erase(batch_id)
		_start_batch_uploads(batch_id)
		return

	var target_id: String = queue[0]
	queue.remove_at(0)
	_batch_export_queue[batch_id] = queue

	var target := _config.find_target(target_id) if _config != null else null
	if target == null:
		_spawn_next_batch_export(batch_id)
		return

	if _spawn_run(target, batch_id, AppReleaseRun.Phase.EXPORT) == null:
		_abort_batch(batch_id)


func _start_batch_uploads(batch_id: String) -> void:
	var target_ids: PackedStringArray = _batch_targets.get(batch_id, [])
	_batch_targets.erase(batch_id)
	if _config == null:
		return
	for target_id in target_ids:
		var target := _config.find_target(target_id)
		if target != null:
			_spawn_run(target, batch_id, AppReleaseRun.Phase.UPLOAD)


func _abort_batch(batch_id: String) -> void:
	var remaining: PackedStringArray = _batch_export_queue.get(batch_id, [])
	_batch_export_queue.erase(batch_id)
	_batch_targets.erase(batch_id)
	if not remaining.is_empty():
		log_appended.emit("Release group stopped: %d target(s) not started.\n" % remaining.size(), "")


func _spawn_run(
	target: AppReleaseTarget, batch_id: String, phase: AppReleaseRun.Phase
) -> AppReleaseRun:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var run := AppReleaseRun.new()
	run.target_id = target.target_id()
	run.batch_id = batch_id
	run.phase = phase
	run.log_path = _log_path_for(target, phase, timestamp)
	DirAccess.remove_absolute(run.log_path + AppReleaseStrings.exit_code_suffix)

	var arguments: PackedStringArray = [
		AppReleaseRunContext.run_env_path(target.target_id()), run.log_path,
	]
	if phase == AppReleaseRun.Phase.EXPORT:
		arguments.append("export")
	elif phase == AppReleaseRun.Phase.UPLOAD:
		arguments.append("upload")

	var command := AppReleaseProcess.release_command(arguments)
	run.pid = OS.create_process(str(command["executable"]), command["arguments"])
	if run.pid <= 0:
		status_changed.emit(AppReleaseStrings.error_start_failed)
		push_error("App Release: could not start %s." % command["executable"])
		return null

	_runs[run.target_id] = run
	return run


func _log_path_for(target: AppReleaseTarget, phase: AppReleaseRun.Phase, timestamp: String) -> String:
	var logs_root := ProjectSettings.globalize_path(
		AppReleaseStrings.resource_path_prefix
	).path_join(_config.logs_dir)
	DirAccess.make_dir_recursive_absolute(logs_root)
	if phase == AppReleaseRun.Phase.SINGLE:
		return logs_root.path_join(
			AppReleaseStrings.log_file_format % [target.target_id(), timestamp]
		)
	var phase_name := "export" if phase == AppReleaseRun.Phase.EXPORT else "upload"
	return logs_root.path_join(
		AppReleaseStrings.log_file_phase_format % [target.target_id(), phase_name, timestamp]
	)


func _on_poll() -> void:
	for run: AppReleaseRun in _runs.values().duplicate():
		_poll_run(run)
	if _runs.is_empty():
		_poll_timer.stop()


func _poll_run(run: AppReleaseRun) -> void:
	_read_new_log_output(run)
	if run.pid <= 0 or OS.is_process_running(run.pid):
		return

	var exit_code: Variant = _read_exit_code(run)
	if exit_code == null:
		run.exit_wait_ticks += 1
		if run.exit_wait_ticks < _EXIT_FILE_GRACE_TICKS:
			return

	_read_new_log_output(run)
	if exit_code == null:
		_finish_run(
			run, "%s — the release script exited without a status." % running_label(run.target_id), false
		)
		push_error("App Release: no exit status from the release script, see %s" % run.log_path)
		return
	if int(exit_code) == 0:
		_finish_run(run, AppReleaseStrings.status_success_format % running_label(run.target_id), true)
		return
	_finish_run(
		run,
		AppReleaseStrings.status_failed_format % [int(exit_code), running_label(run.target_id)],
		false
	)
	push_error("App Release: release failed, see log: %s" % run.log_path)


func _read_exit_code(run: AppReleaseRun) -> Variant:
	if run.log_path.is_empty():
		return null

	var path := run.log_path + AppReleaseStrings.exit_code_suffix
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text().strip_edges()
	file.close()
	if not text.is_valid_int():
		return null
	return int(text)


func _finish_run(run: AppReleaseRun, status: String, succeeded: bool) -> void:
	_runs.erase(run.target_id)
	status_changed.emit(status)
	runs_changed.emit()

	if run.phase != AppReleaseRun.Phase.EXPORT:
		return
	if succeeded:
		_spawn_next_batch_export(run.batch_id)
	else:
		_abort_batch(run.batch_id)


func _log_label_for(run: AppReleaseRun) -> String:
	return running_label(run.target_id) if _runs.size() > 1 else ""


func _read_new_log_output(run: AppReleaseRun) -> void:
	if run.log_path.is_empty() or not FileAccess.file_exists(run.log_path):
		return
	var file := FileAccess.open(run.log_path, FileAccess.READ)
	if file == null:
		return
	var length := file.get_length()
	if length <= run.log_read_len:
		file.close()
		return
	file.seek(run.log_read_len)
	var new_text := file.get_buffer(length - run.log_read_len).get_string_from_utf8()
	file.close()
	run.log_read_len = length
	log_appended.emit(new_text, _log_label_for(run))
