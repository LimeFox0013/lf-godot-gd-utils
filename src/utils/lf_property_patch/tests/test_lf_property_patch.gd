extends GutTest

class Inner:
	extends RefCounted
	var max_hp := 100
	var hp := 40


class Target:
	extends RefCounted
	var damage := 10
	var speed := 2.5
	var inner := Inner.new()


var target: Target


func before_each():
	target = Target.new()


func test_add_is_the_default_op():
	LFPropertyPatch.apply(target, {"path": "speed", "value": 1.5})

	assert_eq(target.speed, 4.0)


func test_multiply_and_set():
	LFPropertyPatch.apply(target, {"path": "speed", "op": "multiply", "value": 2.0})
	assert_eq(target.speed, 5.0)

	LFPropertyPatch.apply(target, {"path": "speed", "op": "set", "value": 7.0})
	assert_eq(target.speed, 7.0)


func test_an_int_property_stays_an_int():
	LFPropertyPatch.apply(target, {"path": "damage", "op": "multiply", "value": 1.55})

	assert_typeof(target.damage, TYPE_INT)
	assert_eq(target.damage, 15)


func test_an_unknown_op_leaves_the_value():
	LFPropertyPatch.apply(target, {"path": "damage", "op": "nope", "value": 5})

	assert_eq(target.damage, 10)


func test_a_dotted_path_reaches_a_nested_object():
	LFPropertyPatch.apply(target, {"path": "inner.max_hp", "value": 20})

	assert_eq(target.inner.max_hp, 120)


func test_clamp_max_caps_the_result():
	LFPropertyPatch.apply(target, {"path": "speed", "value": 100.0, "clampMax": 9.0})

	assert_eq(target.speed, 9.0)


func test_also_set_current_field_mirrors_the_new_value():
	LFPropertyPatch.apply(target, {"path": "inner.max_hp", "value": 20, "alsoSetCurrentField": "hp"})

	assert_eq(target.inner.hp, 120)


func test_apply_returns_true_when_applied():
	assert_true(LFPropertyPatch.apply(target, {"path": "damage", "value": 1}))


func test_a_path_that_misses_an_object_reports_and_changes_nothing():
	assert_false(LFPropertyPatch.apply(target, {"path": "damage.deeper.max_hp", "value": 1}))

	assert_push_error("does not reach an object")
	assert_eq(target.damage, 10)


func test_an_entry_without_path_or_value_reports_and_returns_false():
	assert_false(LFPropertyPatch.apply(target, {"value": 1}))
	assert_false(LFPropertyPatch.apply(target, {"path": "damage"}))

	assert_push_error_count(2)
	assert_eq(target.damage, 10)


func test_an_unknown_property_reports_and_returns_false():
	assert_false(LFPropertyPatch.apply(target, {"path": "nope", "value": 1}))

	assert_push_error("no property")
