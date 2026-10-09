extends GutTest

signal pinged

var _calls := 0


func _on_ping() -> void:
	_calls += 1


func test_every_connection_goes():
	pinged.connect(_on_ping)
	pinged.connect(func(): _calls += 1)

	LFUtils.disconnect_all(pinged)
	pinged.emit()

	assert_eq(pinged.get_connections().size(), 0)
	assert_eq(_calls, 0)


func test_only_one_objects_connections_go_when_it_is_named():
	var other := RefCounted.new()
	pinged.connect(_on_ping)
	pinged.connect(other.get_reference_count)

	LFUtils.disconnect_all(pinged, other)

	assert_eq(pinged.get_connections().size(), 1)
	assert_true(pinged.is_connected(_on_ping))
	LFUtils.disconnect_all(pinged)


func test_a_signal_without_connections_is_left_as_it_is():
	LFUtils.disconnect_all(pinged)
	LFUtils.disconnect_all(pinged, self)
	assert_eq(pinged.get_connections().size(), 0)
	assert_engine_error_count(0)
