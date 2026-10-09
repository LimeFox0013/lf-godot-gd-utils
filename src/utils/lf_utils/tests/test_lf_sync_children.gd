extends GutTest

var parent: Node
## LFLogger.enable_print_errors as it was before each test; after_each puts it back.
var _saved_print_errors := true


func before_each():
	_saved_print_errors = LFLogger.enable_print_errors
	parent = Node.new()
	add_child_autofree(parent)


func after_each():
	LFLogger.enable_print_errors = _saved_print_errors


func _make(index: int) -> Node:
	var node := Node.new()
	node.name = 'item_%d' % index
	return node


func test_grows_with_create_called_for_each_missing_index():
	var seen: Array[int] = []
	LFUtils.sync_children(parent, 3, func(i): seen.append(i); return _make(i))

	assert_eq(seen, [0, 1, 2])
	assert_eq(parent.get_children().map(func(c): return String(c.name)), ['item_0', 'item_1', 'item_2'])


func test_keeps_existing_children_and_only_creates_the_rest():
	LFUtils.sync_children(parent, 2, _make)
	var first := parent.get_child(0)
	var seen: Array[int] = []
	LFUtils.sync_children(parent, 4, func(i): seen.append(i); return _make(i))

	assert_eq(seen, [2, 3])
	assert_eq(parent.get_child(0), first)
	assert_eq(parent.get_child_count(), 4)


func test_trims_the_tail_at_once_and_frees_it():
	LFUtils.sync_children(parent, 4, _make)
	var head := parent.get_child(0)
	var tail: WeakRef = weakref(parent.get_child(3))

	LFUtils.sync_children(parent, 1, _make)

	assert_eq(parent.get_children(), [head], 'the count is right in the same frame')
	await get_tree().process_frame
	assert_null(tail.get_ref())


func test_a_create_that_adds_the_child_itself_is_not_added_twice():
	LFUtils.sync_children(parent, 2, func(i): var n := _make(i); parent.add_child(n); return n)

	assert_eq(parent.get_child_count(), 2)


func test_zero_or_negative_count_empties_the_parent():
	LFUtils.sync_children(parent, 3, _make)
	LFUtils.sync_children(parent, -1, _make)

	assert_eq(parent.get_child_count(), 0)
	await get_tree().process_frame # let the trimmed children's queue_free run


func test_a_create_that_adds_nothing_stops_with_an_error():
	LFUtils.sync_children(parent, 2, func(_i): return null)

	assert_eq(parent.get_child_count(), 0)
	assert_push_error('create did not add a child')


func test_the_report_goes_through_lf_logger_so_its_switch_silences_it():
	LFLogger.enable_print_errors = false

	LFUtils.sync_children(parent, 2, func(_i): return null) # an unexpected push_error would fail this test

	assert_eq(parent.get_child_count(), 0)


func test_a_create_returning_a_node_parented_elsewhere_stops_with_an_error():
	var elsewhere := Node.new()
	add_child_autofree(elsewhere)
	var stray := Node.new()
	elsewhere.add_child(stray)

	LFUtils.sync_children(parent, 2, func(_i): return stray)

	assert_eq(parent.get_child_count(), 0, 'a node that already has another parent is not stolen')
	assert_eq(stray.get_parent(), elsewhere)
	assert_push_error('create did not add a child for index 0')


func test_the_same_count_changes_nothing():
	LFUtils.sync_children(parent, 2, _make)
	var children := parent.get_children()
	var seen := []
	LFUtils.sync_children(parent, 2, func(i): seen.append(i); return _make(i))
	assert_eq(parent.get_children(), children)
	assert_eq(seen, [])


func test_a_create_that_adds_more_children_than_asked_for_is_trimmed_to_the_count():
	LFUtils.sync_children(parent, 2, func(i):
		for k in 3:
			parent.add_child(_make(i * 10 + k))
		return null
	)

	assert_eq(parent.get_child_count(), 2, 'the parent holds exactly count children')
	await get_tree().process_frame # let the trimmed children's queue_free run


func test_a_create_that_returns_a_freed_node_stops_with_an_error():
	LFUtils.sync_children(parent, 2, func(_i):
		var gone := Node.new()
		gone.free()
		return gone
	)

	assert_eq(parent.get_child_count(), 0)
	assert_push_error('create did not add a child for index 0')
