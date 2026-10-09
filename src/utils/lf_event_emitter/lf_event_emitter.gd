## Named events that any code can listen to, owned by one object (a scene, a node, a menu).
##
## Pub/sub ("publish/subscribe"): `on`/`once`/`off` register handler functions per event
## name; `emit` calls an event's handlers and awaits them all (async ones included),
## `emit_sync` calls them right away.
##
## The handlers an emit calls are the ones registered when it started: one added during
## it waits for the next emit, and one removed or cleared before its turn is skipped. A
## one-shot handler runs at most once and is deregistered before it runs. Nothing the
## emitter stores refers back to it, so pending one-shots don't keep it alive (unless a
## handler you passed holds the emitter). A registered method doesn't keep its object
## alive; once that object is freed the registration does nothing when emitted. Not
## thread-safe.
class_name LFEventEmitter


static var _log := LFLogger.new()


class _Registration:
	var callback: Callable
	var once: bool
	var removed := false

	func _init(handler: Callable, one_shot: bool) -> void:
		callback = handler
		once = one_shot


## Event name -> Array of `_Registration`, in registration order. While an `emit_sync_v` runs,
## an `on` goes into a copy of the event's array and a removal only marks the registration;
## the outermost `emit_sync_v` drops the marked ones when it ends.
var _handlers := {}
## Event name -> how many registrations it has that are not removed.
var _live := {}
## How many `emit_sync_v` calls are running (nested ones included).
var _depth := 0
## How many `emit_sync_v` calls have started; tells a copy made during the current one
## (which no running emit walks) from an older array.
var _serial := 0
## Event name -> `_serial` when its array was last copied (or made) during an emit.
var _copied := {}
## Events whose array holds removed registrations, to drop when the emits end.
var _dirty := {}
## Whether `_copied` or `_dirty` holds anything for the end of the emits to clear.
var _pending := false


## Coroutine (use it with `await`). Calls every handler of `event` with `args` and awaits
## them all (handlers that themselves `await` included); resolves with their results in
## registration order (`[]` when the event has no handlers, `null` for a handler removed
## before its turn).
func emit(event: String, ...args: Array) -> Array:
	var registrations: Variant = _handlers.get(event)
	if registrations == null:
		return []
	var runs: Array = []
	for registration: _Registration in registrations:
		if not registration.removed:
			runs.append(_run.bind(event, registration, args))
	return await LFAwait.all(runs)


## Calls every handler of `event` with `args` right away, in registration order; an async
## handler is started, not awaited. An event with no handlers costs one lookup.
func emit_sync(event: String, ...args: Array) -> void:
	emit_sync_v(event, args)


## `emit_sync` with the arguments already in an array.
func emit_sync_v(event: String, args: Array) -> void:
	var registrations: Variant = _handlers.get(event)
	if registrations == null:
		return
	_depth += 1
	_serial += 1
	for registration: _Registration in registrations:
		if registration.removed:
			continue
		if registration.once:
			_remove(event, registration)
		registration.callback.callv(args)
	_depth -= 1
	if _depth == 0 and _pending:
		_settle()


## Registers `cb` as a handler of `event`; it is called with the emit's arguments. A
## callback registered twice is called twice.
func on(event: String, cb: Callable) -> void:
	_add(event, _Registration.new(cb, false))


## Registers `cb` to run on the next emit of `event` only.
func once(event: String, cb: Callable) -> void:
	_add(event, _Registration.new(cb, true))


## Removes the first registration of `cb` for `event` (by `on` or `once`); does nothing
## when `cb` is not registered. An empty `Callable()` removes nothing and is reported as
## an error through `LFLogger`; to remove every handler of `event`, call `clear_event`.
func off(event: String, cb: Callable) -> void:
	if cb.is_null():
		_log.error('LFEventEmitter.off: an empty Callable removes nothing (event "%s"); use clear_event(event) to remove every handler' % event)
		return
	var registrations: Variant = _handlers.get(event)
	if registrations == null:
		return
	for registration: _Registration in registrations:
		if not registration.removed and registration.callback == cb:
			_remove(event, registration)
			return


## Removes every handler of `event`.
func clear_event(event: String) -> void:
	var registrations: Variant = _handlers.get(event)
	if registrations == null:
		return
	for registration: _Registration in registrations:
		registration.removed = true
	_handlers.erase(event)
	_live.erase(event)


## Removes every handler of every event.
func clear() -> void:
	for event: Variant in _handlers.keys():
		clear_event(event)


## Whether `event` has at least one handler registered.
func has_handlers(event: String) -> bool:
	return _live.get(event, 0) > 0


## How many registrations `event` has (a callback registered twice counts twice; a fired
## or removed one no longer counts).
func handler_count(event: String) -> int:
	return _live.get(event, 0)


func _run(event: String, registration: _Registration, args: Array) -> Variant:
	if registration.removed:
		return null
	if registration.once:
		_remove(event, registration)
	return await registration.callback.callv(args)


func _add(event: String, registration: _Registration) -> void:
	var registrations: Variant = _handlers.get(event)
	if registrations == null:
		registrations = []
		_handlers[event] = registrations
		_live[event] = 0
		if _depth > 0:
			_copied[event] = _serial
			_pending = true
	elif _depth > 0 and _copied.get(event, -1) != _serial:
		# A running emit may walk this array: leave it be and carry on with a copy of the
		# live registrations, which no running emit walks.
		var copy: Array = []
		for kept: _Registration in registrations:
			if not kept.removed:
				copy.append(kept)
		registrations = copy
		_handlers[event] = copy
		_copied[event] = _serial
		_pending = true
	registrations.append(registration)
	_live[event] += 1


# Deregisters a live `registration` (a live one is always listed under its event): at once
# outside an emit, at the end of the emits during one.
func _remove(event: String, registration: _Registration) -> void:
	registration.removed = true
	_live[event] -= 1
	if _depth > 0:
		_dirty[event] = true
		_pending = true
	else:
		_compact(event)


# The emits have ended: drop the registrations they removed, forget their copies.
func _settle() -> void:
	_pending = false
	_copied.clear()
	for event: Variant in _dirty:
		if _handlers.has(event):
			_compact(event)
	_dirty.clear()


# Drops `event`'s removed registrations in place (no emit walks its array), and the event
# itself once none is left.
func _compact(event: String) -> void:
	if _live[event] == 0:
		_handlers.erase(event)
		_live.erase(event)
		return
	var registrations: Array = _handlers[event]
	var kept := 0
	for registration: _Registration in registrations:
		if not registration.removed:
			registrations[kept] = registration
			kept += 1
	registrations.resize(kept)
