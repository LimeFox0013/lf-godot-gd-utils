extends GutTest


func _table(weights: Array, nothing := 0.0) -> LFLootTable:
	var entries: Array[LFLootEntry] = []
	for i in weights.size():
		entries.append(LFLootEntry.new('item-%d' % i, weights[i], StringName('e%d' % i)))
	return LFLootTable.new(entries, nothing)


func test_bands_are_half_open_in_declaration_order():
	var table := _table([1.0, 3.0])
	assert_eq(table.pick_index(0.0), 0)
	assert_eq(table.pick_index(0.24), 0)
	assert_eq(table.pick_index(0.25), 1)
	assert_eq(table.pick_index(0.99), 1)


func test_the_nothing_band_comes_last():
	var table := _table([1.0], 3.0)
	assert_eq(table.pick_index(0.2), 0)
	assert_eq(table.pick_index(0.3), -1)
	assert_eq(table.pick_index(1.0), -1, 'a roll of 1 lands on nothing when it has weight')


func test_a_roll_of_one_without_nothing_lands_on_the_last_positive_entry():
	assert_eq(_table([33.4, 33.3, 33.3]).pick_index(1.0), 2)
	assert_eq(_table([1.0, 0.0]).pick_index(1.0), 0, 'never a zero weight')


func test_zero_or_negative_weights_are_never_chosen():
	var table := _table([0.0, -2.0, 1.0])
	assert_eq(table.pick_index(0.0), 2)
	assert_eq(table.chance_of(0), 0.0)
	assert_eq(table.chance_of(2), 1.0)


func test_no_weight_at_all_is_nothing():
	assert_eq(_table([0.0]).pick_index(0.5), -1)
	assert_eq(LFLootTable.new().pick_index(0.5), -1)


func test_a_null_entry_is_skipped_without_shifting_the_others():
	var entries: Array[LFLootEntry] = [LFLootEntry.new('a', 1.0), null, LFLootEntry.new('b', 1.0)]
	var table := LFLootTable.new(entries)
	assert_eq(table.pick_index(0.4), 0)
	assert_eq(table.pick_index(0.6), 2)


func test_weights_changed_after_construction_count_at_the_next_roll():
	var table := _table([1.0])
	table.entries.append(LFLootEntry.new('late', 1.0))
	assert_eq(table.pick_index(0.75), 1)
	table.find(&'e0').weight = 0.0
	assert_eq(table.pick_index(0.1), 1)


func test_chances_sum_to_one():
	var table := _table([2.0, 3.0], 5.0)
	assert_almost_eq(table.chance_of(0) + table.chance_of(1) + table.nothing_chance(), 1.0, 1e-12)
	assert_eq(table.nothing_chance(), 0.5)


func test_higher_weights_mean_more_drops():
	var low := _table([1.0], 9.0)
	var high := _table([4.0], 9.0)
	assert_gt(1.0 - high.nothing_chance(), 1.0 - low.nothing_chance())


func test_a_nested_table_always_resolves_to_an_entry_or_nothing():
	var inner := _table([1.0, 1.0])
	var entries: Array[LFLootEntry] = [LFLootEntry.nested(inner, 1.0)]
	var outer := LFLootTable.new(entries)
	var rng := LFRandom.new(3)
	for i in 50:
		var got := outer.roll(rng)
		assert_true(got == inner.entries[0] or got == inner.entries[1])


func test_a_nested_tables_nothing_share_yields_nothing():
	var inner := _table([], 1.0)
	var entries: Array[LFLootEntry] = [LFLootEntry.nested(inner, 1.0)]
	assert_null(LFLootTable.new(entries).roll(LFRandom.new(1)))


func test_default_weights_pick_uniformly():
	var table := _table([1.0, 1.0, 1.0, 1.0])
	var rng := LFRandom.new(4)
	var counts := [0, 0, 0, 0]
	for i in 4000:
		counts[table.entries.find(table.roll(rng))] += 1
	for c in counts:
		assert_almost_eq(c / 4000.0, 0.25, 0.03)


func test_a_roll_draws_one_value_per_level():
	var table := _table([1.0, 1.0])
	var rng := LFRandom.new(5)
	var twin := LFRandom.new(5)
	table.roll(rng)
	twin.randf()
	assert_eq(rng.state, twin.state)
	var entries: Array[LFLootEntry] = [LFLootEntry.nested(table, 1.0)]
	LFLootTable.new(entries).roll(rng)
	twin.randf()
	twin.randf()
	assert_eq(rng.state, twin.state)


func test_the_same_seed_replays_the_same_drops():
	var table := _table([1.0, 2.0], 3.0)
	var a := LFRandom.new(6)
	var b := LFRandom.new(6)
	for i in 100:
		assert_eq(table.roll(a), table.roll(b))


func test_rolling_without_a_generator_is_an_error():
	assert_null(_table([1.0]).roll(null))
	assert_push_error('LFLootTable')


func test_a_table_containing_itself_gives_up():
	var table := LFLootTable.new()
	table.entries.append(LFLootEntry.nested(table, 1.0))
	assert_null(table.roll(LFRandom.new(1)))
	assert_push_error('nested')
	table.entries.clear() # the table holds itself: break the cycle so it is freed


func test_duplicating_keeps_the_authored_fields():
	var inner := _table([1.0])
	var entries: Array[LFLootEntry] = [LFLootEntry.new('a', 2.5, &'x'), LFLootEntry.nested(inner, 1.0)]
	var table := LFLootTable.new(entries, 4.0)
	var copy: LFLootTable = table.duplicate(true)
	assert_eq(copy.nothing_weight, 4.0)
	assert_eq(copy.entries[0].weight, 2.5)
	assert_eq(copy.entries[0].id, &'x')
	assert_eq(copy.entries[0].content, 'a')
	assert_not_null(copy.entries[1].subtable)
	copy.entries[0].weight = 0.0
	assert_eq(copy.pick_index(0.0), 1, 'a copy rolls over its own entries')
	assert_eq(table.pick_index(0.0), 0, 'and the original keeps its own')


func test_total_weight_counts_only_positive_weights_and_entries():
	var table := _table([2.0, -1.0], -5.0)
	table.entries.append(null)
	assert_eq(table.total_weight(), 2.0)


func test_chance_of_an_index_out_of_range_is_zero():
	var table := _table([1.0, 1.0])
	assert_eq(table.chance_of(-1), 0.0)
	assert_eq(table.chance_of(2), 0.0)


func test_a_table_without_positive_weight_is_certain_to_give_nothing():
	assert_eq(_table([0.0, -2.0]).nothing_chance(), 1.0)
	assert_eq(LFLootTable.new().nothing_chance(), 1.0)


func test_find_returns_the_first_match_at_the_top_level_only():
	var inner := _table([1.0])
	var first := LFLootEntry.new('first', 1.0, &'dup')
	var table := LFLootTable.new([first, LFLootEntry.new('second', 1.0, &'dup'), LFLootEntry.nested(inner, 1.0, &'inner')])
	assert_eq(table.find(&'dup'), first)
	assert_null(table.find(&'e0'), 'entries of a nested table are not searched')
	assert_eq(table.find(&'inner').subtable, inner, 'a nested entry keeps its id')


## The object count is process-wide (another test's worker thread may add or free a few
## meanwhile), so the bound is "fewer than one object per ten calls", which still fails if
## a call creates even one object that stays.
func test_a_roll_creates_no_objects():
	var rng := RandomNumberGenerator.new()
	var table := LFLootTable.new([LFLootEntry.nested(_table([1.0, 2.0], 1.0), 2.0), LFLootEntry.new('x', 1.0)], 1.0)
	table.roll(rng)
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 200:
		table.roll(rng)
		table.pick_index(rng.randf())
	assert_lt(Performance.get_monitor(Performance.OBJECT_COUNT) - before, 200 / 10.0, 'no object kept per call')


func _chain(levels: int) -> LFLootTable:
	var table := LFLootTable.new([LFLootEntry.new('bottom')])
	for i in levels:
		table = LFLootTable.new([LFLootEntry.nested(table)])
	return table


func test_nesting_up_to_max_depth_resolves_and_deeper_gives_up():
	assert_eq(LFLootTable.MAX_DEPTH, 32)
	assert_eq(_chain(LFLootTable.MAX_DEPTH).roll(LFRandom.new(1)).content, 'bottom')
	assert_null(_chain(LFLootTable.MAX_DEPTH + 1).roll(LFRandom.new(1)))
	assert_push_error('nested')


func test_an_entry_without_a_weight_gets_the_default():
	assert_eq(LFLootEntry.new('a').weight, LFLootEntry.DEFAULT_WEIGHT)
	assert_eq(LFLootEntry.nested(LFLootTable.new()).weight, LFLootEntry.DEFAULT_WEIGHT)


func test_a_table_saved_as_a_resource_file_loads_back_with_its_entries():
	var path := 'user://test_lf_loot_table_roundtrip_%d.tres' % OS.get_process_id()
	var inner := _table([1.0])
	var entries: Array[LFLootEntry] = [LFLootEntry.new({'item': 'gold', 'amount': 3}, 2.5, &'gold'), LFLootEntry.nested(inner, 1.0, &'rare')]
	assert_eq(ResourceSaver.save(LFLootTable.new(entries, 4.0), path), OK)
	var loaded: LFLootTable = ResourceLoader.load(path, '', ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(loaded.nothing_weight, 4.0)
	assert_eq(loaded.find(&'gold').weight, 2.5)
	assert_eq(loaded.find(&'gold').content, {'item': 'gold', 'amount': 3}, 'a saveable content is kept')
	assert_eq(loaded.find(&'rare').subtable.entries[0].content, 'item-0', 'the nested table comes back too')


func _tier_at_least(entry: LFLootEntry, tier: int) -> bool:
	return entry.content.tier >= tier


func test_a_pity_tracker_drives_a_filtered_roll_so_no_streak_outlasts_the_guarantee():
	# A goblin drop: mostly coins, rarely a gem, often nothing. After 3 drops in a row
	# without a gem, the next drop must be a gem.
	var loot := LFLootTable.new([
		LFLootEntry.new({"name": "coin", "tier": 0}, 70.0),
		LFLootEntry.new({"name": "gem", "tier": 1}, 5.0),
	], 25.0)
	var pity := LFPityTracker.new(3, 1)
	var at_least_gem := _tier_at_least.bind(pity.threshold)
	var rng := LFRandom.new(42)
	var longest_streak := 0
	var guaranteed := 0
	var gems := 0
	for i in 4000:
		var drop: LFLootEntry
		if pity.is_active():
			guaranteed += 1
			drop = loot.roll(rng, at_least_gem)
			assert_not_null(drop, 'a guaranteed roll never gives nothing')
			assert_eq(drop.content.name, 'gem')
		else:
			drop = loot.roll(rng)
		if drop == null:
			pity.record_outcome(false)
		else:
			pity.record(drop.content.tier)
			if drop.content.tier >= 1:
				gems += 1
		longest_streak = maxi(longest_streak, pity.streak)
	assert_eq(longest_streak, 3, 'never more than 3 misses in a row')
	assert_gt(guaranteed, 100, 'the guarantee fired many times over 4000 drops')
	assert_gt(gems, guaranteed, 'some gems came without the guarantee too')


func test_a_filtered_roll_keeps_the_accepted_entries_relative_odds_through_nested_tables():
	# Accepted: "a" (weight 2) and "b", reached through a nested entry of weight 4 whose
	# table accepts a quarter of its weight (1 of 1 + 1 + nothing 2): "b" weighs 1.
	var inner := LFLootTable.new([
		LFLootEntry.new({"name": "b", "tier": 1}, 1.0),
		LFLootEntry.new({"name": "c", "tier": 0}, 1.0),
	], 2.0)
	var table := LFLootTable.new([
		LFLootEntry.new({"name": "a", "tier": 1}, 2.0),
		LFLootEntry.nested(inner, 4.0),
		LFLootEntry.new({"name": "d", "tier": 0}, 10.0),
	], 50.0)
	var rng := LFRandom.new(7)
	var counts := {"a": 0, "b": 0}
	var rolls := 30000
	for i in rolls:
		var drop := table.roll(rng, _tier_at_least.bind(1))
		counts[drop.content.name] += 1
	assert_almost_eq(counts.a / float(rolls), 2.0 / 3.0, 0.02)
	assert_almost_eq(counts.b / float(rolls), 1.0 / 3.0, 0.02)


func test_a_filtered_roll_with_nothing_accepted_gives_null_and_still_draws_one_value():
	var table := _table([1.0, 2.0], 5.0)
	var rng := LFRandom.new(3)
	var twin := LFRandom.new(3)
	assert_null(table.roll(rng, func(_entry: LFLootEntry) -> bool: return false))
	twin.randf()
	assert_eq(rng.state, twin.state)
	assert_null(table.roll(rng, func(_entry: LFLootEntry) -> Variant: return 1), 'only a true bool accepts')


func test_a_filtered_roll_replays_with_the_same_seed():
	var table := _table([1.0, 2.0, 3.0], 3.0)
	var odd := func(entry: LFLootEntry) -> bool: return entry.id != &'e1'
	var a := LFRandom.new(9)
	var b := LFRandom.new(9)
	for i in 100:
		var drop := table.roll(a, odd)
		assert_eq(drop, table.roll(b, odd))
		assert_ne(drop.id, &'e1')


func test_a_filtered_roll_leaves_out_a_table_containing_itself_and_reports_it():
	var table := _table([1.0])
	table.entries.append(LFLootEntry.nested(table, 100.0))
	for i in 20:
		assert_eq(table.roll(LFRandom.new(i), func(_entry: LFLootEntry) -> bool: return true).id, &'e0')
	assert_push_error_count(20, 'reported once per roll')
	table.entries.clear() # the table holds itself: break the cycle so it is freed


func test_an_infinite_weight_is_never_chosen_and_counts_for_nothing_in_the_chances():
	var table := _table([INF, 1.0], INF)
	assert_eq(table.pick_index(0.0), 1)
	assert_eq(table.pick_index(1.0), 1)
	assert_eq(table.total_weight(), 1.0)
	assert_eq(table.chance_of(0), 0.0)
	assert_eq(table.chance_of(1), 1.0)
	assert_eq(table.nothing_chance(), 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 20:
		assert_eq(table.roll(rng, func(_entry): return true).id, &'e1')


func test_weights_whose_sum_overflows_still_give_their_shares():
	var table := _table([1e308, 1e308, 1e308], 1e308)
	assert_eq(table.total_weight(), INF, 'the plain sum overflows')
	assert_almost_eq(table.chance_of(0), 0.25, 1e-12)
	assert_almost_eq(table.nothing_chance(), 0.25, 1e-12)
	assert_eq(table.pick_index(0.3), 1)


func test_a_filtered_roll_through_a_nested_table_whose_weights_overflow():
	var inner := _table([1e308, 1e308])
	var outer := LFLootTable.new([LFLootEntry.nested(inner, 1.0), LFLootEntry.new('z', 1.0)] as Array[LFLootEntry])
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var from_inner := 0
	for i in 200:
		var drop := outer.roll(rng, func(_entry: LFLootEntry) -> bool: return true)
		if drop.content != 'z':
			from_inner += 1
	assert_between(from_inner, 60, 140, 'the nested table keeps its half of the odds')
