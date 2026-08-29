extends GutTest


const _Phase := AppReleaseRun.Phase
const _Outcome := AppReleaseBatchRunner.Outcome

var _runner: AppReleaseBatchRunner
var _config: AppReleaseConfig
var _targets: Array[AppReleaseTarget] = []

var _spawns: Array[Dictionary] = []
var _kills: Array[int] = []
var _next_pid := 1000


func before_each() -> void:
	_spawns = []
	_kills = []
	_next_pid = 1000
	_targets = [
		_make_target("PresetA", "Alpha"),
		_make_target("PresetB", "Beta"),
		_make_target("PresetC", "Gamma"),
	]
	_config = _make_config(_targets)

	_runner = AppReleaseBatchRunner.new(add_child_autofree(Node.new()))
	_runner.spawn_hook = _record_spawn
	_runner.kill_hook = func(pid: int) -> void: _kills.append(pid)


func _make_target(preset: String, label: String) -> AppReleaseTarget:
	var target := AppReleaseTarget.new()
	target.export_preset = preset
	target.label = label
	return target


func _make_config(targets: Array[AppReleaseTarget]) -> AppReleaseConfig:
	var group := AppReleaseGroup.new()
	group.name = "Test group"
	group.targets = targets

	var config := AppReleaseConfig.new()
	config.release_groups = [group]
	return config


func _record_spawn(run: AppReleaseRun) -> int:
	_next_pid += 1
	_spawns.append({"target_id": run.target_id, "phase": run.phase, "pid": _next_pid})
	return _next_pid


func _launch(targets: Array[AppReleaseTarget]) -> bool:
	var started := _runner.launch(_config, targets)
	_runner._poll_timer.stop()
	return started


func _finish(target_id: String, outcome: AppReleaseBatchRunner.Outcome) -> void:
	_runner._finish_run(_runner._runs[target_id], "", outcome)


func _spawned(phase: AppReleaseRun.Phase) -> Array:
	return _spawns.filter(
		func(entry: Dictionary) -> bool: return entry["phase"] == phase
	).map(func(entry: Dictionary) -> String: return entry["target_id"])


func _id(index: int) -> String:
	return _targets[index].target_id()


func test_a_batch_starts_exactly_one_export() -> void:
	_launch(_targets)
	assert_eq(_spawned(_Phase.EXPORT), [_id(0)], "only the first target may export")
	assert_eq(_spawned(_Phase.UPLOAD), [], "nothing uploads before the exports are done")


func test_the_next_export_starts_only_after_the_previous_one_succeeded() -> void:
	_launch(_targets)
	_finish(_id(0), _Outcome.SUCCEEDED)
	assert_eq(_spawned(_Phase.EXPORT), [_id(0), _id(1)])
	assert_eq(_spawned(_Phase.UPLOAD), [])


func test_only_one_export_runs_at_a_time() -> void:
	_launch(_targets)
	_finish(_id(0), _Outcome.SUCCEEDED)
	assert_eq(_runner._runs.size(), 1)


func test_every_upload_starts_once_the_last_export_is_done() -> void:
	_launch(_targets)
	for index in 3:
		_finish(_id(index), _Outcome.SUCCEEDED)

	assert_eq(_spawned(_Phase.UPLOAD), [_id(0), _id(1), _id(2)])
	assert_eq(_runner._runs.size(), 3, "uploads run concurrently")


func test_a_failed_export_aborts_the_whole_group() -> void:
	_launch(_targets)
	_finish(_id(0), _Outcome.FAILED)

	assert_eq(_spawned(_Phase.EXPORT), [_id(0)], "no further export may start")
	assert_eq(_spawned(_Phase.UPLOAD), [])
	assert_false(_runner.is_running())


func test_a_single_target_runs_one_combined_process() -> void:
	_launch([_targets[0]] as Array[AppReleaseTarget])
	assert_eq(_spawns.size(), 1)
	assert_eq(_spawns[0]["phase"], _Phase.SINGLE)


func test_stopping_a_target_kills_only_that_process() -> void:
	_launch(_targets)
	var pid: int = _spawns[0]["pid"]

	_runner.stop_target(_id(0))
	assert_eq(_kills, [pid])


func test_stopping_an_export_lets_the_rest_of_the_group_continue() -> void:
	_launch(_targets)
	_runner.stop_target(_id(0))

	assert_eq(_spawned(_Phase.EXPORT), [_id(0), _id(1)], "the next export must still start")


func test_a_stopped_target_never_uploads() -> void:
	_launch(_targets)
	_runner.stop_target(_id(0))
	_finish(_id(1), _Outcome.SUCCEEDED)
	_finish(_id(2), _Outcome.SUCCEEDED)

	assert_eq(_spawned(_Phase.UPLOAD), [_id(1), _id(2)])


func test_stopping_one_upload_leaves_the_others_running() -> void:
	_launch(_targets)
	for index in 3:
		_finish(_id(index), _Outcome.SUCCEEDED)

	_runner.stop_target(_id(1))

	assert_false(_runner.is_target_running(_id(1)))
	assert_true(_runner.is_target_running(_id(0)))
	assert_true(_runner.is_target_running(_id(2)))
	assert_eq(_kills.size(), 1)


func test_stopping_an_unknown_target_is_a_no_op() -> void:
	_launch(_targets)
	_runner.stop_target("ghost")
	assert_eq(_kills, [])
	assert_true(_runner.is_running())


func test_stopping_a_target_reports_it_on_that_target_s_own_stream() -> void:
	_launch(_targets)
	watch_signals(_runner)
	_runner.stop_target(_id(0))

	var parameters: Array = get_signal_parameters(_runner, "log_appended")
	assert_eq(parameters[1], _id(0), "the stop notice must be routed to the target's own tab")
	assert_eq(parameters[2], "Alpha")


func test_a_lone_run_still_reports_its_target_id() -> void:
	_launch([_targets[0]] as Array[AppReleaseTarget])
	watch_signals(_runner)
	_runner.stop_target(_id(0))

	var parameters: Array = get_signal_parameters(_runner, "log_appended")
	assert_eq(parameters[1], _id(0))


func test_stop_all_kills_every_running_upload() -> void:
	_launch(_targets)
	for index in 3:
		_finish(_id(index), _Outcome.SUCCEEDED)

	_runner.stop()

	assert_eq(_kills.size(), 3)
	assert_false(_runner.is_running())


func test_stop_all_does_not_start_the_queued_exports() -> void:
	_launch(_targets)
	_runner.stop()

	assert_eq(_spawned(_Phase.EXPORT), [_id(0)], "stopping must not spawn the queued targets")
	assert_eq(_spawned(_Phase.UPLOAD), [])
	assert_false(_runner.is_running())


func test_stop_all_tells_each_target_that_never_started() -> void:
	var notified: Array[String] = []
	_launch(_targets)
	_runner.log_appended.connect(
		func(text: String, target_id: String, _label: String) -> void:
			if text == AppReleaseStrings.log_not_started:
				notified.append(target_id)
	)

	_runner.stop()

	assert_eq(notified, [_id(1), _id(2)], "the two queued targets, not the running one")


func test_no_output_is_ever_emitted_without_a_target() -> void:
	var untargeted: Array[String] = []
	_launch(_targets)
	_runner.log_appended.connect(
		func(text: String, target_id: String, _label: String) -> void:
			if target_id.is_empty():
				untargeted.append(text)
	)

	_runner.stop()

	assert_eq(untargeted, [], "there is no catch-all tab for untargeted output to land in")


func test_runs_changed_never_reports_an_idle_runner_mid_batch() -> void:
	var seen: Array[bool] = []
	_runner.runs_changed.connect(func() -> void: seen.append(_runner.is_running()))

	_launch(_targets)
	_finish(_id(0), _Outcome.SUCCEEDED)

	assert_does_not_have(seen, false, "the runner must look busy until the batch is done")


func test_the_runner_still_looks_busy_while_the_uploads_run() -> void:
	var seen: Array[bool] = []
	_launch(_targets)
	_runner.runs_changed.connect(func() -> void: seen.append(_runner.is_running()))

	for index in 3:
		_finish(_id(index), _Outcome.SUCCEEDED)

	assert_does_not_have(seen, false, "the upload stage must not read as idle")
	assert_true(_runner.is_running())


func test_runs_changed_reports_idle_once_the_batch_really_ends() -> void:
	_launch(_targets)
	for index in 3:
		_finish(_id(index), _Outcome.SUCCEEDED)

	var seen: Array[bool] = []
	_runner.runs_changed.connect(func() -> void: seen.append(_runner.is_running()))
	for index in 3:
		_finish(_id(index), _Outcome.SUCCEEDED)

	assert_has(seen, false, "the last upload finishing must report an idle runner")


func test_a_batch_announces_every_target_before_the_first_one_starts() -> void:
	var announced: Array[String] = []
	_runner.batch_queued.connect(
		func(ids: PackedStringArray) -> void:
			announced.assign(Array(ids))
			assert_eq(_spawns.size(), 0, "the tabs must exist before anything is spawned")
	)

	_launch(_targets)
	assert_eq(announced, [_id(0), _id(1), _id(2)])


func test_a_single_target_announces_no_batch() -> void:
	watch_signals(_runner)
	_launch([_targets[0]] as Array[AppReleaseTarget])
	assert_signal_not_emitted(_runner, "batch_queued")


func test_launching_clears_the_previous_run_s_output() -> void:
	watch_signals(_runner)
	_launch(_targets)
	assert_signal_emitted(_runner, "log_cleared")
