extends GutTest


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


func test_output_belonging_to_no_target_creates_no_tab() -> void:
	_tabs.append("", "", "something untargeted\n")
	assert_eq(_tabs.get_tab_count(), 0)


func test_a_waiting_notice_without_a_target_creates_no_tab() -> void:
	_tabs.set_waiting("", "", "waiting\n")
	assert_eq(_tabs.get_tab_count(), 0)


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


func test_set_running_creates_the_tab_when_output_has_not_arrived_yet() -> void:
	_tabs.set_running("ios", true, "TestFlight")
	assert_eq(_tabs.get_tab_count(), 1)
	assert_eq(_tabs.get_tab_title(0), "▶ TestFlight")


func test_a_target_that_starts_gets_focus() -> void:
	_tabs.append("ios", "TestFlight", "x\n")
	_tabs.append("android", "Firebase", "y\n")

	_tabs.set_running("android", true)
	assert_eq(_tabs.current_tab, 1)


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


func test_a_queued_target_gets_its_tab_with_a_stand_in_message() -> void:
	_tabs.set_waiting("android", "Firebase", "waiting its turn\n")

	assert_eq(_tabs.get_tab_count(), 1)
	assert_eq(_tabs.get_tab_title(0), "Firebase")
	assert_eq(_tabs.text_for("android"), "waiting its turn\n")
	assert_true(_tabs.is_waiting("android"))


func test_real_output_replaces_the_stand_in_rather_than_following_it() -> void:
	_tabs.set_waiting("android", "Firebase", "waiting its turn\n")
	_tabs.append("android", "Firebase", "exporting\n")

	assert_eq(_tabs.text_for("android"), "exporting\n")
	assert_false(_tabs.is_waiting("android"))
	assert_eq(_tabs.get_tab_count(), 1, "the queued tab is reused, not duplicated")


func test_starting_a_queued_target_drops_the_stand_in() -> void:
	_tabs.set_waiting("android", "Firebase", "waiting its turn\n")
	_tabs.set_running("android", true)

	assert_eq(_tabs.text_for("android"), "")
	assert_false(_tabs.is_waiting("android"))


func test_queued_tabs_keep_the_order_they_were_announced_in() -> void:
	for entry in [["ios", "TestFlight"], ["android", "Firebase"], ["steam", "Steam"]]:
		_tabs.set_waiting(entry[0], entry[1], "waiting\n")

	assert_eq(_tabs.get_tab_title(0), "TestFlight")
	assert_eq(_tabs.get_tab_title(1), "Firebase")
	assert_eq(_tabs.get_tab_title(2), "Steam")


func test_a_tab_follows_new_output_by_default() -> void:
	_tabs.append("ios", "TestFlight", "one\n")
	assert_true(_tabs.is_following("ios"))


func test_follow_on_an_unknown_target_is_a_no_op() -> void:
	_tabs.follow("ghost")
	assert_true(_tabs.is_following("ghost"))


func test_following_scrolls_back_to_the_end_after_the_user_scrolled_away() -> void:
	_tabs.size = Vector2(400, 200)
	for i in 200:
		_tabs.append("ios", "TestFlight", "line %d\n" % i)
	await get_tree().process_frame

	var view: TextEdit = _tabs._views["ios"]
	view.scroll_vertical = 0
	assert_false(_tabs.is_following("ios"), "scrolling away must detach the view")

	_tabs.follow("ios")
	assert_true(_tabs.is_following("ios"), "the view must be back at the end")
	assert_gt(view.scroll_vertical, 0.0)


func test_output_keeps_scrolling_after_the_follow_button_was_used() -> void:
	_tabs.size = Vector2(400, 200)
	for i in 200:
		_tabs.append("ios", "TestFlight", "line %d\n" % i)
	await get_tree().process_frame

	var view: TextEdit = _tabs._views["ios"]
	view.scroll_vertical = 0
	_tabs.follow("ios")
	await get_tree().process_frame

	var resumed_at := view.scroll_vertical
	_tabs.append("ios", "TestFlight", "after the jump\n")
	await get_tree().process_frame

	assert_gt(view.scroll_vertical, resumed_at, "new output must still pull the view along")
	assert_true(_tabs.is_following("ios"))


func test_a_detached_view_stays_where_the_user_left_it() -> void:
	_tabs.size = Vector2(400, 200)
	for i in 200:
		_tabs.append("ios", "TestFlight", "line %d\n" % i)
	await get_tree().process_frame

	var view: TextEdit = _tabs._views["ios"]
	view.scroll_vertical = 0
	await get_tree().process_frame

	_tabs.append("ios", "TestFlight", "more output\n")
	await get_tree().process_frame

	assert_eq(view.scroll_vertical, 0.0, "output must not yank a scrolled-back view forward")
	assert_false(_tabs.is_following("ios"))


func test_the_follow_button_appears_only_while_the_view_is_detached() -> void:
	_tabs.size = Vector2(400, 200)
	for i in 200:
		_tabs.append("ios", "TestFlight", "line %d\n" % i)
	await get_tree().process_frame

	var button: Button = _tabs._follow_buttons["ios"]
	assert_false(button.visible, "nothing to offer while the log is following")

	_tabs._views["ios"].scroll_vertical = 0
	assert_true(button.visible, "the way back must be offered once scrolled away")

	button.pressed.emit()
	assert_false(button.visible)
	assert_true(_tabs.is_following("ios"))


func test_clear_all_forgets_the_stand_ins_too() -> void:
	_tabs.set_waiting("android", "Firebase", "waiting\n")
	_tabs.clear_all()
	assert_false(_tabs.is_waiting("android"))


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
