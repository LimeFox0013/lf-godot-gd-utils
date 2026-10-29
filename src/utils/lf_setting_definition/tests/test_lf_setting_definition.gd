extends GutTest

var mode: LFSettingDefinition
var count: LFSettingDefinition


func before_each():
	mode = LFSettingDefinition.choice("mode", "Mode", "How to play.", [{ "value": "easy", "label": "Easy" }, { "value": "hard", "label": "Hard" }], "easy")
	count = LFSettingDefinition.integer("count", "Count", "How many.", 15, 180, 15, 60, func(v): return "%d s" % int(v))


func test_a_choice_keeps_its_fields():
	assert_eq(mode.id, "mode")
	assert_eq(mode.label, "Mode")
	assert_eq(mode.description, "How to play.")
	assert_eq(mode.kind, LFSettingDefinition.Kind.CHOICE)
	assert_eq(mode.default_value, "easy")
	assert_eq(mode.options.size(), 2)


func test_an_integer_keeps_its_fields():
	assert_eq(count.kind, LFSettingDefinition.Kind.INTEGER)
	assert_eq([count.min_value, count.max_value, count.step, count.default_value], [15, 180, 15, 60])


func test_a_known_choice_is_kept_and_an_unknown_one_falls_back_to_the_default():
	assert_eq(mode.sanitize("hard"), "hard")
	assert_eq(mode.sanitize("nightmare"), "easy")
	assert_eq(mode.sanitize(null), "easy")


func test_an_integer_is_clamped_to_its_range():
	assert_eq(count.sanitize(0), 15)
	assert_eq(count.sanitize(9999), 180)
	assert_eq(count.sanitize(90), 90)


func test_an_integer_snaps_to_the_nearest_step_from_the_minimum():
	assert_eq(count.sanitize(20), 15)
	assert_eq(count.sanitize(23), 30)
	assert_eq(count.sanitize(37), 30)
	assert_eq(count.sanitize(38), 45)


func test_a_float_is_cut_to_an_int_before_snapping():
	assert_eq(count.sanitize(52.9), 45)
	assert_eq(count.sanitize(52.0), 45)


func test_a_non_number_for_an_integer_falls_back_to_the_default():
	assert_eq(count.sanitize("lots"), 60)
	assert_eq(count.sanitize(null), 60)
	assert_eq(count.sanitize([3]), 60)


func test_a_step_of_one_keeps_every_integer():
	var plain := LFSettingDefinition.integer("n", "N", "", 1, 5, 1, 3)
	for i in range(1, 6):
		assert_eq(plain.sanitize(i), i)


func test_display_of_a_choice_is_the_option_label_or_the_value_itself():
	assert_eq(mode.display("hard"), "Hard")
	assert_eq(mode.display("other"), "other")


func test_display_of_an_integer_uses_the_format_or_the_number():
	assert_eq(count.display(45), "45 s")
	assert_eq(LFSettingDefinition.integer("n", "N", "", 0, 9, 1, 0).display(7), "7")


func test_values_lists_every_legal_value_in_order():
	assert_eq(mode.values(), ["easy", "hard"])
	assert_eq(LFSettingDefinition.integer("n", "N", "", 0, 9, 3, 0).values(), [0, 3, 6, 9])


func test_choice_matching_ignores_type_surprises_without_error():
	assert_eq(mode.sanitize(1), "easy")
	assert_eq(mode.sanitize(["easy"]), "easy")


func test_a_choice_value_can_be_a_number():
	var level := LFSettingDefinition.choice("lvl", "Level", "", [{ "value": 1, "label": "One" }, { "value": 2, "label": "Two" }], 1)
	assert_eq(level.sanitize(2), 2)
	assert_eq(level.sanitize(3), 1)
	assert_eq(level.display(2), "Two")


func test_a_negative_range_snaps_from_the_minimum():
	var temp := LFSettingDefinition.integer("t", "T", "", -10, 10, 5, 0)
	assert_eq(temp.sanitize(-100), -10)
	assert_eq(temp.sanitize(-3), -5)
	assert_eq(temp.sanitize(4), 5)
	assert_eq(temp.values(), [-10, -5, 0, 5, 10])


func test_the_formatter_can_name_a_special_value():
	var cap := LFSettingDefinition.integer("cap", "Cap", "", 0, 10, 5, 0, func(v): return "Unlimited" if int(v) == 0 else str(v))
	assert_eq(cap.display(0), "Unlimited")
	assert_eq(cap.display(5), "5")


func test_sanitized_integer_is_always_one_of_the_values():
	for raw in [-7, 0, 1, 22, 59, 61, 500]:
		assert_true(count.values().has(count.sanitize(raw)), str(raw))


func test_a_step_of_zero_or_less_counts_as_one_and_warns_once_per_definition():
	for bad_step in [0, -5]:
		var plain := LFSettingDefinition.integer("n", "N", "", 0, 4, bad_step, 2)
		assert_eq(plain.sanitize(3), 3)
		assert_eq(plain.sanitize(4), 4)
		assert_eq(plain.values(), [0, 1, 2, 3, 4])
	assert_push_warning_count(2)


func test_a_valid_step_logs_nothing():
	LFSettingDefinition.integer("n", "N", "", 0, 4, 1, 2).sanitize(1.0)
	assert_push_warning_count(0)


func test_a_huge_float_clamps_to_the_range_and_warns():
	var wide := LFSettingDefinition.integer("n", "N", "", 10, 100, 10, 50)
	assert_eq(wide.sanitize(1.0e30), 100)
	assert_eq(wide.sanitize(-1.0e30), 10)
	assert_eq(wide.sanitize(INF), 100)
	assert_push_warning_count(3)


func test_nan_gives_the_default_and_warns():
	var wide := LFSettingDefinition.integer("n", "N", "", 10, 100, 10, 50)
	assert_eq(wide.sanitize(NAN), 50)
	assert_push_warning("NaN")
