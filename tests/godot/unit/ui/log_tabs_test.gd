extends GutTest

## Targets in a group upload concurrently, so their output must stay in separate views.

var _tabs: AppReleaseLogTabs


func before_each() -> void:
	_tabs = AppReleaseLogTabs.new()
	add_child_autofree(_tabs)


func test_first_append_creates_one_tab_titled_with_the_label() -> void:
	_tabs.append("ios", "TestFlight", "building\n")
	assert_eq(_tabs.get_tab_count(), 1)
	assert_eq(_tabs.get_tab_title(0), "TestFlight")


func test_further_output_for_the_same_target_reuses_its_tab() -> void:
	_tabs.append("ios", "TestFlight", "one\n")
	_tabs.append("ios", "TestFlight", "two\n")
	assert_eq(_tabs.get_tab_count(), 1)
	assert_eq(_tabs.text_for("ios"), "one\ntwo\n")


func test_concurrent_targets_do_not_bleed_into_each_other() -> void:
	_tabs.append("ios", "TestFlight", "ios line\n")
	_tabs.append("android", "Firebase", "android line\n")
	_tabs.append("ios", "TestFlight", "ios again\n")

	assert_eq(_tabs.get_tab_count(), 2)
	assert_eq(_tabs.text_for("ios"), "ios line\nios again\n")
	assert_eq(_tabs.text_for("android"), "android line\n")


func test_output_belonging_to_no_target_lands_in_the_general_tab() -> void:
	_tabs.append("", "", "fetch failed\n")
	assert_eq(_tabs.get_tab_count(), 1)
	assert_eq(_tabs.get_tab_title(0), AppReleaseStrings.tab_general_log)
	assert_eq(_tabs.text_for(""), "fetch failed\n")


func test_empty_text_creates_no_tab() -> void:
	_tabs.append("ios", "TestFlight", "")
	assert_eq(_tabs.get_tab_count(), 0)


func test_falls_back_to_the_key_when_no_label_is_given() -> void:
	_tabs.append("ios_preset", "", "x\n")
	assert_eq(_tabs.get_tab_title(0), "ios_preset")


func test_set_running_marks_and_unmarks_the_title() -> void:
	_tabs.append("ios", "TestFlight", "x\n")

	_tabs.set_running("ios", true)
	assert_string_starts_with(_tabs.get_tab_title(0), "▶ ")

	_tabs.set_running("ios", false)
	assert_eq(_tabs.get_tab_title(0), "TestFlight")


func test_set_running_does_not_stack_the_marker() -> void:
	_tabs.append("ios", "TestFlight", "x\n")
	_tabs.set_running("ios", true)
	_tabs.set_running("ios", true)
	assert_eq(_tabs.get_tab_title(0), "▶ TestFlight")


## A target's tab has to exist the moment it starts, before any output has arrived.
func test_set_running_creates_the_tab_when_output_has_not_arrived_yet() -> void:
	_tabs.set_running("ios", true, "TestFlight")
	assert_eq(_tabs.get_tab_count(), 1)
	assert_eq(_tabs.get_tab_title(0), "▶ TestFlight")


func test_a_target_that_starts_gets_focus() -> void:
	_tabs.append("ios", "TestFlight", "x\n")
	_tabs.append("android", "Firebase", "y\n")

	_tabs.set_running("android", true)
	assert_eq(_tabs.current_tab, 1)


## Several targets upload at once, so runs_changed fires repeatedly while they are live.
## Re-focusing on each of those would keep dragging the user off the tab they picked.
func test_an_already_running_target_does_not_steal_focus_again() -> void:
	_tabs.append("ios", "TestFlight", "x\n")
	_tabs.append("android", "Firebase", "y\n")
	_tabs.set_running("android", true)

	_tabs.current_tab = 0
	_tabs.set_running("android", true)

	assert_eq(_tabs.current_tab, 0, "the user's tab choice must survive")


func test_set_running_false_for_an_unknown_target_is_a_no_op() -> void:
	_tabs.set_running("ghost", false)
	assert_eq(_tabs.get_tab_count(), 0)


func test_clear_all_removes_every_tab() -> void:
	_tabs.append("ios", "TestFlight", "x\n")
	_tabs.append("android", "Firebase", "y\n")
	_tabs.clear_all()

	assert_eq(_tabs.get_tab_count(), 0)
	assert_false(_tabs.has_tab_for("ios"))
	assert_eq(_tabs.text_for("ios"), "")


func test_tabs_can_be_rebuilt_after_clearing() -> void:
	_tabs.append("ios", "TestFlight", "old run\n")
	_tabs.clear_all()
	_tabs.append("ios", "TestFlight", "new run\n")

	assert_eq(_tabs.get_tab_count(), 1)
	assert_eq(_tabs.text_for("ios"), "new run\n")
