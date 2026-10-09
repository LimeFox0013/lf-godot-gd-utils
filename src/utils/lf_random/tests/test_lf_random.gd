extends GutTest

func test_the_same_seed_replays_the_same_rolls():
	var a := LFRandom.new(42)
	var b := LFRandom.new(42)
	var items := [1, 2, 3, 4, 5, 6, 7, 8]
	for i in 50:
		assert_eq(a.chance(0.5), b.chance(0.5))
		assert_eq(a.pick(items), b.pick(items))
	var shuffled_a := items.duplicate()
	var shuffled_b := items.duplicate()
	a.shuffle(shuffled_a)
	b.shuffle(shuffled_b)
	assert_eq(shuffled_a, shuffled_b)


func test_constructing_never_touches_the_global_generator():
	seed(5)
	var expected := randf()
	seed(5)
	LFRandom.new()
	LFRandom.new(9)
	assert_eq(randf(), expected)


func test_chance_pick_and_shuffle_never_touch_the_global_generator():
	seed(5)
	var expected := randf()
	seed(5)
	var random := LFRandom.new(9)
	random.chance(0.5)
	random.pick([1, 2, 3])
	random.shuffle([1, 2, 3, 4])
	assert_eq(randf(), expected)


func test_minus_one_is_a_usable_seed():
	var a := LFRandom.new(-1)
	var b := LFRandom.new(-1)
	assert_eq(a.seed, -1)
	assert_eq(a.randf(), b.randf())


func test_unseeded_sources_made_together_all_differ():
	var seen := {}
	for i in 50:
		seen[LFRandom.new().randi()] = true
	assert_eq(seen.size(), 50)


func test_certain_chances_and_empty_picks_need_no_roll():
	var random := LFRandom.new(7)
	var before := random.state
	assert_true(random.chance(1.0))
	assert_false(random.chance(0.0))
	assert_null(random.pick([]))
	assert_eq(random.state, before, 'nothing was rolled')


func test_a_nan_chance_never_passes_and_needs_no_roll():
	var random := LFRandom.new(7)
	var before := random.state
	assert_false(random.chance(NAN))
	assert_eq(random.state, before)


func test_a_chance_passes_about_that_often():
	var random := LFRandom.new(11)
	var passed := 0
	for i in 4000:
		if random.chance(0.25):
			passed += 1
	assert_almost_eq(passed / 4000.0, 0.25, 0.03)


func test_pick_and_shuffle_handle_small_arrays():
	var random := LFRandom.new(3)
	assert_eq(random.pick([7]), 7)
	var empty := []
	random.shuffle(empty)
	assert_eq(empty, [])
	var one := [1]
	random.shuffle(one)
	assert_eq(one, [1])


func test_shuffle_keeps_every_item():
	var random := LFRandom.new(3)
	var items := [1, 2, 3, 4, 5]
	random.shuffle(items)
	var sorted := items.duplicate()
	sorted.sort()
	assert_eq(sorted, [1, 2, 3, 4, 5])


func test_an_uncertain_chance_consumes_exactly_one_randf():
	var random := LFRandom.new(21)
	var twin := RandomNumberGenerator.new()
	twin.seed = 21
	random.chance(0.5)
	twin.randf()
	assert_eq(random.state, twin.state)


func test_a_pick_consumes_exactly_one_randi_range():
	var random := LFRandom.new(21)
	var twin := RandomNumberGenerator.new()
	twin.seed = 21
	var items := [1, 2, 3, 4, 5]
	var picked: Variant = random.pick(items)
	assert_eq(picked, items[twin.randi_range(0, items.size() - 1)])
	assert_eq(random.state, twin.state)


func test_shuffle_really_reorders():
	var original := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	var changed := 0
	for seed_value in [1, 2, 3, 4, 5]:
		var items := original.duplicate()
		LFRandom.new(seed_value).shuffle(items)
		if items != original:
			changed += 1
	assert_eq(changed, 5, 'ten items left in place by every seed would be no shuffle at all')


func test_chances_past_the_ends_are_certain_and_need_no_roll():
	var random := LFRandom.new(7)
	var before := random.state
	assert_true(random.chance(2.5), 'above 1 always passes')
	assert_true(random.chance(INF))
	assert_false(random.chance(-0.5), 'below 0 never passes')
	assert_false(random.chance(-INF))
	assert_eq(random.state, before, 'nothing was rolled')


func test_every_order_of_three_items_comes_up_about_equally_often():
	var random := LFRandom.new(5)
	var counts := {}
	for i in 6000:
		var items := ['a', 'b', 'c']
		random.shuffle(items)
		var key := ''.join(items)
		counts[key] = counts.get(key, 0) + 1
	assert_eq(counts.size(), 6, 'all six orders occur')
	for order in counts:
		assert_almost_eq(counts[order] / 6000.0, 1.0 / 6.0, 0.03, order)


func test_pick_reaches_every_item_including_both_ends():
	var random := LFRandom.new(9)
	var seen := {}
	for i in 200:
		seen[random.pick(['first', 'middle', 'last'])] = true
	assert_eq(seen.size(), 3)


func test_shuffle_changes_the_array_passed_in_place():
	var items := [1, 2, 3, 4, 5, 6, 7, 8]
	var same_array := items
	LFRandom.new(1).shuffle(items)
	assert_same(items, same_array)
	assert_ne(same_array, [1, 2, 3, 4, 5, 6, 7, 8], 'the caller sees the new order')
