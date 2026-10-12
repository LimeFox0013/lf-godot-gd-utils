## Game-wide named events: any script can send one or listen for one, with no node to set up.
##
## A process-wide pub/sub ("publish/subscribe") bus: static `emit_sync`/`on`/`once`/`off`
## forwarding to one shared `LFEventEmitter`, so it works without an autoload — e.g. a
## status panel listens for "item-added" that any script emits. Call it on the class; an
## instance has nothing of its own. To await async handlers, use
## `await LFEventBus.emitter.emit(...)`. Everything registered stays until removed or
## `clear()`; a registered method does not keep its object alive, and once that object is
## freed its registration does nothing when emitted.
class_name LFEventBus

## Fewest owners the bus holds before it first looks for freed ones to forget.
const _OWNER_SWEEP_MIN := 64

static var _log := LFLogger.new()
## Instance id of an owner -> Array of `[event, callback]` pairs it registered through
## `on`/`once`, for `off_owner`.
static var _owned := {}
## How many owners `_owned` may hold before the next sweep of freed ones.
static var _sweep_at := _OWNER_SWEEP_MIN

static var _emitter := LFEventEmitter.new()
## The shared emitter behind the bus, for its other methods (`emit`, `has_handlers`,
## `handler_count`). Read-only: assigning reports an error and changes nothing.
static var emitter: LFEventEmitter:
	get:
		return _emitter
	set(_value):
		_log.error("LFEventBus.emitter is read-only")


## Calls every handler of `event` with `args` right away, in registration order; an async
## handler is started, not awaited. An event with no handlers does nothing.
static func emit_sync(event: String, ...args: Array) -> void:
	_emitter.emit_sync_v(event, args)


## `emit_sync` with the arguments already in an array.
static func emit_sync_v(event: String, args: Array) -> void:
	_emitter.emit_sync_v(event, args)


## Registers `cb` as a handler of `event`; it is called with the emit's arguments. A
## callback registered twice is called twice.
static func on(event: String, cb: Callable) -> void:
	_emitter.on(event, cb)
	_remember(event, cb)


## Registers `cb` to run on the next emit of `event` only.
static func once(event: String, cb: Callable) -> void:
	_emitter.once(event, cb)
	_remember(event, cb)


## Removes the first registration of `cb` for `event`; does nothing when `cb` is not
## registered. An empty `Callable()` removes nothing and is reported as an error; use
## `clear_event(event)` to remove every handler of `event`.
static func off(event: String, cb: Callable) -> void:
	_emitter.off(event, cb)
	_forget(event, cb)


## Removes every handler of `event`.
static func clear_event(event: String) -> void:
	_emitter.clear_event(event)
	for owner_id: Variant in _owned.keys():
		var kept: Array = _owned[owner_id].filter(func(entry: Array) -> bool: return entry[0] != event)
		if kept.is_empty():
			_owned.erase(owner_id)
		else:
			_owned[owner_id] = kept


## Removes every handler of every event — call it between tests or when changing scenes.
static func clear() -> void:
	_emitter.clear()
	_owned.clear()


## Removes every handler `owner` registered through `LFEventBus.on`/`once`, on every
## event, and returns how many it removed. A handler belongs to the object its Callable
## is bound to (`Callable.get_object()`): a method `owner.method`, or a lambda written in
## one of `owner`'s methods that uses `self`, so a lambda you cannot name again for `off`
## is still removed. Call it in `_exit_tree()`. Not removed: a handler whose Callable has
## no object (a lambda written in a static function), and one registered straight on
## `LFEventBus.emitter`. A one-shot that already fired is not counted. Pass the object
## while it is alive: a freed one cannot be passed, and the bus forgets its record on a
## later sweep, leaving its handlers inert (they do nothing when emitted) until `clear()`.
static func off_owner(owner: Object) -> int:
	if owner == null:
		_log.error("LFEventBus.off_owner: no owner")
		return 0
	var entries: Variant = _owned.get(owner.get_instance_id())
	if entries == null:
		return 0
	_owned.erase(owner.get_instance_id())
	var removed := 0
	for entry: Array in entries:
		var before := _emitter.handler_count(entry[0])
		_emitter.off(entry[0], entry[1])
		removed += before - _emitter.handler_count(entry[0])
	return removed


# Notes `cb` under the object it is bound to, so `off_owner` can find it.
static func _remember(event: String, cb: Callable) -> void:
	var owner := cb.get_object()
	if owner == null:
		return
	var owner_id := owner.get_instance_id()
	if not _owned.has(owner_id):
		if _owned.size() >= _sweep_at:
			_forget_freed_owners()
		_owned[owner_id] = []
	_owned[owner_id].append([event, cb])


# Drops the first note of `cb` under `event` (the registration `off` removed).
static func _forget(event: String, cb: Callable) -> void:
	var owner := cb.get_object()
	if owner == null:
		return
	var entries: Variant = _owned.get(owner.get_instance_id())
	if entries == null:
		return
	for index in entries.size():
		if entries[index][0] == event and entries[index][1] == cb:
			entries.remove_at(index)
			break
	if entries.is_empty():
		_owned.erase(owner.get_instance_id())


# Forgets the notes of owners that were freed, and sets the next sweep at twice what is left.
static func _forget_freed_owners() -> void:
	for owner_id: Variant in _owned.keys():
		if not is_instance_id_valid(owner_id):
			_owned.erase(owner_id)
	_sweep_at = maxi(_OWNER_SWEEP_MIN, _owned.size() * 2)
