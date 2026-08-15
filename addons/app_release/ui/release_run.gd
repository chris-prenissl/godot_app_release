@tool
class_name AppReleaseRun
extends RefCounted

enum Phase { SINGLE, EXPORT, UPLOAD }

var target_id: String
var batch_id: String = ""
var phase: Phase = Phase.SINGLE
var pid: int = -1
var log_path: String = ""
var log_read_len: int = 0
var exit_wait_ticks: int = 0
