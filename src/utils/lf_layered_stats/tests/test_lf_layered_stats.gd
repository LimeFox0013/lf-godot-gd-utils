extends GutTest

var stats: LFLayeredStats


static func _sum(total: float, value: float) -> float:
	return total + value


static func _product(total: float, value: float) -> float:
	return total * value


func before_each():
	stats = LFLayeredStats.new()


func _standard() -> LFLayeredStats:
	var s := LFLayeredStats.new()
	s.declare_layer('base', _sum)
	s.declare_layer('flat', _sum)
	s.declare_layer('mult', _product, 1.0)
	return s


func test_a_single_layer_resolves_to_its_own_value():
	stats.declare_layer('base', _sum)
	stats.set_layer_values('base', {'stat_a': 10.0})
	assert_eq(stats.resolve('stat_a'), 10.0)


func test_layers_fold_in_declaration_order_through_their_own_combine_rule():
	var s := _standard()
	s.set_layer_values('base', {'stat_a': 10.0})
	s.set_layer_values('flat', {'stat_a': 5.0})
	s.set_layer_values('mult', {'stat_a': 2.0})
	assert_eq(s.resolve('stat_a'), 30.0, '(10 + 5) * 2')


func test_the_first_layer_seeds_the_total_and_its_combine_is_never_called():
	stats.declare_layer('base', func(_t, _v): assert_true(false, 'never called'); return 0.0)
	stats.declare_layer('mult', _product, 1.0)
	stats.set_layer_values('base', {'stat_a': 4.0})
	assert_eq(stats.resolve('stat_a'), 4.0)


func test_no_layers_resolves_to_zero():
	assert_eq(stats.resolve('stat_a'), 0.0)


func test_an_unset_key_contributes_the_layers_identity():
	var s := _standard()
	s.set_layer_values('base', {'stat_a': 10.0})
	assert_eq(s.resolve('stat_a'), 10.0)
	assert_eq(s.resolve('stat_b'), 0.0, 'the first layer\'s identity')


func test_any_caller_arithmetic_can_be_a_combine_rule():
	stats.declare_layer('base', _sum)
	stats.declare_layer('cap', func(t, v): return minf(t, v), INF)
	stats.set_layer_values('base', {'stat_c': 1.4, 'stat_b': 3.0})
	stats.set_layer_values('cap', {'stat_c': 1.0})
	assert_eq(stats.resolve('stat_c'), 1.0)
	assert_eq(stats.resolve('stat_b'), 3.0)


func test_resolve_recomputes_every_time():
	stats.declare_layer('base', _sum)
	stats.set_value('base', 'stat_a', 1.0)
	assert_eq(stats.resolve('stat_a'), 1.0)
	stats.set_value('base', 'stat_a', 2.0)
	assert_eq(stats.resolve('stat_a'), 2.0)


func test_redeclaring_keeps_the_position_and_the_values():
	var s := _standard()
	s.set_layer_values('base', {'stat_a': 10.0})
	s.set_layer_values('mult', {'stat_a': 2.0})
	s.declare_layer('base', _sum)
	assert_eq(s.resolve('stat_a'), 20.0, 'base is still first')
	s.declare_layer('mult', _sum, 0.0)
	assert_eq(s.resolve('stat_a'), 12.0, 'the new rule applies at the same position')


func test_redeclaring_changes_the_identity():
	stats.declare_layer('base', _sum)
	stats.declare_layer('mult', _product, 1.0)
	stats.set_layer_values('base', {'stat_a': 3.0})
	stats.declare_layer('mult', _product, 2.0)
	assert_eq(stats.resolve('stat_a'), 6.0)


func test_an_undeclared_layer_is_an_error_and_changes_nothing():
	stats.set_value('nope', 'stat_a', 1.0)
	assert_push_error('not declared')
	assert_eq(stats.get_value('nope', 'stat_a'), 0.0)
	assert_push_error('not declared')
	assert_false(stats.has_layer('nope'))


func test_set_layer_values_replaces_rather_than_merges():
	var s := _standard()
	s.set_layer_values('flat', {'a': 1.0, 'b': 2.0})
	s.set_layer_values('flat', {'a': 5.0})
	assert_eq(s.get_value('flat', 'b'), 0.0)
	assert_eq(s.get_value('flat', 'a'), 5.0)


func test_an_adopted_dictionary_is_never_written_to():
	var shared := {'stat_a': 1.0}
	var a := _standard()
	var b := _standard()
	a.set_layer_values('flat', shared)
	b.set_layer_values('flat', shared)
	a.set_value('flat', 'stat_a', 9.0)
	a.accumulate('flat', 'stat_a', 1.0)
	assert_eq(shared, {'stat_a': 1.0}, 'writes copy first')
	assert_eq(b.get_value('flat', 'stat_a'), 1.0)
	assert_eq(a.get_value('flat', 'stat_a'), 10.0)


func test_a_read_only_dictionary_can_be_adopted():
	var frozen := {'stat_a': 2.0}
	frozen.make_read_only()
	var s := _standard()
	s.set_layer_values('flat', frozen)
	s.accumulate('flat', 'stat_a', 1.0)
	assert_eq(s.get_value('flat', 'stat_a'), 3.0)


func test_accumulate_folds_through_the_layers_rule():
	var s := _standard()
	assert_eq(s.accumulate('mult', 'stat_a', 1.5), 1.5, 'from the identity 1.0')
	assert_eq(s.accumulate('mult', 'stat_a', 2.0), 3.0)
	assert_eq(s.accumulate('flat', 'stat_a', 2.0), 2.0)


func test_reading_never_creates_anything():
	var s := _standard()
	var before := s.get_layer_values('flat')
	s.get_value('flat', 'stat_a')
	s.resolve('stat_a')
	assert_true(before.is_empty())
	assert_true(before.is_read_only(), 'an unset layer reads as a shared empty dictionary')
	assert_true(is_same(before, s.get_layer_values('mult')))


func test_a_cleared_layer_reads_as_its_identity():
	var s := _standard()
	s.set_value('flat', 'stat_a', 3.0)
	s.clear_layer('flat')
	assert_eq(s.get_value('flat', 'stat_a'), 0.0)


func test_instances_sharing_a_layout_keep_their_own_values():
	var layout := LFLayeredStats.Layout.new()
	layout.declare('base', _sum)
	layout.declare('mult', _product, 1.0)
	var a := LFLayeredStats.new(layout)
	var b := LFLayeredStats.new(layout)
	a.set_value('base', 'stat_a', 10.0)
	b.set_value('base', 'stat_a', 4.0)
	b.set_value('mult', 'stat_a', 2.0)
	assert_eq(a.resolve('stat_a'), 10.0)
	assert_eq(b.resolve('stat_a'), 8.0)
	assert_eq(layout.size(), 2)
	assert_eq(layout.identity_of('mult'), 1.0)


func test_declaring_on_one_instance_never_changes_a_shared_layout():
	var layout := LFLayeredStats.Layout.new()
	layout.declare('base', _sum)
	var a := LFLayeredStats.new(layout)
	var b := LFLayeredStats.new(layout)
	a.set_value('base', 'stat_a', 2.0)
	a.declare_layer('mult', _product, 3.0)
	assert_eq(a.resolve('stat_a'), 6.0)
	assert_false(layout.has('mult'))
	assert_false(b.has_layer('mult'))


func test_a_layout_that_grows_later_reads_as_identity_on_older_instances():
	var layout := LFLayeredStats.Layout.new()
	layout.declare('base', _sum)
	var a := LFLayeredStats.new(layout)
	a.set_value('base', 'stat_a', 2.0)
	layout.declare('mult', _product, 1.0)
	assert_eq(a.resolve('stat_a'), 2.0)
	a.set_value('mult', 'stat_a', 3.0)
	assert_eq(a.resolve('stat_a'), 6.0)


func test_an_instance_can_be_freed():
	var s := _standard()
	s.set_value('flat', 'stat_a', 1.0)
	var ref: WeakRef = weakref(s)
	s = null
	assert_null(ref.get_ref())


func test_the_stock_combine_rules():
	assert_eq(LFLayeredStats.sum(2.0, 3.0), 5.0)
	assert_eq(LFLayeredStats.product(2.0, 3.0), 6.0)
	assert_eq(LFLayeredStats.min_of(2.0, 3.0), 2.0)
	assert_eq(LFLayeredStats.max_of(2.0, 3.0), 3.0)
	var layout := LFLayeredStats.Layout.new()
	layout.declare(&'base', LFLayeredStats.sum)
	layout.declare(&'mult', LFLayeredStats.product, 1.0)
	layout.declare(&'cap', LFLayeredStats.min_of, INF)
	layout.declare(&'floor', LFLayeredStats.max_of, -INF)
	var folded := LFLayeredStats.new(layout)
	folded.set_value(&'base', 'stat_a', 10.0)
	folded.set_value(&'mult', 'stat_a', 3.0)
	folded.set_value(&'cap', 'stat_a', 25.0)
	assert_eq(folded.resolve('stat_a'), 25.0, '10 × 3, capped at 25')
	folded.set_value(&'floor', 'stat_a', 40.0)
	assert_eq(folded.resolve('stat_a'), 40.0, 'then raised to 40')
	assert_eq(folded.resolve('stat_b'), 0.0, 'identities only')


func test_the_identity_of_an_undeclared_layer_is_zero():
	var layout := LFLayeredStats.Layout.new()
	layout.declare(&'mult', _product, 1.0)
	assert_eq(layout.identity_of(&'mult'), 1.0)
	assert_eq(layout.identity_of(&'nope'), 0.0)


func test_writes_to_an_undeclared_layer_are_errors_and_change_nothing():
	stats.declare_layer(&'base', _sum)
	stats.set_value(&'base', 'stat_a', 5.0)
	assert_eq(stats.accumulate(&'nope', 'stat_a', 3.0), 0.0)
	assert_push_error('not declared')
	stats.set_layer_values(&'nope', {'stat_a': 100.0})
	assert_push_error('not declared')
	stats.clear_layer(&'nope')
	assert_push_error('not declared')
	assert_eq(stats.resolve('stat_a'), 5.0)
	assert_false(stats.has_layer(&'nope'))


## The object count is process-wide (another test's worker thread may add or free a few
## meanwhile), so the bound is "fewer than one object per ten calls", which still fails if
## a call creates even one object that stays.
func test_resolve_creates_no_objects():
	var layout := LFLayeredStats.Layout.new()
	layout.declare(&'base', LFLayeredStats.sum)
	layout.declare(&'mult', LFLayeredStats.product, 1.0)
	var folded := LFLayeredStats.new(layout)
	folded.set_value(&'base', 'stat_a', 10.0)
	folded.set_value(&'mult', 'stat_a', 2.0)
	folded.resolve('stat_a')
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 200:
		folded.resolve('stat_a')
		folded.resolve('missing')
	assert_lt(Performance.get_monitor(Performance.OBJECT_COUNT) - before, 200 / 10.0, 'no object kept per call')


func test_get_layer_values_returns_the_adopted_dictionary():
	var s := _standard()
	var shared := {'stat_a': 4.0}
	s.set_layer_values('flat', shared)
	assert_true(is_same(s.get_layer_values('flat'), shared))
	assert_eq(s.get_layer_values('nope'), {})
	assert_push_error('not declared')


func test_a_layer_never_written_reads_as_its_identity_and_clears_quietly():
	var s := _standard()
	s.set_value('base', 'stat_a', 2.0)
	assert_eq(s.get_value('mult', 'stat_a'), 1.0, 'no dictionary exists for mult yet')
	s.clear_layer('mult')
	assert_push_error_count(0, 'clearing a declared but unset layer is not an error')
	assert_eq(s.resolve('stat_a'), 2.0)


func test_clearing_an_adopted_dictionary_leaves_it_untouched():
	var shared := {'stat_a': 4.0}
	var a := _standard()
	var b := _standard()
	a.set_layer_values('flat', shared)
	b.set_layer_values('flat', shared)
	a.clear_layer('flat')
	assert_eq(shared, {'stat_a': 4.0})
	assert_eq(a.get_value('flat', 'stat_a'), 0.0)
	assert_eq(b.get_value('flat', 'stat_a'), 4.0)
	a.set_value('flat', 'stat_b', 1.0)
	assert_eq(shared, {'stat_a': 4.0}, 'a write after clearing does not reach the adopted dictionary')


func test_declaring_a_layer_without_a_usable_rule_is_reported_and_ignored():
	var s := LFLayeredStats.new()
	s.declare_layer('base', LFLayeredStats.sum)
	s.declare_layer('broken', Callable())
	assert_push_error_count(1)
	assert_false(s.has_layer('broken'))
	assert_eq(s.resolve('stat_a'), 0.0, 'resolving still works')
