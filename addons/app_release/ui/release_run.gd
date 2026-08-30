@tool
class_name AppReleaseRun
extends RefCounted

## State of one running release process, owned by [AppReleaseBatchRunner].

## Which part of the pipeline this process runs.
enum Phase {
	## Export and upload in one process — a single target released on its own.
	SINGLE,
	## Export only; the upload follows once every export in the batch is done.
	EXPORT,
	## Upload only, of an artifact an earlier [constant Phase.EXPORT] run produced.
	UPLOAD,
}

## Target being released.
var target_id: String
## Batch this run belongs to, or an empty [String] for a single run.
var batch_id: String = ""
## Part of the pipeline this process runs.
var phase: Phase = Phase.SINGLE
## Process id, or [code]-1[/code] before the process starts.
var pid: int = -1
## Log file the process writes to. Its [code].exit[/code] sidecar carries the exit code.
var log_path: String = ""
## Bytes of the log already read and emitted.
var log_read_len: int = 0
## Polls spent waiting for the [code].exit[/code] file after the process disappeared.
var exit_wait_ticks: int = 0
