extends GutTest

func test_reparenting_to_current_parent_is_a_noop():
	var parent = add_child_autofree(Node.new())
	var child = Node.new()
	parent.add_child(child)
	autofree(child)

	await LFUtils.move_node(child, parent)

	assert_eq(child.get_parent(), parent)
	assert_null(child.owner, "owner must stay untouched by a no-op reparent")


func test_reparenting_to_a_new_parent_moves_the_node_and_assigns_owner():
	var old_parent = add_child_autofree(Node.new())
	var new_parent = add_child_autofree(Node.new())
	var child = Node.new()
	old_parent.add_child(child)

	await LFUtils.move_node(child, new_parent)

	assert_eq(child.get_parent(), new_parent)
	assert_eq(old_parent.get_child_count(), 0)
	assert_eq(child.owner, new_parent)


func test_reparenting_into_a_parent_outside_the_tree_still_moves_the_node():
	var old_parent = add_child_autofree(Node.new())
	var detached = autofree(Node.new()) # never added to the scene tree
	var child = Node.new()
	old_parent.add_child(child)

	await LFUtils.move_node(child, detached)

	assert_eq(child.get_parent(), detached)


func test_a_new_parent_freed_before_the_move_finishes_is_no_error():
	var node: Node = autofree(Node.new())
	var new_parent := Node.new()
	add_child(new_parent)

	LFUtils.move_node(node, new_parent)
	new_parent.free()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(is_instance_valid(new_parent))


func test_a_node_freed_before_the_move_finishes_is_no_error():
	var node := Node.new()
	var new_parent: Node = add_child_autofree(Node.new())
	LFUtils.move_node(node, new_parent)
	node.free()
	await get_tree().process_frame
	assert_eq(new_parent.get_child_count(), 0)


func test_a_dead_new_parent_leaves_the_node_where_it_was():
	var old_parent = add_child_autofree(Node.new())
	var node := Node.new()
	old_parent.add_child(node)
	var new_parent := Node.new()
	add_child(new_parent)
	LFUtils.move_node(node, new_parent)
	new_parent.free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(node.get_parent(), old_parent, 'not orphaned, not leaked')


func test_the_later_of_two_moves_wins():
	var first = add_child_autofree(Node.new())
	var second = add_child_autofree(Node.new())
	var node := Node.new()
	LFUtils.move_node(node, first)
	await LFUtils.move_node(node, second)
	await get_tree().process_frame
	assert_eq(node.get_parent(), second)


func test_set_owner_false_leaves_the_owner_alone():
	var old_parent = add_child_autofree(Node.new())
	var new_parent = add_child_autofree(Node.new())
	var child = Node.new()
	old_parent.add_child(child)

	await LFUtils.move_node(child, new_parent, false)

	assert_eq(child.get_parent(), new_parent)
	assert_null(child.owner)


func test_a_null_node_or_parent_is_a_no_op():
	# A freed Node can't be passed at all (the typed parameter refuses it), so null is
	# what reaches the guard.
	var parent: Node = add_child_autofree(Node.new())
	var node: Node = autofree(Node.new())

	await LFUtils.move_node(null, parent)
	await LFUtils.move_node(node, null)

	assert_eq(parent.get_child_count(), 0)
	assert_null(node.get_parent())
	assert_false(node.has_meta(&'_lf_move_ticket'), 'no move was requested')


func test_the_move_happens_before_the_await_returns():
	var new_parent: Node = add_child_autofree(Node.new())
	var node := Node.new()
	LFUtils.move_node(node, new_parent)
	assert_null(node.get_parent(), 'deferred: not moved yet in the calling frame')
	await get_tree().process_frame
	assert_eq(node.get_parent(), new_parent)


func test_a_node_cannot_be_moved_under_itself_or_its_own_descendant_and_stays_where_it_was():
	var root_node = add_child_autofree(Node.new())
	var node := Node.new()
	var descendant := Node.new()
	root_node.add_child(node)
	node.add_child(descendant)

	await LFUtils.move_node(node, node)
	assert_eq(node.get_parent(), root_node, "moving a node under itself leaves it in place")
	assert_push_error("LFUtils.move_node")

	await LFUtils.move_node(node, descendant)
	assert_eq(node.get_parent(), root_node, "moving a node under its own descendant leaves it in place")
	assert_push_error("LFUtils.move_node")
