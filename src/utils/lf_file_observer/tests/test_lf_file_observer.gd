extends GutTest

## Backed by real files in a scratch folder under user:// (an exported game can write
## there, unlike res://; see the lf-file test suite for why res:// is avoided here).

## The process id keeps two runs that share one user:// folder apart.
var scratch_dir := "user://lf_file_observer_test_%d" % OS.get_process_id()
var observed_file := scratch_dir + "/observed.txt"
var observed_json := scratch_dir + "/observed.json"
var blocker_path := scratch_dir + "/blocker"
## Owner write only: the file exists but cannot be read.
const WRITE_ONLY := 0x80
const OWNER_READ_WRITE := 0x180
## Owner read + execute: the directory can be listed but nothing renamed or created in it.
const READ_ONLY_DIR := 0x140
const OWNER_ALL := 0x1C0


func after_each():
	# Most tests never create the folder; listing a missing one would log an error.
	if !DirAccess.dir_exists_absolute(LFFile.to_absolute(scratch_dir)):
		return
	for file in DirAccess.get_files_at(LFFile.to_absolute(scratch_dir)):
		FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/" + file), OWNER_READ_WRITE)
	LFFile.remove_recursive(scratch_dir)


func _corrupt_backups() -> Array:
	var found := []
	for f in DirAccess.get_files_at(LFFile.to_absolute(scratch_dir)):
		if f.begins_with(observed_json.get_file() + ".corrupt-"):
			found.append(f)
	return found


## Permission bits mean nothing on Windows or to a superuser.
func _permissions_apply() -> bool:
	return OS.get_name() != "Windows" and OS.get_environment("USER") != "root"


func _make_unreadable(path: String, content: String) -> void:
	LFFile.save(path, content)
	FileAccess.set_unix_permissions(LFFile.to_absolute(path), WRITE_ONLY)


func _content_of(path: String) -> String:
	FileAccess.set_unix_permissions(LFFile.to_absolute(path), OWNER_READ_WRITE)
	return LFFile.load_file(path)


func _upper(text: String) -> String:
	return text.to_upper()


func _lower(text: String) -> String:
	return text.to_lower()


# ---- basics

func test_an_observer_is_a_plain_ref_counted_object():
	var observer: Variant = LFFileObserver.new(observed_file)
	assert_true(observer is RefCounted)
	assert_false(observer is Resource)


func test_reading_data_the_first_time_loads_it_from_the_backing_file():
	LFFile.save(observed_file, "pre-existing content")
	var observer = LFFileObserver.new(observed_file)
	assert_eq(observer.data, "pre-existing content")


func test_writing_persists_to_the_backing_file():
	var observer = LFFileObserver.new(observed_file)
	observer.data = "new content"
	assert_eq(LFFile.load_file(observed_file), "new content")


func test_every_write_emits_a_saved_signal():
	var observer = LFFileObserver.new(observed_file)
	watch_signals(observer)
	observer.data = "a"
	observer.data = "b"
	assert_signal_emit_count(observer, "saved", 2)


func test_custom_transforms_convert_between_file_text_and_data():
	LFFile.save(observed_file, "hello")
	var observer := LFFileObserver.new(observed_file, _upper, _lower)

	assert_eq(observer.data, "HELLO", "transform_out runs on load")
	observer.data = "BYE"
	assert_eq(LFFile.load_file(observed_file), "bye", "transform_in runs on save")


func test_reading_a_missing_backing_file_does_not_create_it():
	var observer = LFFileObserver.new(observed_file)
	assert_eq(observer.data, "")
	assert_false(FileAccess.file_exists(observed_file), "only a write creates the file")


func test_an_empty_cached_value_is_not_reloaded_from_disk_on_every_read():
	LFFile.save(observed_file, "")
	var observer = LFFileObserver.new(observed_file)
	assert_eq(observer.data, "")

	LFFile.save(observed_file, "written behind the observer's back")

	assert_eq(observer.data, "", "after the first load, reads come from the cached value")


func test_a_failed_save_leaves_the_value_unchanged_and_emits_nothing():
	LFFile.save(blocker_path, "a file, so nothing can be created under it")
	var observer = LFFileObserver.new(blocker_path + "/inside.txt")
	assert_eq(observer.data, "")
	watch_signals(observer)

	observer.data = "lost"

	assert_push_error("LFFile")
	assert_push_error("LFFileObserver")
	assert_eq(observer.data, "", "the in-memory value only changes once the file is written")
	assert_signal_not_emitted(observer, "saved")


func test_a_value_that_transform_in_does_not_turn_into_text_is_refused_before_the_file_is_touched():
	LFFile.save(observed_file, "keep")
	var observer := LFFileObserver.new(observed_file)
	watch_signals(observer)

	observer.data = 42

	assert_push_error("cannot store this value")
	assert_eq(LFFile.load_file(observed_file), "keep")
	assert_eq(observer.data, "keep")
	assert_signal_not_emitted(observer, "saved")


# ---- edit and reload

func test_edit_applies_a_change_to_a_copy_and_writes_once():
	var observer := LFJsonFileObserver.new(observed_json)
	observer.data = {"value_a": 10}
	watch_signals(observer)

	var ok := observer.edit(func(d: Dictionary) -> Dictionary:
		d["value_a"] = d["value_a"] + 5
		d["value_b"] = 1
		return d
	)

	assert_true(ok)
	assert_signal_emit_count(observer, "saved", 1, "one batch, one write")
	assert_eq(LFJsonFileObserver.new(observed_json).data, {"value_a": 15.0, "value_b": 1.0})


func test_edit_hands_the_change_a_copy_so_a_refused_result_changes_nothing():
	var observer := LFJsonFileObserver.new(observed_json)
	observer.data = {"value_a": 10}

	var ok := observer.edit(func(d: Dictionary):
		d["value_a"] = 999
		return null # not an object
	)

	assert_false(ok)
	assert_push_error("cannot store this value")
	assert_eq(observer.data, {"value_a": 10})
	assert_eq(LFJsonFileObserver.new(observed_json).data, {"value_a": 10.0})


func test_reload_picks_up_a_change_made_outside_the_observer():
	var observer := LFJsonFileObserver.new(observed_json)
	observer.data = {"a": 1}
	LFFile.save_json(observed_json, {"a": 2})

	assert_true(observer.reload())

	assert_eq(observer.data, {"a": 2.0})


func test_an_edit_after_another_writer_changed_the_file_keeps_that_change():
	var ours := LFJsonFileObserver.new(observed_json)
	ours.data = {"value_a": 10}
	var theirs := LFJsonFileObserver.new(observed_json)
	theirs.set_by_path("value_a", 60)

	ours.set_by_path("value_b", 1)

	assert_eq(LFJsonFileObserver.new(observed_json).data, {"value_a": 60.0, "value_b": 1.0})
	assert_eq(ours.get_by_path("value_a"), 60.0, "the editing instance now sees the other write too")


func test_replacing_data_after_another_writer_changed_the_file_is_refused():
	var ours := LFJsonFileObserver.new(observed_json)
	ours.data = {"value_a": 10}
	LFJsonFileObserver.new(observed_json).set_by_path("value_a", 60)
	watch_signals(ours)

	ours.data = {"value_a": 11}

	assert_push_error("changed on disk")
	assert_eq(LFFile.load_json(observed_json), {"value_a": 60.0}, "the other writer's change survives")
	assert_signal_not_emitted(ours, "saved")


# ---- unreadable and corrupt files

func test_an_unreadable_file_is_never_overwritten():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	_make_unreadable(observed_json, '{"value_a": 999}')
	var observer := LFJsonFileObserver.new(observed_json)

	assert_eq(observer.data, {}, "nothing could be read")
	assert_push_error("could not read")
	assert_false(observer.set_by_path("lastSeen", "today"))
	observer.data = {"lastSeen": "today"}

	assert_push_error("could not read")
	assert_push_error("could not read")
	assert_eq(_content_of(observed_json), '{"value_a": 999}')


func test_an_observer_writes_again_once_its_unreadable_file_becomes_readable():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	_make_unreadable(observed_json, '{"value_a": 999}')
	var observer := LFJsonFileObserver.new(observed_json)
	assert_eq(observer.data, {})
	assert_push_error("could not read")
	FileAccess.set_unix_permissions(LFFile.to_absolute(observed_json), OWNER_READ_WRITE)

	assert_true(observer.set_by_path("lastSeen", "today"))

	assert_eq(LFFile.load_json(observed_json), {"value_a": 999.0, "lastSeen": "today"})


func test_json_observer_round_trips_a_dictionary_through_the_backing_file():
	var observer = LFJsonFileObserver.new(observed_json)
	observer.data = {"count": 3, "label": "x"}

	var reopened = LFJsonFileObserver.new(observed_json)
	assert_eq(reopened.data, {"count": 3.0, "label": "x"})


func test_valid_json_that_is_not_an_object_loads_as_an_empty_dictionary():
	LFFile.save(observed_json, "[1]")
	var observer = LFJsonFileObserver.new(observed_json)

	assert_eq(observer.data, {}, "a JSON array is not an object and must not leak through as data")
	assert_eq(observer.get_by_path("a", "fallback"), "fallback")


func test_a_json_file_holding_only_whitespace_loads_as_empty_and_is_not_set_aside():
	LFFile.save(observed_json, "  \n\t ")
	var observer = LFJsonFileObserver.new(observed_json)

	assert_eq(observer.data, {})
	assert_eq(_corrupt_backups().size(), 0, "a blank file is an empty file, not a corrupt one")
	assert_true(observer.set_by_path("key_a", 1))
	assert_eq(LFFile.load_json(observed_json), {"key_a": 1.0})


func test_a_corrupt_json_file_is_set_aside_before_starting_fresh():
	LFFile.save(observed_json, '{"key_a": 12, broken')
	var observer = LFJsonFileObserver.new(observed_json)

	assert_eq(observer.data, {})
	assert_engine_error_count(0, "parsing is quiet")
	var backups := _corrupt_backups()
	assert_eq(backups.size(), 1, "the corrupt content is kept beside the file")
	if backups.size() == 1:
		assert_eq(LFFile.load_file(scratch_dir + "/" + backups[0]), '{"key_a": 12, broken')

	observer.data = {"key_a": 0}
	assert_eq(_corrupt_backups().size(), 1, "the backup survives the fresh write")


func test_a_corrupt_file_is_set_aside_once_however_many_observers_open_it():
	LFFile.save(observed_json, '{"key_a": 12, broken')

	for i in 3:
		assert_eq(LFJsonFileObserver.new(observed_json).data, {})

	assert_eq(_corrupt_backups().size(), 1)
	assert_false(FileAccess.file_exists(observed_json), "the corrupt file was moved aside, not copied")


func test_a_json_file_of_control_bytes_is_set_aside_not_read_as_empty():
	var contents := {
		"zero_bytes": PackedByteArray([0, 0, 0, 0]),
		"control_bytes": PackedByteArray([1, 2, 3]),
		"zero_then_json": PackedByteArray([0]) + '{"a": 1}'.to_utf8_buffer(),
	}
	for label in contents:
		LFFile.save_bytes(observed_json, contents[label])
		var observer = LFJsonFileObserver.new(observed_json)

		assert_eq(observer.data, {}, label)
		assert_eq(_corrupt_backups().size(), 1, "%s: the file was set aside" % label)
		assert_false(FileAccess.file_exists(observed_json), label)
		assert_true(observer.set_by_path("key_a", 1), label)
		assert_eq(FileAccess.get_file_as_bytes(scratch_dir + "/" + _corrupt_backups()[0]), contents[label], "%s: its bytes are kept" % label)
		for f in _corrupt_backups():
			LFFile.remove(scratch_dir + "/" + f)
		LFFile.remove(observed_json)


func test_a_json_file_of_control_bytes_that_cannot_be_moved_aside_blocks_writes():
	if !_permissions_apply():
		pending("permission bits do not apply here")
		return
	LFFile.save_bytes(observed_json, PackedByteArray([0, 0]))
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir), READ_ONLY_DIR)
	var observer := LFJsonFileObserver.new(observed_json)

	assert_eq(observer.data, {})
	assert_false(observer.set_by_path("key_a", 1), "the unknown content is never overwritten")

	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir), OWNER_ALL)
	assert_push_error("LFFileObserver")
	assert_eq(_corrupt_backups().size(), 0)
	assert_eq(FileAccess.get_file_as_bytes(observed_json), PackedByteArray([0, 0]))


# ---- dotted paths

func test_json_observer_set_by_path_updates_a_nested_value_and_persists():
	var observer = LFJsonFileObserver.new(observed_json)
	observer.data = {"a": {"b": 1}}
	assert_true(observer.set_by_path("a.b", 2))

	assert_eq(observer.data.a.b, 2)
	var reopened = LFJsonFileObserver.new(observed_json)
	assert_eq(reopened.data.a.b, 2.0, "a reload brings JSON numbers back as floats")


func test_json_observer_get_by_path_returns_a_present_falsy_value_not_the_fallback():
	var observer = LFJsonFileObserver.new(observed_json)
	observer.data = {"count": 0, "enabled": false}

	assert_eq(observer.get_by_path("count", "fallback"), 0, "the in-memory value keeps its int until a reload")
	assert_eq(observer.get_by_path("enabled", "fallback"), false)


func test_json_observer_get_by_path_returns_the_fallback_for_a_missing_key():
	var observer = LFJsonFileObserver.new(observed_json)
	observer.data = {"a": 1}
	assert_eq(observer.get_by_path("missing", "fallback"), "fallback")


func test_get_by_path_returns_a_copy_the_caller_can_change_freely():
	var observer := LFJsonFileObserver.new(observed_json)
	observer.data = {"layer_a": {"a": 1}}

	var layer: Dictionary = observer.get_by_path("layer_a")
	layer["a"] = 99

	assert_eq(observer.get_by_path("layer_a"), {"a": 1})


func test_json_observer_erase_by_path_removes_a_nested_key_and_persists():
	var observer = LFJsonFileObserver.new(observed_json)
	observer.data = {"a": {"b": 1, "c": 2}}
	observer.erase_by_path("a.b")

	assert_false(observer.data.a.has("b"))
	var reopened = LFJsonFileObserver.new(observed_json)
	assert_false(reopened.data.a.has("b"))


func test_erasing_a_missing_key_keeps_the_rest():
	var observer := LFJsonFileObserver.new(observed_json)
	observer.data = {"a": 1}

	assert_true(observer.erase_by_path("nope.deeper"))

	assert_eq(LFFile.load_json(observed_json), {"a": 1.0})


func test_a_corrupt_file_that_cannot_be_moved_aside_is_never_overwritten():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(observed_json, '{"key_a": 12, broken')
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir), READ_ONLY_DIR)
	var observer := LFJsonFileObserver.new(observed_json)

	assert_eq(observer.data, {})
	observer.data = {"key_a": 0}

	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir), OWNER_ALL)
	assert_push_error("LFFileObserver")
	assert_eq(_corrupt_backups().size(), 0, "the rename failed, so no backup exists")
	assert_eq(LFFile.load_file(observed_json), '{"key_a": 12, broken', "the corrupt content is untouched")


# ---- more edges

func test_assigning_an_unchanged_value_still_writes_and_emits_saved():
	var observer := LFFileObserver.new(observed_file)
	observer.data = "same"
	watch_signals(observer)

	observer.data = "same"

	assert_signal_emit_count(observer, "saved", 1)


func test_edit_on_an_observer_not_yet_read_starts_from_the_file():
	LFFile.save_json(observed_json, {"kept": 1, "value_a": 2})
	var observer := LFJsonFileObserver.new(observed_json)

	assert_true(observer.edit(func(d: Dictionary) -> Dictionary:
		d["value_a"] += 1
		return d
	))

	assert_eq(LFFile.load_json(observed_json), {"kept": 1.0, "value_a": 3.0})


func test_edit_works_on_a_plain_text_observer():
	LFFile.save(observed_file, "line one")
	var observer := LFFileObserver.new(observed_file)

	assert_true(observer.edit(func(text: String) -> String: return text + "\nline two"))

	assert_eq(LFFile.load_file(observed_file), "line one\nline two")
	assert_eq(observer.data, "line one\nline two")


func test_edit_hands_an_array_value_over_as_a_copy():
	var observer := LFFileObserver.new(observed_file, func(text: String) -> Array: return Array(text.split(",", false)),
			func(items: Variant) -> Variant: return ",".join(PackedStringArray(items)) if items is Array else null)
	observer.data = ["a"]
	var seen: Array = []

	observer.edit(func(items: Array) -> Variant:
		seen.append(items)
		items.append("b")
		return 0 # not text: refused
	)

	assert_push_error("cannot store this value")
	assert_eq(observer.data, ["a"], "the change saw a copy, not the cached value")
	assert_eq(seen.size(), 1)


func test_a_file_deleted_behind_the_observer_is_edited_from_empty():
	var observer := LFJsonFileObserver.new(observed_json)
	observer.data = {"old": 1}
	DirAccess.remove_absolute(LFFile.to_absolute(observed_json))

	assert_true(observer.set_by_path("new", 2))

	assert_eq(LFFile.load_json(observed_json), {"new": 2.0}, "the deleted content does not come back")


func test_reload_reports_an_unreadable_file():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(observed_file, "before")
	var observer := LFFileObserver.new(observed_file)
	assert_eq(observer.data, "before")
	_make_unreadable(observed_file, "after")

	assert_false(observer.reload())

	assert_push_error("could not read")
	assert_eq(observer.data, "", "reads as an empty file")
	FileAccess.set_unix_permissions(LFFile.to_absolute(observed_file), OWNER_READ_WRITE)
	assert_true(observer.reload())
	assert_eq(observer.data, "after")


func test_replacing_data_after_an_unreadable_file_becomes_readable_is_refused():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	_make_unreadable(observed_file, "theirs")
	var observer := LFFileObserver.new(observed_file)
	assert_eq(observer.data, "")
	assert_push_error("could not read")
	FileAccess.set_unix_permissions(LFFile.to_absolute(observed_file), OWNER_READ_WRITE)

	observer.data = "ours"

	assert_push_error("changed on disk")
	assert_eq(LFFile.load_file(observed_file), "theirs", "a content never read is not replaced blindly")
