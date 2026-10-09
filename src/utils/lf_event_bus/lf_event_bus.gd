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

static var _log := LFLogger.new()


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


## Registers `cb` to run on the next emit of `event` only.
static func once(event: String, cb: Callable) -> void:
	_emitter.once(event, cb)


## Removes the first registration of `cb` for `event`; does nothing when `cb` is not
## registered. An empty `Callable()` removes nothing and is reported as an error; use
## `clear_event(event)` to remove every handler of `event`.
static func off(event: String, cb: Callable) -> void:
	_emitter.off(event, cb)


## Removes every handler of `event`.
static func clear_event(event: String) -> void:
	_emitter.clear_event(event)


## Removes every handler of every event — call it between tests or when changing scenes.
static func clear() -> void:
	_emitter.clear()
