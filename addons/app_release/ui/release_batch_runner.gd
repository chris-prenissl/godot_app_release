@tool
class_name AppReleaseBatchRunner
extends RefCounted

## Starts release processes and follows them until they exit.
##
## One target runs in a single phase. Several targets run as a [i]batch[/i]: the exports go
## one after another — they all drive the same Godot exporter and the same
## [code]export_presets.cfg[/code] — and once the last export is done every upload starts
## at once. [AppReleaseBatchPlan] holds that queue, [AppReleaseRun] the state of one
## process.
## [br][br]
## There is no pipe to read from: the script writes its own log file plus an
## [code].exit[/code] sidecar, and this class polls both twice a second, emitting whatever
## is new. That is also why a run that vanishes without writing a status is reported as a
## failure rather than a success.

## New output appeared in a run's log.
signal log_appended(text: String, target_id: String, label: String)
## A new release started; the panel should clear the log views.
signal log_cleared()
## A batch was queued. Carries every target id in it, so the panel can show the ones that
## are still waiting for their turn.
signal batch_queued(target_ids: PackedStringArray)
## Status line changed.
signal status_changed(text: String)
## A run started or finished; buttons and PID fields need refreshing.
signal runs_changed()

## How a run ended.
enum Outcome { SUCCEEDED, FAILED, CANCELLED }

## Polls to wait for the [code].exit[/code] file after the process is gone, before calling
## the run statusless. The script writes the log and the status separately.
const _EXIT_FILE_GRACE_TICKS := 4
const _POLL_INTERVAL := 0.5

## Test seam: replaces [method OS.create_process]. Receives the [AppReleaseRun] and returns
## a pid.
var spawn_hook: Callable = Callable()
## Test seam: replaces [method AppReleaseShell.kill_process_tree]. Receives a pid.
var kill_hook: Callable = Callable()

var _config: AppReleaseConfig
var _runs: Dictionary = {}
var _plan := AppReleaseBatchPlan.new()
var _batch_id: String = ""
var _stopping := false
var _poll_timer: Timer


func _init(timer_parent: Node) -> void:
	_poll_timer = Timer.new()
	_poll_timer.wait_time = _POLL_INTERVAL
	_poll_timer.timeout.connect(_on_poll)
	timer_parent.add_child(_poll_timer, false, Node.INTERNAL_MODE_BACK)


func is_running() -> bool:
	return not _runs.is_empty()


func is_target_running(target_id: String) -> bool:
	return _runs.has(target_id)


func pid_for(target_id: String) -> int:
	var run: AppReleaseRun = _runs.get(target_id)
	return run.pid if run != null else -1


func running_label(target_id: String) -> String:
	if _config == null:
		return target_id
	var target := _config.find_target(target_id)
	return target.display_label() if target != null else target_id

## Patches the version into the presets and writes a [code]run.env[/code] per target, then
## hands over to [method launch].
func start(
	config: AppReleaseConfig, targets: Array[AppReleaseTarget], version: String, build: int,
	notes_file: String
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
		if AppReleaseRunFiles.write_run_env(
			_config, target, version, build, notes_file
		) != OK:
			status_changed.emit(AppReleaseStrings.error_start_failed)
			return false
	AppReleaseRunFiles.write_run_config(_config)

	return launch(config, targets)

## Starts the processes from the [code]run.env[/code] files already on disk — no patching,
## so it re-runs a previously written configuration.
func launch(config: AppReleaseConfig, targets: Array[AppReleaseTarget]) -> bool:
	if config == null or targets.is_empty():
		return false
	_config = config
	_stopping = false
	log_cleared.emit()

	if targets.size() == 1:
		if _spawn_run(targets[0], "", AppReleaseRun.Phase.SINGLE) == null:
			return false
		_poll_timer.start()
		runs_changed.emit()
		return true

	_batch_id = Time.get_datetime_string_from_system().replace(":", "-")
	var ids: PackedStringArray = []
	for target in targets:
		ids.append(target.target_id())
	_plan.open(_batch_id, ids)
	batch_queued.emit(ids)

	_spawn_next_batch_export(_batch_id)
	_poll_timer.start()
	runs_changed.emit()
	return true


func stop_target(target_id: String) -> void:
	var run: AppReleaseRun = _runs.get(target_id)
	if run == null:
		return

	_kill(run.pid)
	_read_new_log_output(run)
	log_appended.emit(
		AppReleaseStrings.log_stopped_by_user, run.target_id, running_label(run.target_id)
	)
	_plan.drop_target(run.batch_id, run.target_id)
	_finish_run(run, AppReleaseStrings.status_stopped_format % running_label(run.target_id),
		Outcome.CANCELLED)

func running_warning() -> String:
	if _runs.is_empty():
		return ""
	var labels: PackedStringArray = []
	for target_id: String in _runs:
		labels.append(running_label(target_id))
	return AppReleaseStrings.warning_quit_while_running_format % ", ".join(labels)


func kill_all_processes() -> void:
	for run: AppReleaseRun in _runs.values():
		_kill(run.pid)
	_runs.clear()
	_plan.abort(_batch_id)
	if _poll_timer != null and is_instance_valid(_poll_timer):
		_poll_timer.stop()


func stop() -> void:
	_stopping = true
	for target_id: String in _runs.keys().duplicate():
		stop_target(target_id)
	_abort_batch(_batch_id)
	_stopping = false
	_poll_timer.stop()


func _spawn_next_batch_export(batch_id: String) -> void:
	if not _plan.has_batch(batch_id):
		return

	var target_id := _plan.next_export(batch_id)
	if target_id.is_empty():
		_start_batch_uploads(batch_id)
		return

	var target := _config.find_target(target_id) if _config != null else null
	if target == null:
		_spawn_next_batch_export(batch_id)
		return

	if _spawn_run(target, batch_id, AppReleaseRun.Phase.EXPORT) == null:
		_abort_batch(batch_id)


func _start_batch_uploads(batch_id: String) -> void:
	var target_ids := _plan.upload_targets(batch_id)
	if _config == null:
		return
	for target_id in target_ids:
		var target := _config.find_target(target_id)
		if target != null:
			_spawn_run(target, batch_id, AppReleaseRun.Phase.UPLOAD)


func _abort_batch(batch_id: String) -> void:
	for target_id in _plan.abort(batch_id):
		log_appended.emit(
			AppReleaseStrings.log_not_started, target_id, running_label(target_id)
		)


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

	run.pid = _launch_process(run, target)
	if run.pid <= 0:
		status_changed.emit(AppReleaseStrings.error_start_failed)
		return null

	_runs[run.target_id] = run
	return run


func _launch_process(run: AppReleaseRun, target: AppReleaseTarget) -> int:
	if spawn_hook.is_valid():
		return int(spawn_hook.call(run))

	DirAccess.make_dir_recursive_absolute(run.log_path.get_base_dir())

	var arguments: PackedStringArray = [
		AppReleaseRunFiles.run_env_path(target.target_id()), run.log_path,
	]
	if run.phase == AppReleaseRun.Phase.EXPORT:
		arguments.append("export")
	elif run.phase == AppReleaseRun.Phase.UPLOAD:
		arguments.append("upload")

	var command := AppReleaseShell.release_command(arguments)
	var pid := OS.create_process(str(command["executable"]), command["arguments"])
	if pid <= 0:
		push_error("App Release: could not start %s." % command["executable"])
	return pid


func _kill(pid: int) -> void:
	if kill_hook.is_valid():
		kill_hook.call(pid)
		return
	AppReleaseShell.kill_process_tree(pid)


func _log_path_for(target: AppReleaseTarget, phase: AppReleaseRun.Phase, timestamp: String) -> String:
	var logs_root := ProjectSettings.globalize_path(
		AppReleaseStrings.resource_path_prefix
	).path_join(_config.logs_dir)
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
			run, "%s — the release script exited without a status." % running_label(run.target_id),
			Outcome.FAILED
		)
		push_error("App Release: no exit status from the release script, see %s" % run.log_path)
		return
	if int(exit_code) == 0:
		_finish_run(
			run, AppReleaseStrings.status_success_format % running_label(run.target_id),
			Outcome.SUCCEEDED
		)
		return
	_finish_run(
		run,
		AppReleaseStrings.status_failed_format % [int(exit_code), running_label(run.target_id)],
		Outcome.FAILED
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


func _finish_run(run: AppReleaseRun, status: String, outcome: Outcome) -> void:
	_runs.erase(run.target_id)
	status_changed.emit(status)

	if run.phase == AppReleaseRun.Phase.EXPORT and not _stopping:
		if outcome == Outcome.FAILED:
			_abort_batch(run.batch_id)
		else:
			_spawn_next_batch_export(run.batch_id)

	runs_changed.emit()


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
	log_appended.emit(new_text, run.target_id, running_label(run.target_id))
