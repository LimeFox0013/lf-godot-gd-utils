## Gives live objects short, stable text ids like `item-7`, and finds the object from its id.
##
## A two-way mapping between live objects and readable ids (`<prefix>-<n>`): the same
## object keeps the same id until it is released, and a released id is never issued again. For
## network messages, saves and logs that must name objects.
class_name LFObjectIdRegistry

## The shape of an id: the prefix, a dash, the index.
const _ID_FORMAT := '%s-%d'
## The index of the first id a registry issues.
const _FIRST_INDEX := 1
## Fewest ids assigned between two sweeps of the entries of objects freed without a
## release (see the README's Notes).
const _SWEEP_MIN_INTERVAL := 32

static var _log := LFLogger.new()


## The text before every id. Read-only.
var prefix: String:
	get:
		return _prefix
	set(_value):
		_log.error("LFObjectIdRegistry.prefix is read-only")

var _prefix: String
var _ids_by_object := {}
var _objects_by_id := {}
var _next_index := _FIRST_INDEX
## Ids assigned since the last sweep of freed objects (see `_sweep_if_due`).
var _assigned_since_sweep := 0
## How many entries the last sweep left (all of them live then).
var _entries_after_sweep := 0


## A registry issuing ids `<id_prefix>-1`, `<id_prefix>-2`, ...
func _init(id_prefix: String) -> void:
	_prefix = id_prefix


## `object`'s id (any Object, a Node included), assigned on first request. With `release_on`, the id is released when
## that signal first fires, whatever arguments it carries; only the call that assigns the
## id connects it (a later `release_on` for an object that has an id is ignored). A freed
## object gets `''` and an error. Every max(32, entries left by the previous sweep) new ids,
## it also forgets the ids of objects that were freed without being released.
func id_for(object: Variant, release_on: Signal = Signal()) -> String:
	if not is_instance_valid(object):
		_log.error("LFObjectIdRegistry: can't give an id to a freed, null or non-object value")
		return ''
	if _ids_by_object.has(object):
		return _ids_by_object[object]
	_sweep_if_due()
	var id := _ID_FORMAT % [_prefix, _next_index]
	_next_index += 1
	_ids_by_object[object] = id
	_objects_by_id[id] = object
	if not release_on.is_null():
		# Binds the id, not the object: the signal usually belongs to the object itself,
		# and binding the object into its own signal would keep it alive.
		release_on.connect(_release_from_signal.bind(id), CONNECT_ONE_SHOT)
	return id


## `object`'s id, or `''` if it has none — never assigns one.
func find_id(object: Variant) -> String:
	if not is_instance_valid(object):
		return ''
	return _ids_by_object.get(object, '')


## The live object with `id`, or null (unknown, released or freed).
func object_for(id: String) -> Object:
	var object: Variant = _objects_by_id.get(id)
	return object if is_instance_valid(object) else null


## Whether `object` is live and holds an id. Safe on a freed object.
func has_object(object: Variant) -> bool:
	return is_instance_valid(object) and _ids_by_object.has(object)


## Forgets `id` and its object; a no-op for an unknown or already released id.
func release_id(id: String) -> void:
	if _objects_by_id.has(id):
		_ids_by_object.erase(_objects_by_id[id])
		_objects_by_id.erase(id)


## Forgets `object`'s id — also when the object was freed meanwhile; a no-op for an object
## without an id.
func release(object: Variant) -> void:
	if is_instance_valid(object):
		if _ids_by_object.has(object):
			release_id(_ids_by_object[object])
		return
	for id: Variant in _objects_by_id.keys():
		if is_same(_objects_by_id[id], object):
			release_id(id)
			return


# Forgets freed objects once max(32, entries left by the last sweep) ids were assigned
# since it. A sweep costs O(entries), at most twice that interval, so O(1) per assignment
# on average; and the entries never exceed the ones left by the last sweep plus one
# interval.
func _sweep_if_due() -> void:
	_assigned_since_sweep += 1
	if _assigned_since_sweep < maxi(_entries_after_sweep, _SWEEP_MIN_INTERVAL):
		return
	_assigned_since_sweep = 0
	for id: String in _objects_by_id.keys():
		if not is_instance_valid(_objects_by_id[id]):
			release_id(id)
	_entries_after_sweep = _objects_by_id.size()


## The release signal's own arguments come first; the bound id is last.
func _release_from_signal(...args: Array) -> void:
	release_id(args[-1])
