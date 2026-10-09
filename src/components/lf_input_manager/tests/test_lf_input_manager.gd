extends GutTest

var manager: LFInputManager
var screen: Node


func before_each():
	screen = add_child_autofree(Node.new())
	manager = LFInputManager.new()
	screen.add_child(manager)


func after_each():
	get_tree().paused = false


func _key(keycode: Key = KEY_K) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


## A handler that appends `tag` to `calls` and consumes when `consume` is true.
func _recorder(calls: Array, tag: Variant, consume := false) -> Callable:
	return func(_event: InputEvent) -> bool:
		calls.append(tag)
		return consume


func test_layers_receive_an_event_from_the_highest_priority_down():
	var calls := []
	manager.add_layer(screen, _recorder(calls, 'field'), 0)
	manager.add_layer(screen, _recorder(calls, 'menu'), 20)
	manager.add_layer(screen, _recorder(calls, 'panel'), 10)

	assert_false(manager.route(_key()), 'nobody consumed it')

	assert_eq(calls, ['menu', 'panel', 'field'])


func test_among_equal_priorities_the_newest_layer_goes_first():
	var calls := []
	manager.add_layer(screen, _recorder(calls, 'older'))
	manager.add_layer(screen, _recorder(calls, 'newer'))

	manager.route(_key())

	assert_eq(calls, ['newer', 'older'])


func test_a_layer_that_consumes_hides_the_event_from_the_layers_below():
	var calls := []
	manager.add_layer(screen, _recorder(calls, 'field'), 0)
	manager.add_layer(screen, _recorder(calls, 'menu', true), 10)

	assert_true(manager.route(_key()))

	assert_eq(calls, ['menu'])


func test_a_handler_without_a_return_value_does_not_consume():
	var calls := []
	manager.add_layer(screen, func(_event: InputEvent) -> void: calls.append('top'), 10)
	manager.add_layer(screen, _recorder(calls, 'bottom'), 0)

	assert_false(manager.route(_key()))

	assert_eq(calls, ['top', 'bottom'])


func test_a_switched_off_layer_receives_nothing_until_switched_back_on():
	var calls := []
	var id := manager.add_layer(screen, _recorder(calls, 'a'))

	manager.set_layer_enabled(id, false)
	manager.route(_key())
	assert_eq(calls, [])
	assert_false(manager.is_layer_enabled(id))

	manager.set_layer_enabled(id, true)
	manager.route(_key())
	assert_eq(calls, ['a'])


func test_switching_a_layer_off_inside_a_handler_takes_effect_for_the_same_event():
	var calls := []
	var world := manager.add_layer(screen, _recorder(calls, 'world'), 0)
	manager.add_layer(screen, func(_event: InputEvent) -> bool:
		calls.append('hud')
		manager.set_layer_enabled(world, false)
		return false, 10)

	manager.route(_key())

	assert_eq(calls, ['hud'], 'the world never sees the event the HUD switched it off with')


func test_an_enabled_predicate_is_read_for_every_layer_as_the_event_reaches_it():
	var calls := []
	var menu_open := [true]
	manager.add_layer(screen, _recorder(calls, 'menu'), 10, func() -> bool: return menu_open[0])
	manager.add_layer(screen, func(_event: InputEvent) -> bool:
		calls.append('closer')
		menu_open[0] = false
		return false, 20)

	manager.route(_key())
	assert_eq(calls, ['closer'], 'the menu closed before the event reached it')

	menu_open[0] = true
	calls.clear()
	manager.route(_key())
	assert_eq(calls, ['closer'])


func test_a_layer_added_while_routing_waits_for_the_next_event():
	var calls := []
	manager.add_layer(screen, func(_event: InputEvent) -> bool:
		if calls.is_empty():
			manager.add_layer(screen, _recorder(calls, 'late'), -10)
		calls.append('first')
		return false)

	manager.route(_key())
	assert_eq(calls, ['first'])

	manager.route(_key())
	assert_eq(calls, ['first', 'first', 'late'])


func test_a_layer_whose_owner_leaves_the_tree_is_dropped():
	var calls := []
	var owner_node: Node = add_child_autofree(Node.new())
	var id := manager.add_layer(owner_node, _recorder(calls, 'gone'))

	remove_child(owner_node)
	manager.route(_key())

	assert_false(manager.has_layer(id))
	assert_eq(calls, [])
	add_child(owner_node) # so autofree can free it
	manager.route(_key())
	assert_eq(calls, [], 'coming back does not bring the layer back')


func test_a_layer_whose_owner_is_freed_is_dropped_without_touching_the_freed_owner():
	var calls := []
	var owner_node := Node.new()
	add_child(owner_node)
	var id := manager.add_layer(owner_node, func(_event: InputEvent) -> bool:
		calls.append(owner_node.name)
		return false)

	owner_node.queue_free()
	await wait_process_frames(1)
	manager.route(_key())

	assert_false(manager.has_layer(id))
	assert_eq(calls, [])


func test_an_owner_queued_for_deletion_stops_receiving_at_once():
	var calls := []
	var owner_node: Node = add_child_autofree(Node.new())
	manager.add_layer(owner_node, _recorder(calls, 'leaving'))

	owner_node.queue_free()
	manager.route(_key())

	assert_eq(calls, [])


func test_an_owner_freed_before_ever_entering_the_tree_is_dropped_on_the_next_event():
	var calls := []
	var owner_node := Node.new()
	var id := manager.add_layer(owner_node, _recorder(calls, 'never'))

	manager.route(_key())
	assert_eq(calls, [], 'an owner outside the tree does not receive')
	assert_true(manager.has_layer(id), 'it may still enter the tree')

	owner_node.free()
	manager.route(_key())
	assert_false(manager.has_layer(id))


func test_a_screen_swapped_in_the_same_frame_takes_input_at_once():
	var calls := []
	manager.add_layer(screen, _recorder(calls, 'old'))
	screen.queue_free()
	var next_screen: Node = add_child_autofree(Node.new())
	var next_manager := LFInputManager.new()
	next_screen.add_child(next_manager)
	next_manager.add_layer(next_screen, _recorder(calls, 'new'))

	get_viewport().push_input(_key())
	assert_eq(calls, ['new'], 'the leaving screen is already deaf')

	await wait_process_frames(2)
	calls.clear()
	get_viewport().push_input(_key())
	assert_eq(calls, ['new'])


func test_events_reach_the_layers_from_the_viewport():
	var calls := []
	manager.add_layer(screen, _recorder(calls, 'a'))

	get_viewport().push_input(_key())

	assert_eq(calls, ['a'])


func test_a_consumed_event_is_marked_handled_so_later_listeners_never_see_it():
	var calls := []
	var other := LFInputManager.new()
	screen.add_child(other) # added after `manager`, so it gets unhandled input first
	other.add_layer(screen, _recorder(calls, 'front', true))
	manager.add_layer(screen, _recorder(calls, 'behind'))

	get_viewport().push_input(_key())

	assert_eq(calls, ['front'])


func test_the_input_stage_routes_before_the_unhandled_stage():
	var calls := []
	var early := LFInputManager.new()
	early.stage = LFInputManager.Stage.INPUT
	screen.add_child(early)
	early.add_layer(screen, _recorder(calls, 'early', true))
	manager.add_layer(screen, _recorder(calls, 'late'))

	get_viewport().push_input(_key())

	assert_eq(calls, ['early'])


func test_a_manual_manager_ignores_the_viewport_and_routes_only_what_it_is_given():
	var calls := []
	manager.stage = LFInputManager.Stage.MANUAL
	manager.add_layer(screen, _recorder(calls, 'a'))

	get_viewport().push_input(_key())
	assert_eq(calls, [])

	manager.route(_key())
	assert_eq(calls, ['a'])


func test_while_the_tree_is_paused_only_owners_that_run_when_paused_receive():
	var calls := []
	var pause_menu: Node = add_child_autofree(Node.new())
	pause_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	manager.add_layer(pause_menu, _recorder(calls, 'pause menu'))
	manager.add_layer(screen, _recorder(calls, 'world'))
	get_tree().paused = true

	get_viewport().push_input(_key())

	assert_eq(calls, ['pause menu'])


func test_a_pause_toggle_owned_by_a_pausable_node_can_unpause_when_always_active():
	# The usual pause menu: Escape toggles a real pause from the level script (a pausable
	# node), the menu itself runs only while paused and swallows every event.
	var calls := []
	var menu: Node = add_child_autofree(Node.new())
	menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	var toggle := func(event: InputEvent) -> bool:
		if (event as InputEventKey).keycode != KEY_ESCAPE:
			return false
		get_tree().paused = not get_tree().paused
		calls.append('paused' if get_tree().paused else 'resumed')
		return true
	var toggle_id := manager.add_layer(screen, toggle, 30)
	manager.set_layer_always_active(toggle_id, true)
	manager.add_layer(menu, _recorder(calls, 'menu', true), 20)
	manager.add_layer(screen, _recorder(calls, 'world', true), 0)

	get_viewport().push_input(_key(KEY_ENTER))
	get_viewport().push_input(_key(KEY_ESCAPE))
	get_viewport().push_input(_key(KEY_ENTER))
	get_viewport().push_input(_key(KEY_ESCAPE))
	get_viewport().push_input(_key(KEY_ENTER))

	assert_eq(calls, ['world', 'paused', 'menu', 'resumed', 'world'])
	assert_false(get_tree().paused)
	assert_true(manager.is_layer_always_active(toggle_id))


func test_always_active_still_obeys_the_switch_and_the_predicate_and_unknown_ids_read_false():
	var calls := []
	var shown := [false]
	var id := manager.add_layer(screen, _recorder(calls, 'a'), 0, func() -> bool: return shown[0])
	manager.set_layer_always_active(id, true)
	get_tree().paused = true

	manager.route(_key())
	shown[0] = true
	manager.set_layer_enabled(id, false)
	manager.route(_key())
	manager.set_layer_enabled(id, true)
	manager.route(_key())
	manager.set_layer_always_active(id, false)
	manager.route(_key())
	manager.set_layer_always_active(999, true)

	assert_eq(calls, ['a'])
	assert_false(manager.is_layer_always_active(999))


func test_remove_layer_and_clear_drop_layers_and_unknown_ids_are_ignored():
	var calls := []
	var a := manager.add_layer(screen, _recorder(calls, 'a'))
	var b := manager.add_layer(screen, _recorder(calls, 'b'))
	assert_ne(a, b, 'every layer gets its own id')

	manager.remove_layer(a)
	manager.remove_layer(12345)
	manager.route(_key())
	assert_eq(calls, ['b'])
	assert_false(manager.has_layer(a))

	manager.clear()
	manager.route(_key())
	assert_eq(calls, ['b'])
	assert_false(manager.has_layer(b))


func test_a_removed_layer_no_longer_listens_to_its_owner():
	var owner_node: Node = add_child_autofree(Node.new())
	var id := manager.add_layer(owner_node, _recorder([], 'a'))

	manager.remove_layer(id)

	assert_eq(owner_node.tree_exiting.get_connections().size(), 0)


func test_two_managers_never_share_layers():
	var other: LFInputManager = add_child_autofree(LFInputManager.new())
	var id := manager.add_layer(screen, _recorder([], 'a'))

	assert_true(manager.has_layer(id))
	assert_false(other.has_layer(id))


func test_a_layer_without_an_owner_or_a_valid_handler_is_refused():
	assert_eq(manager.add_layer(null, _recorder([], 'a')), 0)
	assert_push_error('owner')
	assert_eq(manager.add_layer(screen, Callable()), 0)
	assert_push_error('handler')

	assert_false(manager.route(_key()), 'nothing was registered')


func test_switching_an_unknown_layer_is_ignored_and_reads_as_off():
	manager.set_layer_enabled(12345, true)

	assert_false(manager.is_layer_enabled(12345))
	assert_false(manager.is_layer_enabled(0))


class _Handler:
	extends RefCounted
	var calls := 0
	func on_input(_event: InputEvent) -> bool:
		calls += 1
		return false
	func is_on() -> bool:
		return true


func test_a_layer_whose_handler_or_predicate_object_is_freed_is_dropped():
	var handler_owner := Object.new()
	var by_handler := manager.add_layer(screen, Callable(handler_owner, &"free"))
	var predicate_owner := Object.new()
	var by_predicate := manager.add_layer(screen, _recorder([], 'p'), 0, Callable(predicate_owner, &"get_class"))
	var kept_handler := _Handler.new()
	var kept := manager.add_layer(screen, kept_handler.on_input, 0, kept_handler.is_on)

	handler_owner.free()
	predicate_owner.free()
	manager.route(_key())

	assert_false(manager.has_layer(by_handler))
	assert_false(manager.has_layer(by_predicate))
	assert_true(manager.has_layer(kept))
	assert_eq(kept_handler.calls, 1)


func test_only_a_true_bool_consumes_other_truthy_returns_pass_the_event_on():
	var calls := []
	manager.add_layer(screen, func(_event: InputEvent) -> int:
		calls.append('top')
		return 1, 10)
	manager.add_layer(screen, _recorder(calls, 'bottom'), 0)

	assert_false(manager.route(_key()))
	assert_eq(calls, ['top', 'bottom'])


func test_a_freed_manager_leaves_no_connection_on_the_owners():
	var owner_node: Node = add_child_autofree(Node.new())
	var other := LFInputManager.new()
	add_child(other)
	other.add_layer(owner_node, _recorder([], 'a'))
	assert_eq(owner_node.tree_exiting.get_connections().size(), 1)

	other.free()

	assert_eq(owner_node.tree_exiting.get_connections().size(), 0)
	remove_child(owner_node) # tree_exiting fires with nothing listening
	assert_engine_error_count(0)
	add_child(owner_node)


func test_a_manager_queued_for_deletion_routes_nothing():
	var calls := []
	manager.add_layer(screen, _recorder(calls, 'a', true))

	manager.queue_free()

	assert_false(manager.route(_key()))
	assert_eq(calls, [])


func test_a_predicate_returning_a_non_bool_keeps_the_layer_out():
	var calls := []
	manager.add_layer(screen, _recorder(calls, 'a', true), 0, func() -> int: return 1)

	assert_false(manager.route(_key()))
	assert_eq(calls, [], 'only a true bool lets the layer take part')


func test_route_reports_a_consumed_event():
	manager.add_layer(screen, _recorder([], 'a', true))

	assert_true(manager.route(_key()))


func test_an_owner_with_two_layers_keeps_one_listener_until_its_last_layer_goes():
	var owner_node: Node = add_child_autofree(Node.new())
	var first := manager.add_layer(owner_node, _recorder([], 'a'))
	var second := manager.add_layer(owner_node, _recorder([], 'b'))
	assert_eq(owner_node.tree_exiting.get_connections().size(), 1, 'one listener per owner')

	manager.remove_layer(first)
	assert_eq(owner_node.tree_exiting.get_connections().size(), 1, 'the other layer still needs it')

	manager.remove_layer(second)
	assert_eq(owner_node.tree_exiting.get_connections().size(), 0)


func test_an_owner_leaving_the_tree_drops_all_its_layers_and_its_listener():
	var owner_node: Node = add_child_autofree(Node.new())
	var first := manager.add_layer(owner_node, _recorder([], 'a'))
	var second := manager.add_layer(owner_node, _recorder([], 'b'), 5)
	var other := manager.add_layer(screen, _recorder([], 'c'))

	remove_child(owner_node)

	assert_false(manager.has_layer(first))
	assert_false(manager.has_layer(second))
	assert_true(manager.has_layer(other))
	assert_eq(owner_node.tree_exiting.get_connections().size(), 0)
	add_child(owner_node)


func test_clear_stops_listening_to_every_owner():
	var owner_node: Node = add_child_autofree(Node.new())
	manager.add_layer(owner_node, _recorder([], 'a'))

	manager.clear()

	assert_eq(owner_node.tree_exiting.get_connections().size(), 0)


func test_layer_ids_count_up_from_one_and_add_layer_defaults_to_priority_zero():
	var calls := []
	var first := manager.add_layer(screen, _recorder(calls, 'default'))
	manager.add_layer(screen, _recorder(calls, 'below'), LFInputManager.DEFAULT_PRIORITY - 1)
	var second := manager.add_layer(screen, _recorder(calls, 'above'), LFInputManager.DEFAULT_PRIORITY + 1)

	manager.route(_key())

	assert_eq(first, 1)
	assert_eq(second, 3)
	assert_eq(calls, ['above', 'default', 'below'])
