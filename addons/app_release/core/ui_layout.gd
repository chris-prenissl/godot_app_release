@tool
class_name AppReleaseUiLayout
extends RefCounted

static func chain(controls: Array[Control]) -> Control:
	var result: Control = controls[controls.size() - 1]
	for i in range(controls.size() - 2, -1, -1):
		var pair := HSplitContainer.new()
		pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pair.add_child(controls[i])
		pair.add_child(result)
		result = pair
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return result
