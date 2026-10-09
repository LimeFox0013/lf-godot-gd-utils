## Finds stored items by the values they hold, like "every item with the tag `fast`".
##
## This is an inverted index: instead of scanning every item on each lookup, it files each
## item (a Dictionary or an Object) under every value its rules (`LFIndexingRule`) read
## from it, then looks items up by rule name and values: a lookup reads only the buckets of
## the requested values. Items are tracked by identity, so an item changed after `add` can
## still be removed — re-`add` it to re-index it.
##
## Cost: `add`, `remove` and `has` take constant time per bucket for an Object item, and so
## does a lookup per item it returns. A Dictionary has no identity handle in GDScript, so
## it is found by its content hash while it is unchanged; one that changed after `add` is
## found by a scan of all Dictionary items (see the README for the exact cases).
class_name LFInvertIndex
extends RefCounted

## Most records added between two reads for which `_reconcile` compares identities one by one;
## beyond it, it hashes every item once instead.
const _SCAN_PENDING_LIMIT := 4

static var _log := LFLogger.new()


var _rules: Array[LFIndexingRule] = []
## Rule name -> { value -> { sequence number -> item } }, each bucket in insertion order.
var _buckets: Dictionary = {}
## Object item -> its record; found by identity in O(1), whatever the object holds.
var _object_records: Dictionary = {}
## Content hash at `add` time -> { sequence number -> record } for non-Object items
## (Dictionaries…), since a changed Dictionary no longer hashes to its old key.
var _value_records: Dictionary = {}
## Every non-Object record and its item, in parallel Arrays (a plain Array scans faster
## than a Dictionary); a record knows its `slot`, and removal swaps the last one into it.
var _scan_records: Array[_Record] = []
var _scan_items: Array = []
## Non-Object records added since the last `_reconcile`, which may duplicate a record whose
## item changed after it was added.
var _pending: Array[_Record] = []
## Sequence number -> item, for every item in insertion order.
var _items: Dictionary = {}
var _next_sequence := 0


class _Record:
	var item: Variant
	var sequence := 0
	## Content hash when it was filed; only for non-Object items.
	var content_hash := 0
	var alive := true
	## Whether it sits in `_pending`, so a twin of the same item may still be filed.
	var pending := false
	## Position in `_scan_records`; only for non-Object items.
	var slot := -1
	## [bucket Dictionary, rule name, value] for every bucket the item sits in.
	var placements: Array = []


## An index over `rules`. A second rule with an already-used name is reported and dropped.
func _init(rules: Array[LFIndexingRule]) -> void:
	for rule in rules:
		if _buckets.has(rule.name):
			_log.error('LFInvertIndex: two rules are named "%s"; name one with LFIndexingRule.new(path, target, name)' % rule.name)
			continue
		_rules.append(rule)
		_buckets[rule.name] = {}


## Indexes `item` (a Dictionary or an Object) under every value its rules extract
## (re-indexing it if already there).
func add(item: Variant) -> void:
	var is_object := typeof(item) == TYPE_OBJECT
	var content_hash := 0
	var known := false
	var replaces_pending := false
	if is_object:
		_unfile(_object_records.get(item))
	else:
		content_hash = hash(item)
		var existing := _find_by_hash(item, content_hash)
		known = existing != null
		replaces_pending = known and existing.pending
		_unfile(existing)
	var record := _Record.new()
	record.item = item
	record.sequence = _next_sequence
	record.content_hash = content_hash
	_next_sequence += 1
	for rule in _rules:
		var by_value: Dictionary = _buckets[rule.name]
		var seen := {}
		for value: Variant in rule.values_of(item):
			if seen.has(value):
				continue
			seen[value] = true
			if not by_value.has(value):
				by_value[value] = {}
			var bucket: Dictionary = by_value[value]
			bucket[record.sequence] = item
			record.placements.append([bucket, rule.name, value])
	_items[record.sequence] = item
	if is_object:
		_object_records[item] = record
	else:
		if not _value_records.has(content_hash):
			_value_records[content_hash] = {}
		_value_records[content_hash][record.sequence] = record
		record.slot = _scan_records.size()
		_scan_records.append(record)
		_scan_items.append(item)
		# Not found by its hash, so it is new, or an indexed item that changed since.
		# A record still pending may itself have a stale twin, so its replacement is queued too.
		if not known or replaces_pending:
			record.pending = true
			_pending.append(record)


## Removes `item` from every bucket it was indexed under; a no-op for an unknown item.
func remove(item: Variant) -> void:
	_unfile(_find(item))


## Every item indexed under any of `values` by the rule named `rule_name`, each once, in
## first-match order. An unknown `rule_name` reports an error and returns an empty Array.
func get_by_values(rule_name: String, values: Array) -> Array:
	if not _buckets.has(rule_name):
		_log.error('LFInvertIndex: indexing for "%s" does not exist' % rule_name)
		return []
	_reconcile()
	var by_value: Dictionary = _buckets[rule_name]
	var result: Array = []
	var seen := {}
	for value: Variant in values:
		var bucket: Dictionary = by_value.get(value, {})
		for sequence: Variant in bucket:
			if not seen.has(sequence):
				seen[sequence] = true
				result.append(bucket[sequence])
	return result


## Whether `item` is indexed (by identity).
func has(item: Variant) -> bool:
	return _find(item) != null


## How many items are indexed.
func size() -> int:
	_reconcile()
	return _items.size()


## Every indexed item, in insertion order (a copy).
func items() -> Array:
	_reconcile()
	return _items.values()


## Removes every item; the rules stay and keep answering (with nothing).
func clear() -> void:
	for name: Variant in _buckets:
		_buckets[name] = {}
	_object_records.clear()
	_value_records.clear()
	_scan_records.clear()
	_scan_items.clear()
	_pending.clear()
	_items.clear()


## The record of `item`, or null. A non-Object item is found by its current content hash
## and, when that fails (it changed since it was added, or it was never added), by a scan.
func _find(item: Variant) -> _Record:
	# `typeof`, not `is`: `is` is a script error on a freed Object, which `remove` must accept.
	if typeof(item) == TYPE_OBJECT:
		return _object_records.get(item)
	_reconcile()
	var found := _find_by_hash(item, hash(item))
	if found != null:
		return found
	for i in _scan_items.size():
		if is_same(_scan_items[i], item):
			return _scan_records[i]
	return null


func _find_by_hash(item: Variant, content_hash: int) -> _Record:
	var same_hash: Dictionary = _value_records.get(content_hash, {})
	for sequence: Variant in same_hash:
		var record: _Record = same_hash[sequence]
		if is_same(record.item, item):
			return record
	return null


## Takes a record out of every bucket and table.
func _unfile(record: _Record) -> void:
	if record == null:
		return
	record.alive = false
	for placement: Variant in record.placements:
		var bucket: Dictionary = placement[0]
		bucket.erase(record.sequence)
		if bucket.is_empty():
			_buckets[placement[1]].erase(placement[2])
	_items.erase(record.sequence)
	if typeof(record.item) == TYPE_OBJECT:
		_object_records.erase(record.item)
	else:
		var same_hash: Dictionary = _value_records.get(record.content_hash, {})
		same_hash.erase(record.sequence)
		if same_hash.is_empty():
			_value_records.erase(record.content_hash)
		var last := _scan_records.size() - 1
		var moved := _scan_records[last]
		_scan_records[record.slot] = moved
		_scan_items[record.slot] = _scan_items[last]
		moved.slot = record.slot
		_scan_records.resize(last)
		_scan_items.resize(last)
		record.slot = -1


## Drops the older of two records that hold the same non-Object item, which happens when an
## item changed after it was added and was added again (its new content hash found
## nothing). One pass over the non-Object records finds those that changed; it runs only
## when something was added since the last one.
func _reconcile() -> void:
	if _pending.is_empty():
		return
	if _pending.size() <= _SCAN_PENDING_LIMIT:
		# Comparing identities is cheaper than hashing every item while few were added.
		for added in _pending:
			if added.alive:
				_unfile_older_twin(added)
		_clear_pending()
		return
	var changed: Array[_Record] = []
	for record in _scan_records:
		if hash(record.item) != record.content_hash:
			changed.append(record)
	for added in _pending:
		if not added.alive:
			continue
		for old in changed:
			if old.alive and old != added and is_same(old.item, added.item):
				_unfile(old if old.sequence < added.sequence else added)
				break
	_clear_pending()
	for record in changed:
		if record.alive:
			_value_records[record.content_hash].erase(record.sequence)
			if _value_records[record.content_hash].is_empty():
				_value_records.erase(record.content_hash)
			record.content_hash = hash(record.item)
			if not _value_records.has(record.content_hash):
				_value_records[record.content_hash] = {}
			_value_records[record.content_hash][record.sequence] = record


func _clear_pending() -> void:
	for record in _pending:
		record.pending = false
	_pending.clear()


## Drops the older record that holds the same item as `added`, if any.
func _unfile_older_twin(added: _Record) -> void:
	for i in _scan_items.size():
		if i != added.slot and is_same(_scan_items[i], added.item):
			var record := _scan_records[i]
			_unfile(record if record.sequence < added.sequence else added)
			return
