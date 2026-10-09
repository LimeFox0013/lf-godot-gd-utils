extends GutTest

class Point extends Resource:
	@export var x: int = 0
	@export var y: int = 0


func test_property_names_lists_the_resources_declared_properties():
	var props := LFUtils.property_names(Point.new())
	assert_true(props.has("x"), "declared property x must be listed")
	assert_true(props.has("y"), "declared property y must be listed")


func test_property_names_lists_every_property_list_entry_by_name():
	var point := Point.new()
	var expected := point.get_property_list().map(func(prop_dict): return prop_dict.name)
	assert_eq(Array(LFUtils.property_names(point)), expected)


func test_property_names_returns_a_typed_string_array():
	var props = LFUtils.property_names(Point.new())
	assert_eq(props.get_typed_builtin(), TYPE_STRING)
