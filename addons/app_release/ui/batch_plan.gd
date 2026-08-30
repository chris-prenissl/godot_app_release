@tool
class_name AppReleaseBatchPlan
extends RefCounted

## Bookkeeping for a batch release: who still has to export, and who then uploads.
##
## Exports are serialised because they share one Godot exporter and one
## [code]export_presets.cfg[/code]; uploads are not. [AppReleaseBatchRunner] drains the
## export queue one target at a time and then starts every upload.

var _export_queue: Dictionary = {}
var _upload_targets: Dictionary = {}


func open(batch_id: String, target_ids: PackedStringArray) -> void:
	_export_queue[batch_id] = target_ids.duplicate()
	_upload_targets[batch_id] = target_ids.duplicate()


func has_batch(batch_id: String) -> bool:
	return _export_queue.has(batch_id) or _upload_targets.has(batch_id)

## [b]Destructive[/b]: pops the target, and returns empty when the export phase is done.
func next_export(batch_id: String) -> String:
	var queue: PackedStringArray = _export_queue.get(batch_id, PackedStringArray())
	if queue.is_empty():
		_export_queue.erase(batch_id)
		return ""

	var target_id := queue[0]
	queue.remove_at(0)
	_export_queue[batch_id] = queue
	return target_id


func pending_exports(batch_id: String) -> PackedStringArray:
	return PackedStringArray(_export_queue.get(batch_id, PackedStringArray()))


## Returns the upload targets [i]and closes the batch[/i].
func upload_targets(batch_id: String) -> PackedStringArray:
	var targets: PackedStringArray = _upload_targets.get(batch_id, PackedStringArray())
	_export_queue.erase(batch_id)
	_upload_targets.erase(batch_id)
	return targets


func drop_target(batch_id: String, target_id: String) -> void:
	_remove_from(_export_queue, batch_id, target_id)
	_remove_from(_upload_targets, batch_id, target_id)


func abort(batch_id: String) -> PackedStringArray:
	var remaining: PackedStringArray = _export_queue.get(batch_id, PackedStringArray())
	_export_queue.erase(batch_id)
	_upload_targets.erase(batch_id)
	return remaining


func _remove_from(store: Dictionary, batch_id: String, target_id: String) -> void:
	if not store.has(batch_id):
		return
	var ids: PackedStringArray = store[batch_id]
	var index := ids.find(target_id)
	if index < 0:
		return
	ids.remove_at(index)
	store[batch_id] = ids
