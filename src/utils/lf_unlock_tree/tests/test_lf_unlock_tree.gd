extends GutTest

var tree: LFUnlockTree


func before_each():
	tree = LFUnlockTree.new()


func _node(id: String, base_cost: float, prerequisites: Array = [], max_level := 1, cost_growth := 2.0) -> Dictionary:
	return {"id": id, "base_cost": base_cost, "prerequisites": prerequisites, "max_level": max_level, "cost_growth": cost_growth}


func _pool() -> Array:
	return [
		_node("node_a", 100.0, [], 3),
		_node("node_b", 100.0),
		_node("node_c", 300.0, ["node_a"]),
		_node("node_d", 100.0),
	]


func _levels_from(levels: Dictionary) -> Callable:
	return func(id): return levels.get(id, 0)


func test_the_first_level_costs_the_base_and_each_later_one_grows():
	var node := _node("repeatable", 10.0, [], 3, 2.0)
	assert_eq(tree.cost_for_level(node, 1), 10.0)
	assert_eq(tree.cost_for_level(node, 2), 20.0)
	assert_eq(tree.cost_for_level(node, 3), 40.0)
	assert_eq(LFUnlockTree.cost_at(10.0, 3.0, 3), 90.0)


func test_a_node_without_growth_or_max_level_reads_the_defaults():
	var plain := {"id": "plain", "base_cost": 5.0}
	assert_eq(tree.cost_for_level(plain, 3), 5.0, 'no growth')
	assert_eq(tree.max_level_of(plain), 1)
	assert_true(tree.can_buy_next(plain, _levels_from({}), 5.0), 'no prerequisites')


func test_the_next_level_needs_to_be_affordable():
	var node := _node("a", 100.0)
	assert_false(tree.can_buy_next(node, _levels_from({}), 99.0))
	assert_true(tree.can_buy_next(node, _levels_from({}), 100.0))


func test_nothing_past_the_max_level():
	var node := _node("repeatable", 10.0, [], 3)
	assert_true(tree.can_buy_next(node, _levels_from({"repeatable": 2}), 1000.0))
	assert_false(tree.can_buy_next(node, _levels_from({"repeatable": 3}), 1000.0))


func test_a_later_level_is_checked_at_its_grown_cost():
	var node := _node("repeatable", 10.0, [], 3, 2.0)
	assert_false(tree.can_buy_next(node, _levels_from({"repeatable": 2}), 39.0))
	assert_true(tree.can_buy_next(node, _levels_from({"repeatable": 2}), 40.0))


func test_every_prerequisite_must_be_owned_at_least_once():
	var child := _node("child", 10.0, ["root", "other"])
	assert_false(tree.can_buy_next(child, _levels_from({}), 1000.0), 'neither owned, however affordable')
	assert_false(tree.can_buy_next(child, _levels_from({"root": 1}), 1000.0))
	assert_true(tree.can_buy_next(child, _levels_from({"root": 1, "other": 3}), 1000.0), 'any level counts')


func test_spent_counts_every_level_bought():
	assert_eq(tree.spent(_pool(), {"node_a": 2, "node_d": 1}), 100.0 + 200.0 + 100.0)


func test_spent_clamps_levels_to_the_maximum_and_ignores_unknown_ids():
	assert_eq(tree.spent(_pool(), {"node_a": 9}), 700.0)
	assert_eq(tree.spent(_pool(), {"nope": 4}), 0.0)


func test_round_robin_buys_one_level_per_node_per_pass():
	var levels := {}
	var spent := tree.spend_round_robin(_pool(), levels, 400.0)
	# Pass 1: node_a 100, node_b 100, node_c skipped (300 > 200 left), node_d 100. Pass 2: node_a's 2nd level costs 200 > 100 left.
	assert_eq(levels, {"node_a": 1, "node_b": 1, "node_d": 1})
	assert_eq(spent, 300.0)


func test_round_robin_respects_prerequisites_and_max_levels():
	var levels := {}
	tree.spend_round_robin(_pool(), levels, 10000.0)
	assert_eq(levels, {"node_a": 3, "node_b": 1, "node_c": 1, "node_d": 1})


func test_round_robin_with_no_budget_buys_nothing():
	var levels := {}
	assert_eq(tree.spend_round_robin(_pool(), levels, 0.0), 0.0)
	assert_eq(levels, {})


func test_round_robin_continues_from_levels_already_held():
	var levels := {"node_a": 2}
	var spent := tree.spend_round_robin(_pool(), levels, 400.0)
	assert_eq(levels["node_a"], 3, 'level 3 for 400')
	assert_eq(spent, 400.0)


func test_round_robin_never_overspends():
	var levels := {}
	var spent := tree.spend_round_robin(_pool(), levels, 650.0)
	assert_lte(spent, 650.0)
	assert_eq(tree.spent(_pool(), levels), spent)


func test_round_robin_can_read_prerequisites_owned_elsewhere():
	var owned := {"node_a": 1}
	var levels := {}
	tree.spend_round_robin([_node("node_c", 300.0, ["node_a"])], levels, 300.0, func(id): return owned.get(id, 0))
	assert_eq(levels, {"node_c": 1})


class CustomNode:
	var node_key: String
	var price_value: float
	var needs: Array[String] = []
	var top_level := 1
	var growth := 2.0

	func _init(node_key: String, price_value: float, needs: Array[String] = [], top_level := 1) -> void:
		self.node_key = node_key
		self.price_value = price_value
		self.needs = needs
		self.top_level = top_level


func test_objects_with_their_own_field_names_are_read_through_the_mapping():
	var custom := LFUnlockTree.new({"id": "node_key", "base_cost": "price_value", "max_level": "top_level", "cost_growth": "growth", "prerequisites": "needs"})
	var root := CustomNode.new("root", 10.0, [], 2)
	var child := CustomNode.new("child", 30.0, ["root"] as Array[String])
	assert_eq(custom.id_of(root), "root")
	assert_eq(custom.cost_for_level(root, 2), 20.0)
	assert_false(custom.can_buy_next(child, _levels_from({}), 100.0))
	var levels := {}
	custom.spend_round_robin([root, child], levels, 60.0)
	assert_eq(levels, {"root": 2, "child": 1}, 'pass 1: root 10, then child (root is owned by then) 30; pass 2: root again, 20')


func test_the_field_names_default_and_follow_the_mapping():
	assert_eq([tree.id_field, tree.base_cost_field, tree.max_level_field, tree.cost_growth_field, tree.prerequisites_field],
		[&"id", &"base_cost", &"max_level", &"cost_growth", &"prerequisites"])
	var custom := LFUnlockTree.new({"id": "key", "unknown": "ignored"})
	assert_push_error("unknown")
	assert_eq(custom.id_field, &"key")
	assert_eq(custom.base_cost_field, &"base_cost", 'unnamed fields keep their default')


func test_field_names_can_change_later():
	tree.base_cost_field = &"price"
	tree.max_level_field = &"cap"
	tree.cost_growth_field = &"growth"
	tree.prerequisites_field = &"needs"
	tree.id_field = &"name"
	var node := {"name": "x", "price": 5.0, "cap": 2, "growth": 3.0, "needs": ["y"]}
	assert_eq(tree.id_of(node), "x")
	assert_eq(tree.cost_for_level(node, 2), 15.0)
	assert_eq(tree.max_level_of(node), 2)
	assert_false(tree.can_buy_next(node, _levels_from({}), 100.0), 'y is required')
	assert_true(tree.can_buy_next(node, _levels_from({"y": 1}), 100.0))


func test_with_an_override_a_prerequisite_bought_in_the_same_call_does_not_count():
	var levels := {}
	var nowhere := func(_id): return 0
	tree.spend_round_robin([_node("node_a", 100.0), _node("node_c", 300.0, ["node_a"])], levels, 1000.0, nowhere)
	assert_eq(levels, {"node_a": 1}, 'the override alone answers for prerequisites')


func test_the_default_field_names_are_the_named_constants():
	var plain := LFUnlockTree.new()
	assert_eq(plain.id_field, LFUnlockTree.DEFAULT_ID_FIELD)
	assert_eq(plain.base_cost_field, LFUnlockTree.DEFAULT_BASE_COST_FIELD)
	assert_eq(plain.max_level_field, LFUnlockTree.DEFAULT_MAX_LEVEL_FIELD)
	assert_eq(plain.cost_growth_field, LFUnlockTree.DEFAULT_COST_GROWTH_FIELD)
	assert_eq(plain.prerequisites_field, LFUnlockTree.DEFAULT_PREREQUISITES_FIELD)


func test_round_robin_refuses_a_nan_infinite_or_negative_limit():
	for limit in [NAN, INF, -INF, -100.0]:
		var levels := {}
		assert_eq(tree.spend_round_robin(_pool(), levels, limit), 0.0, 'limit %s' % limit)
		assert_push_error('limit')
		assert_eq(levels, {}, 'nothing bought with limit %s' % limit)


func test_round_robin_skips_a_negative_cost_instead_of_gaining_budget():
	var pool := [_node("refund", -500.0, [], 3), _node("node_b", 100.0), _node("node_d", 100.0)]
	var levels := {}
	var spent := tree.spend_round_robin(pool, levels, 100.0)
	assert_push_error('cost')
	assert_eq(levels, {"node_b": 1}, 'the negative cost buys nothing and adds no budget')
	assert_eq(spent, 100.0)


func test_a_nan_cost_or_budget_is_never_affordable():
	assert_false(tree.can_buy_next(_node("broken", NAN), _levels_from({}), 1000.0), 'a NaN cost')
	assert_false(tree.can_buy_next(_node("a", 100.0), _levels_from({}), NAN), 'a NaN budget')
	assert_true(tree.can_buy_next(_node("a", 100.0), _levels_from({}), INF), 'an infinite budget affords anything finite')


func test_round_robin_skips_a_nan_cost_for_the_rest_of_the_call():
	var pool := [_node("broken", NAN, [], 3), _node("node_b", 100.0)]
	var levels := {}
	assert_eq(tree.spend_round_robin(pool, levels, 500.0), 100.0)
	assert_push_error('invalid cost')
	assert_eq(levels, {"node_b": 1})


func test_round_robin_skips_a_level_whose_growth_turns_its_cost_negative():
	var levels := {}
	tree.spend_round_robin([_node("flip", 10.0, [], 3, -1.0)], levels, 100.0)
	assert_push_error('invalid cost')
	assert_eq(levels, {"flip": 1}, 'level 1 costs 10; level 2 would cost -10 and is skipped')


func test_round_robin_with_an_override_reading_levels_counts_a_prerequisite_bought_in_the_call():
	var levels := {}
	tree.spend_round_robin([_node("node_a", 100.0), _node("node_c", 300.0, ["node_a"])], levels, 400.0, func(id): return levels.get(id, 0))
	assert_eq(levels, {"node_a": 1, "node_c": 1})


func test_round_robin_over_an_empty_pool_spends_nothing():
	var levels := {}
	assert_eq(tree.spend_round_robin([], levels, 100.0), 0.0)
	assert_eq(levels, {})


func test_a_node_without_an_id_or_that_is_not_a_dictionary_or_object_reads_the_fallbacks():
	assert_null(tree.id_of({"base_cost": 1.0}))
	assert_null(tree.id_of(42))
	assert_eq(tree.max_level_of(42), 1)
	assert_eq(tree.cost_for_level(42, 1), 0.0)
	assert_eq(tree.cost_for_level({"id": "free"}, 1), 0.0, 'no base cost reads as 0')


func test_spent_follows_the_cost_growth():
	assert_eq(tree.spent([_node("r", 10.0, [], 3, 3.0)], {"r": 3}), 10.0 + 30.0 + 90.0)
	assert_eq(tree.spent([], {"r": 3}), 0.0)


func test_a_null_node_is_never_bought():
	assert_false(tree.can_buy_next(null, func(_id): return 0, 100.0))
	var levels := {}
	assert_eq(tree.spend_round_robin([null, _node("node_a", 10.0)], levels, 100.0), 10.0)
	assert_eq(levels, {"node_a": 1}, 'no entry for the null node')


func test_an_unknown_field_key_is_reported_naming_it():
	var renamed := LFUnlockTree.new({"id": "skill_id", "bsae_cost": "price"})

	assert_push_error("bsae_cost")
	assert_eq(renamed.id_field, &"skill_id")
	assert_eq(renamed.base_cost_field, LFUnlockTree.DEFAULT_BASE_COST_FIELD, "the misspelt key changed nothing")
