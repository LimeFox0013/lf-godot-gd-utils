extends GutTest

## LFLogger.enable_print_errors as it was before each test; after_each puts it back.
var _saved_print_errors := true


func before_each():
	_saved_print_errors = LFLogger.enable_print_errors


func after_each():
	LFLogger.enable_print_errors = _saved_print_errors


func test_every_child_is_detached_at_once_and_freed():
	var parent := Node.new()
	add_child_autofree(parent)
	var children: Array[WeakRef] = []
	for i in 3:
		var child := Node.new()
		parent.add_child(child)
		children.append(weakref(child))

	LFUtils.free_children(parent)

	assert_eq(parent.get_child_count(), 0, 'gone from the parent in the same frame')
	await get_tree().process_frame
	for child in children:
		assert_null(child.get_ref())


func test_a_filter_keeps_the_children_it_rejects():
	var parent := Node.new()
	add_child_autofree(parent)
	var keep := Node2D.new()
	parent.add_child(keep)
	parent.add_child(Node.new())

	LFUtils.free_children(parent, func(child): return !(child is Node2D))

	assert_eq(parent.get_children(), [keep])
	await get_tree().process_frame # let the detached child's queue_free run


class Picker:
	extends Object
	func accept(_child: Node) -> bool:
		return true


func test_a_filter_whose_object_was_freed_frees_nothing_and_reports():
	var parent := Node.new()
	add_child_autofree(parent)
	parent.add_child(Node.new())
	var picker := Picker.new()
	var filter := picker.accept
	picker.free()

	LFUtils.free_children(parent, filter)

	assert_push_error('can no longer be called')
	assert_eq(parent.get_child_count(), 1, 'an invalid filter is not "no filter"')


func test_the_report_goes_through_lf_logger_so_its_switch_silences_it():
	var parent := Node.new()
	add_child_autofree(parent)
	parent.add_child(Node.new())
	var picker := Picker.new()
	var filter := picker.accept
	picker.free()
	LFLogger.enable_print_errors = false

	LFUtils.free_children(parent, filter) # an unexpected push_error would fail this test

	assert_eq(parent.get_child_count(), 1)
