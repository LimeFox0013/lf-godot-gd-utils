## An inventory of fixed slots in named sections, like a 5-slot row and a 20-slot row.
##
## Each section is a row of slots of fixed length (a short row that fills first and a long
## overflow row). Every slot holds one item or null; positions are stable, so an item never
## shifts when its neighbor leaves. A new item goes to the first free slot of the first
## section in the add order that has one; `move` sends an item to another section's first
## free slot. Sections grow with `grow`. Items are any non-null values (normally Objects),
## found by `==`; a freed Object reads as an empty slot. `changed` fires on every change.
##
## Bookkeeping only: what an item is, what it may merge with, or what a section allows is
## the caller's. Extend it, or keep one inside your own class.
class_name LFSlotInventory
extends RefCounted

static var _log := LFLogger.new()


## Emitted after every add, remove, move and grow (never when a call changes nothing).
signal changed

## section -> Array of slots (item or null).
var _slots: Dictionary = {}
## The sections in declaration order.
var _sections: Array = []
## Where `add` looks, in order.
var _add_order: Array = []


## Sections `sizes` (`{section: slot_count}`, in that order); `add` fills them in
## `add_order` (every section when empty: declaration order). Section keys are any
## values; a negative count counts as 0, and an `add_order` entry that is not a section is
## reported and skipped.
func _init(sizes: Dictionary = {}, add_order: Array = []) -> void:
	for section: Variant in sizes:
		var row: Array = []
		row.resize(maxi(int(sizes[section]), 0))
		_slots[section] = row
		_sections.append(section)
	for section: Variant in add_order if not add_order.is_empty() else _sections:
		if not _slots.has(section):
			_log.error("LFSlotInventory: add order names '%s', which is not a section" % [section])
			continue
		_add_order.append(section)


## The sections, in declaration order.
func sections() -> Array:
	return _sections.duplicate()


## How many slots `section` has (0, reported, for an unknown section).
func slot_count(section: Variant) -> int:
	var row: Variant = _section(section)
	return row.size() if row != null else 0


## A copy of `section`'s slots: each an item or null, by position.
func slots(section: Variant) -> Array:
	var row: Variant = _section(section)
	if row == null:
		return []
	var copy: Array = row.duplicate()
	for i in copy.size():
		if copy[i] == null: # a freed Object reads as empty
			copy[i] = null
	return copy


## The item in `section`'s slot `index`, or null when empty or out of range.
func item_at(section: Variant, index: int) -> Variant:
	var row: Variant = _section(section)
	if row == null or index < 0 or index >= row.size():
		return null
	var item: Variant = row[index]
	return item if item != null else null # a freed Object reads as empty


## Whether a slot is free in `section`, or in any section when `section` is null.
func has_room(section: Variant = null) -> bool:
	if section != null:
		var row: Variant = _section(section)
		if row == null:
			return false
		var section_slots: Array = row
		return _free_index(section_slots) != -1
	for each: Variant in _sections:
		var section_slots: Array = _slots[each]
		if _free_index(section_slots) != -1:
			return true
	return false


## Puts `item` in the first free slot of the first section in the add order that has one.
## False — nothing changes — when every slot is full, when `item` is already held, or for
## a null item (reported).
func add(item: Variant) -> bool:
	if not _can_hold(item):
		return false
	for section: Variant in _add_order:
		var row: Array = _slots[section]
		var index := _free_index(row)
		if index != -1:
			row[index] = item
			changed.emit()
			return true
	return false


## Puts `item` in `section`'s first free slot. False when it is full, when `item` is
## already held, or for a null item or an unknown section (reported).
func add_to(item: Variant, section: Variant) -> bool:
	var row: Variant = _section(section)
	if row == null or not _can_hold(item):
		return false
	var section_slots: Array = row
	var index := _free_index(section_slots)
	if index == -1:
		return false
	section_slots[index] = item
	changed.emit()
	return true


## Empties `item`'s slot. False when it isn't held.
func remove(item: Variant) -> bool:
	var section: Variant = section_of(item)
	if section == null:
		return false
	var row: Array = _slots[section]
	row[row.find(item)] = null
	changed.emit()
	return true


## Moves `item` to the first free slot of `to_section`, or — when it is null — of the
## first section in the add order, other than its own, that has one. False — nothing
## changes — when `item` isn't held, the target is its own section or full, or there is
## no free slot elsewhere.
func move(item: Variant, to_section: Variant = null) -> bool:
	var from: Variant = section_of(item)
	if from == null:
		return false
	var from_slots: Array = _slots[from]
	var target_slots: Variant = null
	if to_section == null:
		for section: Variant in _add_order:
			var row: Array = _slots[section]
			if not is_same(row, from_slots) and _free_index(row) != -1:
				target_slots = row
				break
		if target_slots == null:
			return false
	else:
		target_slots = _section(to_section)
	# Compared by row, so a String naming a StringName section still counts as its own.
	if target_slots == null or is_same(target_slots, from_slots):
		return false
	var target_row: Array = target_slots
	var index := _free_index(target_row)
	if index == -1:
		return false
	from_slots[from_slots.find(item)] = null
	target_slots[index] = item
	changed.emit()
	return true


## The section holding `item`, or null.
func section_of(item: Variant) -> Variant:
	if item == null:
		return null
	for section: Variant in _sections:
		if _slots[section].has(item):
			return section
	return null


## `item`'s slot index within its section, or -1 when it isn't held.
func index_of(item: Variant) -> int:
	var section: Variant = section_of(item)
	return _slots[section].find(item) if section != null else -1


## Whether `item` is held anywhere.
func has(item: Variant) -> bool:
	return section_of(item) != null


## The held items of `section` in slot order, or of every section (in declaration order)
## when `section` is null. A new array each call.
func items(section: Variant = null) -> Array:
	var held: Array = []
	for each: Variant in _sections if section == null else [section]:
		var row: Variant = _section(each)
		if row == null:
			continue
		for item: Variant in row:
			if item != null:
				held.append(item)
	return held


## Adds `count` empty slots to the end of `section`. A non-positive count or an unknown
## section is reported and changes nothing.
func grow(section: Variant, count: int) -> void:
	var row: Variant = _section(section)
	if row == null:
		return
	if count <= 0:
		_log.error("LFSlotInventory: grow needs a positive count, got %d" % count)
		return
	row.resize(row.size() + count)
	changed.emit()


func _section(section: Variant) -> Variant:
	var row: Variant = _slots.get(section)
	if row == null:
		_log.error("LFSlotInventory: '%s' is not a section" % [section])
	return row


# The first free slot of `row`, or -1. A freed Object counts as free.
static func _free_index(row: Array) -> int:
	for i in row.size():
		if row[i] == null:
			return i
	return -1


func _can_hold(item: Variant) -> bool:
	if item == null:
		_log.error("LFSlotInventory: an item can't be null")
		return false
	return not has(item)
