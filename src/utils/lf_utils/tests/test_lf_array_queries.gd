extends GutTest

func test_min_by_picks_the_smallest_key_and_the_first_on_a_tie():
	var items := [{ 'n': 3 }, { 'n': 1 }, { 'n': 1, 'second': true }, { 'n': 2 }]

	var best: Dictionary = LFUtils.min_by(items, func(item): return item['n'])

	assert_eq(best, { 'n': 1 })
	assert_null(LFUtils.min_by([], func(item): return 0.0))


func test_find_by_reads_dictionary_entries_and_object_properties():
	var node := Node.new()
	node.name = 'b'
	assert_eq(LFUtils.find_by([{ 'id': 'a' }, { 'id': 'b', 'x': 1 }], 'id', 'b'), { 'id': 'b', 'x': 1 })
	assert_eq(LFUtils.find_by([node], 'name', &'b'), node)
	assert_eq(LFUtils.find_by([node], 'name', 'b'), node, 'a String finds a StringName by content')
	assert_null(LFUtils.find_by([null, {'id': 'x'}], 'id', 'y'), 'null items are skipped')
	assert_null(LFUtils.find_by([{ 'id': 'a' }], 'id', 'zzz'))
	assert_null(LFUtils.find_by([{ 'id': 1 }], 'id', '1'), 'a different type never matches')
	assert_eq(LFUtils.find_by([{ 'id': 1 }], 'id', 1.0), { 'id': 1 }, 'except an int and a float of the same number')
	node.free()


func test_index_by_keys_every_item_and_a_later_one_wins():
	var index := LFUtils.index_by([{ 'id': 'a', 'v': 1 }, { 'id': 'b' }, { 'id': 'a', 'v': 2 }], 'id')

	assert_eq(index.keys(), ['a', 'b'])
	assert_eq(index['a']['v'], 2)


func test_lower_median_takes_the_lower_middle_and_leaves_the_input_alone():
	var values := [5, 1, 4, 2]

	assert_eq(LFUtils.lower_median(values), 2)
	assert_eq(values, [5, 1, 4, 2])
	assert_eq(LFUtils.lower_median([7, 3, 9]), 7)
	assert_null(LFUtils.lower_median([]))


func test_min_by_still_picks_an_item_when_every_key_is_infinite():
	# Every key equal, even INF, is a tie: the first item wins, never null.
	var items := ['far', 'farther']
	assert_eq(LFUtils.min_by(items, func(_item): return INF), 'far')


func test_max_by_picks_the_largest_key_and_the_first_on_a_tie():
	var items := [{ 'n': 1 }, { 'n': 3 }, { 'n': 3, 'second': true }, { 'n': 2 }]

	assert_eq(LFUtils.max_by(items, func(item): return item['n']), { 'n': 3 })
	assert_null(LFUtils.max_by([], func(_item): return 0.0))


func test_max_by_still_picks_an_item_when_every_key_is_negative_infinity():
	assert_eq(LFUtils.max_by(['near', 'nearer'], func(_item): return -INF), 'near')


func test_group_by_files_items_under_their_key_in_order():
	var groups := LFUtils.group_by([1, 2, 3, 4, 5, 6], func(n): return 'odd' if n % 2 else 'even')

	assert_eq(groups.keys(), ['odd', 'even'], 'keys in the order first met')
	assert_eq(groups['odd'], [1, 3, 5])
	assert_eq(groups['even'], [2, 4, 6])
	assert_eq(LFUtils.group_by([], func(n): return n), {})


func test_count_by_counts_items_per_key_in_order():
	var counts := LFUtils.count_by(['b', 'a', 'b', 'c', 'b'], func(s): return s)

	assert_eq(counts.keys(), ['b', 'a', 'c'])
	assert_eq(counts, { 'b': 3, 'a': 1, 'c': 1 })
	assert_eq(LFUtils.count_by([], func(s): return s), {})


func test_a_nan_key_never_beats_a_number():
	var keys := {'broken': NAN, 'far': 2.0, 'near': 1.0}
	var key := func(item): return keys[item]

	assert_eq(LFUtils.min_by(['broken', 'far', 'near'], key), 'near', 'a NaN first key does not win')
	assert_eq(LFUtils.max_by(['broken', 'far', 'near'], key), 'far')
	assert_eq(LFUtils.min_by(['broken', 'broken'], func(_i): return NAN), 'broken', 'only NaN keys: the first item')


class Item:
	extends Object
	var id := ''
	func _init(initial_id: String) -> void:
		id = initial_id


func test_find_by_reads_object_properties_and_skips_freed_items():
	var freed := Item.new('a')
	var live := Item.new('a')
	freed.free()

	assert_same(LFUtils.find_by([freed, live], 'id', 'a'), live, 'a freed item is skipped, not an error')
	live.free()


func test_index_by_reads_object_properties_and_skips_null_and_freed_items():
	var freed := Item.new('gone')
	var first := Item.new('x')
	var second := Item.new('y')
	freed.free()

	var index := LFUtils.index_by([null, freed, first, { 'id': 'z' }, second], 'id')

	assert_eq(index.keys(), ['x', 'z', 'y'])
	assert_same(index['x'], first)
	first.free()
	second.free()


func test_lower_median_of_one_value_is_that_value():
	assert_eq(LFUtils.lower_median([4]), 4)
	assert_eq(LFUtils.lower_median([2.5, 1.5]), 1.5)


func test_max_by_skips_a_leading_nan_key():
	var keys := {'broken': NAN, 'low': -5.0}
	assert_eq(LFUtils.max_by(['broken', 'low'], func(item): return keys[item]), 'low')
	assert_eq(LFUtils.max_by(['broken', 'broken'], func(_i): return NAN), 'broken', 'only NaN keys: the first item')


func test_cycle_index_wraps_forward_and_back():
	assert_eq(LFUtils.cycle_index(0, 3, 1), 1)
	assert_eq(LFUtils.cycle_index(2, 3, 1), 0)
	assert_eq(LFUtils.cycle_index(0, 3, -1), 2)


func test_cycle_index_from_nothing_starts_at_the_first_or_last():
	assert_eq(LFUtils.cycle_index(-1, 3, 1), 0)
	assert_eq(LFUtils.cycle_index(-1, 3, -1), 2)


func test_cycle_index_skips_rejected_entries_and_returns_minus_one_when_none_fit():
	assert_eq(LFUtils.cycle_index(0, 4, 1, func(i): return i == 3), 3)
	assert_eq(LFUtils.cycle_index(0, 4, 1, func(_i): return false), -1)
	assert_eq(LFUtils.cycle_index(-1, 0, 1), -1)
