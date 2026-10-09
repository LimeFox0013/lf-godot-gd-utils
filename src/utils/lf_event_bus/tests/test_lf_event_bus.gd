extends GutTest

## LFEventBus is process-wide: every test clears it afterwards.

func after_each():
	LFEventBus.clear()


func test_every_call_shares_one_emitter():
	assert_same(LFEventBus.emitter, LFEventBus.emitter)


func test_on_receives_emit_sync():
	var received := []
	LFEventBus.on("bus-on", func(payload): received.append(payload))
	LFEventBus.emit_sync("bus-on", "payload")
	assert_eq(received, ["payload"])


func test_emit_sync_v_takes_an_array():
	var received := []
	LFEventBus.on("bus-v", func(a, b): received.append([a, b]))
	LFEventBus.emit_sync_v("bus-v", [1, 2])
	assert_eq(received, [[1, 2]])


func test_off_stops_a_handler():
	var calls := [0]
	var handler := func(): calls[0] += 1
	LFEventBus.on("bus-off", handler)
	LFEventBus.emit_sync("bus-off")
	LFEventBus.off("bus-off", handler)
	LFEventBus.emit_sync("bus-off")
	assert_eq(calls[0], 1)


func test_once_fires_a_single_time():
	var calls := []
	LFEventBus.once("bus-once", func(payload): calls.append(payload))
	LFEventBus.emit_sync("bus-once", "first")
	LFEventBus.emit_sync("bus-once", "second")
	assert_eq(calls, ["first"])
	assert_false(LFEventBus.emitter.has_handlers("bus-once"))


func test_clearing_an_event_or_the_whole_bus():
	LFEventBus.on("a", func(): pass)
	LFEventBus.on("b", func(): pass)
	LFEventBus.clear_event("a")
	assert_false(LFEventBus.emitter.has_handlers("a"))
	LFEventBus.clear()
	assert_false(LFEventBus.emitter.has_handlers("b"))


func test_the_shared_emitter_cannot_be_replaced():
	var before := LFEventBus.emitter
	LFEventBus.emitter = LFEventEmitter.new()
	assert_push_error("read-only")
	assert_same(LFEventBus.emitter, before)


class Listener:
	extends RefCounted
	var count := 0
	func bump() -> void:
		count += 1


func test_a_registered_method_does_not_keep_its_object_alive():
	var listener := Listener.new()
	LFEventBus.on("bus-alive", listener.bump)
	var watch: WeakRef = weakref(listener)
	listener = null
	assert_null(watch.get_ref(), 'the registration holds no reference to the object')
	assert_eq(LFEventBus.emitter.handler_count("bus-alive"), 1, 'the registration itself stays until off() or clear()')


func test_a_handler_whose_node_was_freed_does_nothing_on_emit():
	var node := Node.new()
	LFEventBus.on("bus-freed", node.queue_free)
	node.free()
	LFEventBus.emit_sync("bus-freed")
	assert_eq(LFEventBus.emitter.handler_count("bus-freed"), 1)


func test_off_with_an_empty_callable_removes_nothing_and_clear_event_removes_all():
	var calls := [0]
	LFEventBus.on("bus-off-all", func(): calls[0] += 1)
	LFEventBus.on("bus-off-all", func(): calls[0] += 1)
	LFEventBus.off("bus-off-all", Callable())
	assert_push_error_count(1)
	LFEventBus.emit_sync("bus-off-all")
	assert_eq(calls[0], 2, 'an empty Callable removed nothing')
	LFEventBus.clear_event("bus-off-all")
	LFEventBus.emit_sync("bus-off-all")
	assert_eq(calls[0], 2)
	assert_false(LFEventBus.emitter.has_handlers("bus-off-all"))


func test_a_callback_registered_twice_is_called_twice():
	var calls := [0]
	var handler := func(): calls[0] += 1
	LFEventBus.on("bus-twice", handler)
	LFEventBus.on("bus-twice", handler)
	LFEventBus.emit_sync("bus-twice")
	assert_eq(calls[0], 2)


func test_an_async_handler_can_be_awaited_through_the_shared_emitter():
	LFEventBus.on("bus-async", func(value):
		await get_tree().process_frame
		return value * 2)
	assert_eq(await LFEventBus.emitter.emit("bus-async", 21), [42])
