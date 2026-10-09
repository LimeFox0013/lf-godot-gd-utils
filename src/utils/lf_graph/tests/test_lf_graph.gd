extends GutTest


func _parents(edges: Dictionary) -> Callable:
	return func(id): return edges.get(id, [])


func test_ids_without_parents_are_depth_zero():
	assert_eq(LFGraph.layer_depths(['a', 'b'], _parents({})), {'a': 0, 'b': 0})


func test_a_chain_counts_its_parents():
	var depths := LFGraph.layer_depths(['c', 'b', 'a'], _parents({'b': ['a'], 'c': ['b']}))
	assert_eq(depths, {'c': 2, 'b': 1, 'a': 0})


func test_the_longest_chain_wins():
	# d sits on a (depth 0) and on c, which is two below a.
	var edges := {'b': ['a'], 'c': ['b'], 'd': ['a', 'c']}
	assert_eq(LFGraph.layer_depths(['a', 'b', 'c', 'd'], _parents(edges))['d'], 3)


func test_parents_outside_ids_are_ignored():
	var edges := {'child': ['root', 'elsewhere'], 'root': ['far-away']}
	assert_eq(LFGraph.layer_depths(['root', 'child'], _parents(edges)), {'root': 0, 'child': 1})


func test_the_result_follows_the_order_of_ids_and_lists_a_duplicate_once():
	var depths := LFGraph.layer_depths(['b', 'a', 'b'], _parents({'b': ['a']}))
	assert_eq(depths.keys(), ['b', 'a'])


func test_a_null_parent_list_counts_as_none():
	assert_eq(LFGraph.layer_depths([1, 2], func(_id): return null), {1: 0, 2: 0})


func test_a_cycle_terminates_and_every_id_gets_a_depth():
	var edges := {'x': ['y'], 'y': ['z'], 'z': ['x'], 'tail': ['x']}
	var depths := LFGraph.layer_depths(['x', 'y', 'z', 'tail'], _parents(edges))
	assert_eq(depths.size(), 4)
	# Walking from x, the edge z -> x closes the cycle and is ignored.
	assert_eq(depths, {'x': 2, 'y': 1, 'z': 0, 'tail': 3})


func test_a_self_parent_is_ignored():
	assert_eq(LFGraph.layer_depths(['a'], _parents({'a': ['a']})), {'a': 0})


func test_each_id_asks_for_its_parents_once():
	var asked := {}
	var edges := {'b': ['a'], 'c': ['a', 'b'], 'd': ['b', 'c']}
	LFGraph.layer_depths(['d', 'c', 'b', 'a'], func(id):
		asked[id] = asked.get(id, 0) + 1
		return edges.get(id, []))
	assert_eq(asked, {'d': 1, 'c': 1, 'b': 1, 'a': 1})


func test_a_dense_thirty_layer_graph_finishes_quickly():
	# Every node sits on every node of every earlier layer: an unmemoised walk would
	# follow exponentially many paths.
	const LAYERS := 30
	const WIDTH := 6
	var ids := []
	var edges := {}
	var earlier := []
	for layer in LAYERS:
		var this_layer := []
		for i in WIDTH:
			var id := '%d-%d' % [layer, i]
			edges[id] = earlier.duplicate()
			this_layer.append(id)
		earlier.append_array(this_layer)
		ids.append_array(this_layer)
	ids.reverse()
	var started := Time.get_ticks_msec()
	var depths := LFGraph.layer_depths(ids, _parents(edges))
	assert_lt(Time.get_ticks_msec() - started, 5000, 'an unmemoised walk would take far longer')
	assert_eq(depths['29-0'], 29)
	assert_eq(depths['0-5'], 0)


func test_a_long_chain_does_not_overflow_the_stack():
	var ids := []
	var edges := {}
	for i in 5000:
		ids.append(i)
		if i > 0:
			edges[i] = [i - 1]
	ids.reverse()
	assert_eq(LFGraph.layer_depths(ids, _parents(edges))[4999], 4999)


func test_no_ids_give_no_depths_and_ask_for_no_parents():
	var asked := []
	assert_eq(LFGraph.layer_depths([], func(id):
		asked.append(id)
		return []), {})
	assert_eq(asked, [])
