@tool
class_name AppReleaseGroup
extends Resource

@export var name: String = "":
	set(value):
		name = value
		resource_name = value

@export var targets: Array[AppReleaseTarget] = []


func enabled_targets() -> Array[AppReleaseTarget]:
	var result: Array[AppReleaseTarget] = []
	for target in targets:
		if target != null and target.enabled:
			result.append(target)
	return result


func runnable_targets() -> Array[AppReleaseTarget]:
	var result: Array[AppReleaseTarget] = []
	for target in targets:
		if target != null and target.enabled and target.get_configuration_error().is_empty():
			result.append(target)
	return result
