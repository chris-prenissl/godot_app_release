@tool
class_name AppReleaseBundleInstaller
extends RefCounted

signal finished(succeeded: bool)

const _POLL_INTERVAL := 0.5
const _LOG_NAME := "bundle_install.log"

var log_path: String = ""

var _timer: Timer
var _pid := -1


func _init(timer_parent: Node) -> void:
	_timer = Timer.new()
	_timer.wait_time = _POLL_INTERVAL
	_timer.timeout.connect(_on_poll)
	timer_parent.add_child(_timer, false, Node.INTERNAL_MODE_BACK)


func is_running() -> bool:
	return _pid > 0


func start(extra_path_entries: PackedStringArray = PackedStringArray()) -> bool:
	if _pid > 0:
		return false

	log_path = AppReleaseRunContext.work_dir().path_join(_LOG_NAME)
	var command := AppReleaseProcess.bundle_install_command(log_path, extra_path_entries)
	_pid = OS.create_process(str(command["executable"]), command["arguments"])
	if _pid <= 0:
		_pid = -1
		return false

	_timer.start()
	return true


func _on_poll() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		return
	_timer.stop()
	_pid = -1
	finished.emit(AppReleaseProcess.are_gems_installed())
