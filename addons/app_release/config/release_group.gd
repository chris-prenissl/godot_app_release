@tool
@icon("res://addons/app_release/icon.png")
class_name AppReleaseGroup
extends Resource

## A row of the Release tab: one panel holding related targets.
##
## A group is a display and batching unit. Its panel shows one column per
## [AppReleaseTarget] it owns, plus a single [b]Release group[/b] button that runs all of
## them — exports run one after another, then the uploads start.
## [br][br]
## The default config ships two groups, [code]Test[/code] (TestFlight, Firebase) and
## [code]Store[/code] (App Store, Google Play); see
## [method AppReleaseScaffolder.build_default_groups]. Add your own freely.
##
## @tutorial(Architecture overview): https://github.com/chris-prenissl/godot_app_release/blob/main/ARCHITECTURE.md

## Heading of the group's panel. Also becomes the resource name, so the group is
## identifiable in [member AppReleaseConfig.release_groups].
@export var name: String = "":
	set(value):
		name = value
		resource_name = value

## Targets shown in this panel, left to right.
@export var targets: Array[AppReleaseTarget] = []


func enabled_targets() -> Array[AppReleaseTarget]:
	var result: Array[AppReleaseTarget] = []
	for target in targets:
		if target != null and target.enabled:
			result.append(target)
	return result


## Enabled targets that are also valid — what the group's Release button starts.
func runnable_targets() -> Array[AppReleaseTarget]:
	var result: Array[AppReleaseTarget] = []
	for target in targets:
		if target != null and target.enabled and target.get_configuration_error().is_empty():
			result.append(target)
	return result
