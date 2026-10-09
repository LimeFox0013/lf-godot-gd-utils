extends GutTest

enum Section { FIRST, SECOND }

var inventory: LFSlotInventory
var _changes := 0


class Item:
	var name: String

	func _init(item_name := '') -> void:
		name = item_name


func _on_changed() -> void:
	_changes += 1


func before_each():
	inventory = LFSlotInventory.new({Section.FIRST: 5, Section.SECOND: 2})
	_changes = 0
	inventory.changed.connect(_on_changed)


func test_sections_have_their_declared_slot_counts():
	assert_eq(inventory.sections(), [Section.FIRST, Section.SECOND])
	assert_eq(inventory.slot_count(Section.FIRST), 5)
	assert_eq(inventory.slot_count(Section.SECOND), 2)
	assert_eq(inventory.slots(Section.SECOND), [null, null])


func test_adding_fills_the_first_section_before_the_next():
	for i in 5:
		assert_true(inventory.add(Item.new()))
	var sixth := Item.new()
	inventory.add(sixth)

	assert_eq(inventory.items(Section.FIRST).size(), 5)
	assert_eq(inventory.section_of(sixth), Section.SECOND)
	assert_eq(inventory.index_of(sixth), 0)


func test_the_add_order_can_differ_from_the_declaration_order():
	var second_first := LFSlotInventory.new({Section.FIRST: 1, Section.SECOND: 1}, [Section.SECOND, Section.FIRST])
	var first := Item.new()
	var second := Item.new()
	second_first.add(first)
	second_first.add(second)
	assert_eq(second_first.section_of(first), Section.SECOND)
	assert_eq(second_first.section_of(second), Section.FIRST)
	assert_eq(second_first.items(), [second, first], 'items() still lists sections in declaration order')


func test_a_section_left_out_of_the_add_order_is_never_filled_by_add():
	var first_only := LFSlotInventory.new({&'section_a': 1, &'section_b': 3}, [&'section_a'])
	assert_true(first_only.add(Item.new()))
	assert_false(first_only.add(Item.new()), 'section_b takes items only by add_to or move')
	assert_true(first_only.add_to(Item.new(), &'section_b'))


func test_adding_fails_once_every_slot_is_full():
	for i in 7:
		inventory.add(Item.new())
	assert_false(inventory.has_room())
	assert_false(inventory.add(Item.new()))
	assert_eq(_changes, 7, 'a failed add announces nothing')


func test_has_room_per_section():
	for i in 5:
		inventory.add(Item.new())
	assert_false(inventory.has_room(Section.FIRST))
	assert_true(inventory.has_room(Section.SECOND))
	assert_true(inventory.has_room())


func test_an_item_is_held_once():
	var item := Item.new()
	assert_true(inventory.add(item))
	assert_false(inventory.add(item))
	assert_false(inventory.add_to(item, Section.SECOND))
	assert_eq(inventory.items().size(), 1)


func test_a_null_item_is_reported():
	assert_false(inventory.add(null))
	assert_push_error('null')


func test_add_to_uses_that_sections_first_free_slot():
	var item := Item.new()
	assert_true(inventory.add_to(item, Section.SECOND))
	assert_eq(inventory.section_of(item), Section.SECOND)
	inventory.add_to(Item.new(), Section.SECOND)
	assert_false(inventory.add_to(Item.new(), Section.SECOND), 'full')


func test_sections_can_grow():
	inventory.grow(Section.FIRST, 1)
	inventory.grow(Section.SECOND, 2)
	assert_eq(inventory.slot_count(Section.FIRST), 6)
	assert_eq(inventory.slot_count(Section.SECOND), 4)
	assert_eq(_changes, 2)


func test_growing_by_nothing_or_an_unknown_section_is_reported():
	inventory.grow(Section.FIRST, 0)
	assert_push_error('positive')
	inventory.grow(&'nope', 1)
	assert_push_error('not a section')
	assert_eq(_changes, 0)


func test_move_goes_to_the_other_sections_first_free_slot():
	var item := Item.new()
	inventory.add(item)

	assert_true(inventory.move(item))
	assert_eq(inventory.section_of(item), Section.SECOND)
	assert_true(inventory.move(item))
	assert_eq(inventory.section_of(item), Section.FIRST)
	assert_eq(inventory.index_of(item), 0)


func test_move_into_a_full_section_changes_nothing():
	var kept := Item.new()
	inventory.add(kept)
	inventory.add_to(Item.new(), Section.SECOND)
	inventory.add_to(Item.new(), Section.SECOND)
	var before := _changes
	assert_false(inventory.move(kept))
	assert_false(inventory.move(kept, Section.SECOND))
	assert_eq(inventory.section_of(kept), Section.FIRST)
	assert_eq(_changes, before)


func test_move_to_a_named_section_or_its_own_section():
	var item := Item.new()
	inventory.add(item)
	assert_false(inventory.move(item, Section.FIRST), 'already there')
	assert_true(inventory.move(item, Section.SECOND))
	assert_false(inventory.move(Item.new()), 'not held')


func test_removing_leaves_the_slot_empty_without_shifting_neighbors():
	var a := Item.new()
	var b := Item.new()
	inventory.add(a)
	inventory.add(b)

	assert_true(inventory.remove(a))

	assert_null(inventory.item_at(Section.FIRST, 0))
	assert_eq(inventory.index_of(b), 1)
	assert_false(inventory.remove(a), 'no longer held')
	assert_false(inventory.has(a))


func test_a_freed_slot_is_the_next_one_filled():
	var a := Item.new()
	inventory.add(a)
	inventory.add(Item.new())
	inventory.remove(a)
	var c := Item.new()
	inventory.add(c)
	assert_eq(inventory.index_of(c), 0)


func test_lookups_of_items_that_are_not_held():
	assert_null(inventory.section_of(Item.new()))
	assert_null(inventory.section_of(null))
	assert_eq(inventory.index_of(Item.new()), -1)
	assert_null(inventory.item_at(Section.FIRST, 99))
	assert_null(inventory.item_at(Section.FIRST, -1))


func test_items_lists_each_section_in_slot_order():
	var a := Item.new('a')
	var b := Item.new('b')
	var c := Item.new('c')
	inventory.add(a)
	inventory.add(b)
	inventory.add_to(c, Section.SECOND)
	inventory.remove(a)
	assert_eq(inventory.items(Section.FIRST), [b])
	assert_eq(inventory.items(Section.SECOND), [c])
	assert_eq(inventory.items(), [b, c])


func test_slots_is_a_copy():
	var copy := inventory.slots(Section.FIRST)
	copy[0] = Item.new()
	assert_null(inventory.item_at(Section.FIRST, 0))


func test_an_unknown_section_is_reported():
	assert_eq(inventory.slot_count(&'nope'), 0)
	assert_push_error('not a section')
	assert_false(inventory.add_to(Item.new(), &'nope'))
	assert_push_error('not a section')


func test_an_add_order_naming_an_unknown_section_is_reported():
	var odd := LFSlotInventory.new({&'a': 1}, [&'b', &'a'])
	assert_push_error('not a section')
	assert_true(odd.add(Item.new()))


func test_a_negative_slot_count_is_an_empty_section():
	assert_eq(LFSlotInventory.new({&'a': -3}).slot_count(&'a'), 0)


func test_moving_to_its_own_section_named_as_a_string_changes_nothing():
	var named := LFSlotInventory.new({&'section_a': 3, &'section_b': 3})
	var first := Item.new()
	var item := Item.new()
	named.add(first)
	named.add(item)
	named.remove(first)

	assert_false(named.move(item, 'section_a'), 'a String names the same section as its StringName')
	assert_eq(named.index_of(item), 1, 'the item kept its slot')


func test_every_change_is_announced_once():
	var item := Item.new()
	inventory.add(item)
	inventory.move(item)
	inventory.remove(item)
	inventory.add_to(Item.new(), Section.SECOND)
	assert_eq(_changes, 4)


func test_failed_calls_announce_nothing():
	var held := Item.new()
	inventory.add(held)
	_changes = 0
	inventory.remove(Item.new())
	inventory.move(Item.new())
	inventory.move(held, Section.FIRST)
	inventory.add(held)
	inventory.add_to(held, Section.SECOND)
	assert_eq(_changes, 0)


func test_lookups_of_an_unknown_section_are_reported_and_empty():
	assert_eq(inventory.slots(&'nope'), [])
	assert_push_error('not a section')
	assert_null(inventory.item_at(&'nope', 0))
	assert_push_error('not a section')
	assert_false(inventory.has_room(&'nope'))
	assert_push_error('not a section')
	assert_eq(inventory.items(&'nope'), [])
	assert_push_error('not a section')


func test_moving_to_an_unknown_section_is_reported_and_changes_nothing():
	var item := Item.new()
	inventory.add(item)
	assert_false(inventory.move(item, &'nope'))
	assert_push_error('not a section')
	assert_eq(inventory.section_of(item), Section.FIRST)


func test_add_to_refuses_a_null_item():
	assert_false(inventory.add_to(null, Section.FIRST))
	assert_push_error('null')


func test_a_move_without_a_target_only_looks_at_the_add_order():
	var two := LFSlotInventory.new({&'a': 1, &'b': 1, &'c': 1}, [&'a', &'b'])
	var first := Item.new()
	var second := Item.new()
	two.add(first)
	two.add(second)
	assert_false(two.move(first), 'b is full and c is not in the add order')
	assert_true(two.move(first, &'c'), 'a named target outside the add order is fine')


func test_an_empty_inventory_has_no_room_and_takes_nothing():
	var empty := LFSlotInventory.new()
	assert_eq(empty.sections(), [])
	assert_false(empty.has_room())
	assert_false(empty.add(Item.new()))
	assert_eq(empty.items(), [])


func test_a_grown_section_takes_new_items_in_the_new_slots():
	for i in 7:
		inventory.add(Item.new())
	inventory.grow(Section.SECOND, 1)
	var late := Item.new()
	assert_true(inventory.add(late))
	assert_eq(inventory.section_of(late), Section.SECOND)
	assert_eq(inventory.index_of(late), 2)


func test_sections_returns_a_copy():
	inventory.sections().clear()
	assert_eq(inventory.sections(), [Section.FIRST, Section.SECOND])


func test_a_freed_item_leaves_its_slot_free():
	var node := Node.new()
	var single := LFSlotInventory.new({&'a': 1})
	single.add(node)
	node.free()
	assert_true(single.has_room(), 'the slot of a freed item counts as free')
	assert_eq(single.slots(&'a'), [null])
	assert_null(single.item_at(&'a', 0))
	var fresh := Item.new()
	assert_true(single.add(fresh))
	assert_eq(single.items(), [fresh])
