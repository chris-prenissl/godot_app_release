@tool
class_name AppReleaseGroup
extends Resource

@export var name: String = "":
	set(value):
		name = value
		resource_name = value

@export var target_ids: PackedStringArray = []
