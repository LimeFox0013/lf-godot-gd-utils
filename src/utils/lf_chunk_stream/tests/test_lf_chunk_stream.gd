extends GutTest

var _spawned: Array[int] = []
var _despawned: Array[int] = []
var _stream: LFChunkStream


func before_each():
	_spawned.clear()
	_despawned.clear()
	_stream = LFChunkStream.new(_spawn, _despawn, 2, 1)


func _spawn(index: int) -> Variant:
	_spawned.append(index)
	return "chunk_%d" % index


func _despawn(index: int, _chunk: Variant) -> void:
	_despawned.append(index)


func test_nothing_is_built_before_the_first_focus():
	assert_eq(_stream.count(), 0)
	assert_null(_stream.focused_index())
	assert_eq(_spawned, [] as Array[int])


func test_focus_builds_the_window_lowest_first():
	_stream.min_index = 0
	_stream.focus(0)
	assert_eq(_spawned, [0, 1, 2] as Array[int], "no chunk behind index 0")
	assert_eq(_stream.indices(), [0, 1, 2] as Array[int])
	assert_eq(_stream.focused_index(), 0)


func test_moving_forward_builds_ahead_and_removes_behind():
	_stream.focus(5)
	assert_eq(_stream.indices(), [4, 5, 6, 7] as Array[int])
	_spawned.clear()
	_stream.focus(7)
	assert_eq(_despawned, [4, 5] as Array[int], "the window is now 6 to 9")
	assert_eq(_spawned, [8, 9] as Array[int])
	assert_eq(_stream.indices(), [6, 7, 8, 9] as Array[int])


func test_moving_back_rebuilds_what_was_removed():
	_stream.focus(10)
	_stream.focus(4)
	assert_eq(_stream.indices(), [3, 4, 5, 6] as Array[int])
	assert_true(_spawned.has(3))


func test_focusing_the_same_index_again_does_nothing():
	_stream.focus(3)
	_spawned.clear()
	_stream.focus(3)
	assert_eq(_spawned, [] as Array[int])
	assert_eq(_despawned, [] as Array[int])


func test_bounds_clamp_the_window_and_the_focus():
	_stream.min_index = 0
	_stream.max_index = 4
	_stream.focus(-3)
	assert_eq(_stream.focused_index(), 0)
	_stream.focus(99)
	assert_eq(_stream.focused_index(), 4)
	assert_eq(_stream.indices(), [3, 4] as Array[int])


func test_chunk_lookups():
	_stream.focus(0)
	assert_eq(_stream.chunk_at(1), "chunk_1")
	assert_null(_stream.chunk_at(50))
	assert_true(_stream.has_chunk(2))
	assert_false(_stream.has_chunk(3))
	assert_eq(_stream.index_of("chunk_2"), 2)
	assert_null(_stream.index_of("other"))


func test_a_wider_window_after_a_change_is_filled_on_the_next_focus():
	_stream.focus(0)
	_stream.ahead = 4
	_stream.behind = 0
	_stream.focus(0)
	assert_eq(_stream.indices(), [0, 1, 2, 3, 4] as Array[int])


func test_negative_sizes_become_zero():
	_stream.ahead = -5
	_stream.behind = -1
	_stream.focus(2)
	assert_eq(_stream.indices(), [2] as Array[int])


func test_signals_carry_the_index_and_the_chunk():
	var events: Array = []
	_stream.chunk_spawned.connect(func(i: int, c: Variant): events.append(["in", i, c]))
	_stream.chunk_despawned.connect(func(i: int, c: Variant): events.append(["out", i, c]))
	_stream.ahead = 1
	_stream.behind = 0
	_stream.focus(0)
	_stream.focus(5)
	assert_eq(events, [
		["in", 0, "chunk_0"], ["in", 1, "chunk_1"],
		["out", 0, "chunk_0"], ["out", 1, "chunk_1"],
		["in", 5, "chunk_5"], ["in", 6, "chunk_6"],
	])


func test_a_null_chunk_is_reported_and_stays_empty():
	var stream := LFChunkStream.new(func(i: int): return null if i == 1 else i, _despawn, 2, 0)
	stream.focus(0)
	assert_push_error('LFChunkStream')
	assert_eq(stream.indices(), [0, 2] as Array[int])


func test_an_invalid_spawn_callable_is_reported_and_builds_nothing():
	var stream := LFChunkStream.new(Callable(), _despawn, 1, 0)
	stream.focus(0)
	assert_push_error('LFChunkStream')
	assert_push_error('LFChunkStream')
	assert_eq(stream.count(), 0)


func test_clear_removes_everything_and_forgets_the_focus():
	_stream.focus(0)
	_despawned.clear()
	_stream.clear()
	assert_eq(_despawned, [-1, 0, 1, 2] as Array[int])
	assert_eq(_stream.count(), 0)
	assert_null(_stream.focused_index())


func test_a_focus_from_inside_spawn_waits_and_the_last_one_wins():
	var holder := []
	var nested := func(index: int) -> Variant:
		if index == 1:
			holder[0].focus(10)
		return index
	var stream := LFChunkStream.new(nested, _despawn, 1, 0)
	holder.append(stream)
	stream.focus(0)
	assert_eq(stream.focused_index(), 10)
	assert_eq(stream.indices(), [10, 11] as Array[int])


func test_an_inverted_range_is_reported_and_keeps_no_chunks():
	_stream.focus(5)
	_stream.min_index = 10
	_stream.max_index = 2
	_spawned.clear()
	_stream.focus(5)
	assert_push_error('LFChunkStream')
	assert_eq(_stream.count(), 0)
	assert_eq(_spawned, [] as Array[int])
	assert_null(_stream.focused_index())


func test_a_focus_from_inside_despawn_during_clear_is_dropped():
	var holder: Array[LFChunkStream] = []
	var refocus := func(_index: int, _chunk: Variant) -> void:
		holder[0].focus(20)
	var stream := LFChunkStream.new(_spawn, refocus, 1, 1)
	holder.append(stream)
	stream.focus(5)
	stream.clear()
	assert_eq(stream.count(), 0)
	assert_null(stream.focused_index())


func test_clear_from_inside_a_running_focus_is_ignored():
	var holder: Array[LFChunkStream] = []
	var clearer := func(_index: int, _chunk: Variant) -> void:
		holder[0].clear()
	var stream := LFChunkStream.new(_spawn, clearer, 1, 0)
	holder.append(stream)
	stream.focus(1)
	stream.focus(5)
	assert_push_error('LFChunkStream')
	assert_push_error('LFChunkStream')
	assert_eq(stream.indices(), [5, 6] as Array[int])
