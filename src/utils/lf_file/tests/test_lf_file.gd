extends GutTest

## Every write targets a scratch folder under user://: res:// is the project's own source
## tree, and writing there would leave files in it.

## The process id keeps two runs that share one user:// folder apart.
var scratch_dir := "user://lf_file_test_%d" % OS.get_process_id()
## Set by a test that writes below user://<user dir name>/, which after_each then removes.
var _clamped_root_claimed := false
## Owner write only: the file exists but cannot be read.
const WRITE_ONLY := 0x80
## Owner read + execute: the directory can be listed but nothing created in it.
const READ_ONLY_DIR := 0x140
## Owner read + write + execute.
const OWNER_ALL := 0x1C0
## Owner read + write.
const OWNER_READ_WRITE := 0x180
## Size of the file the max_bytes test reads, in bytes.
const BIG_FILE_BYTES := 100
## A max_bytes below that size.
const SMALLER_CAP := 50


func after_each():
	LFFile._system_name = ""
	if _clamped_root_claimed:
		LFFile.remove_recursive("user://" + _user_dir_name())
		_clamped_root_claimed = false
	_restore_permissions(scratch_dir)
	LFFile.remove_recursive(scratch_dir)


## Gives the owner full access again to everything under `path`, so teardown can remove it.
func _restore_permissions(path: String) -> void:
	var absolute := LFFile.to_absolute(path)
	if !DirAccess.dir_exists_absolute(absolute):
		return
	FileAccess.set_unix_permissions(absolute, OWNER_ALL)
	for file in DirAccess.get_files_at(absolute):
		FileAccess.set_unix_permissions(absolute + "/" + file, OWNER_READ_WRITE)
	for dir in DirAccess.get_directories_at(absolute):
		var child := absolute + "/" + dir
		var parent := DirAccess.open(absolute)
		if parent != null and !parent.is_link(child):
			_restore_permissions(child)


## Permission bits mean nothing on Windows or to a superuser.
func _permissions_apply() -> bool:
	return OS.get_name() != "Windows" and OS.get_environment("USER") != "root"


## Creates a symbolic link at `link` pointing to `target`; false where links can't be made.
func _link(target: String, link: String) -> bool:
	var dir := DirAccess.open(LFFile.to_absolute(link).get_base_dir())
	return dir != null and dir.create_link(LFFile.to_absolute(target), LFFile.to_absolute(link)) == OK


# ---- paths

func test_res_and_plain_relative_paths_resolve_to_the_same_absolute_path():
	assert_eq(LFFile.to_absolute("foo.txt"), LFFile.to_absolute("res://foo.txt"))


func test_an_already_absolute_path_resolves_to_itself():
	var absolute = LFFile.to_absolute("res://foo.txt")
	assert_eq(LFFile.to_absolute(absolute), absolute)


func test_user_scheme_path_matches_godots_own_globalize_path():
	assert_eq(
		LFFile.to_absolute("user://foo.txt"),
		ProjectSettings.globalize_path("user://foo.txt"),
	)


func test_to_absolute_normalizes_backslashes_in_a_windows_drive_path():
	assert_eq(LFFile.to_absolute("C:\\Users\\me\\file.txt"), "C:/Users/me/file.txt")


func test_to_absolute_keeps_a_forward_slash_drive_path_and_simplifies_it():
	assert_eq(LFFile.to_absolute("d:/data/./dir_a/../item_a.json"), "d:/data/item_a.json")


func test_to_absolute_normalizes_backslashes_in_a_relative_path():
	assert_eq(LFFile.to_absolute("sub\\dir\\foo.txt"), LFFile.to_absolute("res://sub/dir/foo.txt"))


func test_to_absolute_does_not_treat_a_drive_letter_without_a_slash_as_absolute():
	# 'C:foo' is not 'C:/...', so it falls through to the res://-relative branch.
	assert_eq(LFFile.to_absolute("C:foo"), LFFile.to_absolute("res://C:foo"))


func test_a_readable_path_keeps_godot_schemes_and_makes_relative_paths_res_relative():
	assert_eq(LFFile.readable_path("res://a/../b.txt"), "res://b.txt")
	assert_eq(LFFile.readable_path("user://x/y.json"), "user://x/y.json")
	assert_eq(LFFile.readable_path("data/z.json"), "res://data/z.json")
	assert_eq(LFFile.readable_path("/tmp/abs.txt"), "/tmp/abs.txt")


func test_dot_dot_never_climbs_above_a_scheme_root():
	assert_eq(LFFile.to_absolute("user://../../x.txt"), LFFile.to_absolute("user://x.txt"))
	assert_eq(LFFile.to_absolute("res://a/../../x.txt"), LFFile.to_absolute("res://x.txt"))
	assert_eq(LFFile.to_absolute("../x.txt"), LFFile.to_absolute("res://x.txt"))
	assert_eq(LFFile.readable_path("res://a/../../x.txt"), "res://x.txt")
	assert_eq(LFFile.readable_path("user://../x.txt"), "user://x.txt")


func test_a_save_and_a_load_of_the_same_dot_dot_path_touch_the_same_file():
	var path := scratch_dir + "/../../" + scratch_dir.get_file() + "/escape.txt"
	LFFile.save(path, "same file")
	assert_eq(LFFile.load_file(path), "same file")
	assert_eq(LFFile.load_file(scratch_dir + "/escape.txt"), "same file")


## The user:// folder's own name: an escape that climbs out of user:// and back in through
## it lands in the scratch folder, while the clamped path lands under user://<this name>.
func _user_dir_name() -> String:
	return ProjectSettings.globalize_path("user://").simplify_path().get_file()


## Spellings of `user://<scratch>/<rel>` that climb above user:// and come back down
## through its own folder: an embedded scheme, backslashes, repeated slashes, a drive
## letter. Without clamping each resolves to the scratch folder; clamped, each stays
## under user://<user dir name>/.
func _escapes(rel: String) -> Array[String]:
	var back := _user_dir_name() + "/" + scratch_dir.get_file() + "/" + rel
	var s := scratch_dir.get_file()
	return [
		"user://res://../../" + back,
		"user://user://../../" + back,
		("user://res://../../" + back).replace("/", "\\"),
		"user:////res:////..//..//" + back,
		"user://" + s + "/res://../../../" + back,
		"user://C:/../../" + back,
		"user://C:/../../../" + back,
	]


## Where every clamped escape of `rel` lands: below user://, outside the scratch folder.
func _clamped(rel: String) -> String:
	return "user://" + _user_dir_name() + "/" + scratch_dir.get_file() + "/" + rel


## Claims user://<user dir name>/ for one test, so after_each removes it; false when it
## already exists and is not this test's to remove.
func _claim_clamped_root() -> bool:
	if LFFile.path_exists("user://" + _user_dir_name()):
		return false
	_clamped_root_claimed = true
	return true


func test_no_spelling_of_a_scheme_path_resolves_outside_its_root():
	var user_root := ProjectSettings.globalize_path("user://").simplify_path() + "/"
	var res_root := ProjectSettings.globalize_path("res://").simplify_path() + "/"
	for escape in _escapes("x.txt"):
		var absolute := LFFile.to_absolute(escape)
		assert_true(absolute.begins_with(user_root), "%s -> %s" % [escape, absolute])
		assert_eq(absolute, LFFile.to_absolute(_clamped("x.txt")), escape)
		assert_true(LFFile.readable_path(escape).begins_with("user://"), escape)
	for escape in [
		"res://user://../../../../../../x.txt", "res://C:/../../../x.txt",
		"res:\\..\\..\\x.txt", "res:///../../x.txt", "user://%2e%2e/%2e%2e/x.txt",
		"res://a/.../.../x.txt", "res://.. /.. /x.txt", "C:../../x.txt",
	]:
		var absolute := LFFile.to_absolute(escape)
		var root := user_root if escape.begins_with("user") else res_root
		assert_true(absolute.begins_with(root), "%s -> %s" % [escape, absolute])
		assert_false(LFFile.readable_path(escape).contains(".."), escape)


func test_save_ensure_dir_and_copy_through_an_escape_stay_inside_user():
	if !_claim_clamped_root():
		pending("user:// already holds a folder named like itself")
		return
	for escape in _escapes("out/x.txt"):
		assert_true(LFFile.save(escape, "kept in"), escape)
		assert_eq(LFFile.ensure_dir(_escapes("made/")[0]), OK)
	LFFile.save(scratch_dir + "/src.txt", "copied")
	assert_true(LFFile.copy_to_dir(scratch_dir + "/src.txt", _escapes("copies/")[0]))

	assert_false(LFFile.path_exists(scratch_dir + "/out"), "nothing written where the escape led")
	assert_false(LFFile.path_exists(scratch_dir + "/made"))
	assert_false(LFFile.path_exists(scratch_dir + "/copies"))
	assert_eq(LFFile.load_file(_clamped("out/x.txt")), "kept in")
	assert_eq(LFFile.path_leads_to(_clamped("made")), LFFile.PathTarget.DIR)
	assert_eq(LFFile.load_file(_clamped("copies/src.txt")), "copied")


func test_remove_and_move_aside_through_an_escape_leave_files_outside_alone():
	if !_claim_clamped_root():
		pending("user:// already holds a folder named like itself")
		return
	LFFile.save(scratch_dir + "/victim.txt", "still here")
	LFFile.save(scratch_dir + "/tree/leaf.txt", "still here")
	for escape in _escapes("victim.txt"):
		assert_eq(LFFile.remove(escape), OK, escape)
		assert_eq(LFFile.move_aside(escape, "aside"), "", escape)
	for escape in _escapes("tree"):
		assert_eq(LFFile.remove_recursive(escape), OK, escape)

	assert_eq(LFFile.load_file(scratch_dir + "/victim.txt"), "still here")
	assert_eq(LFFile.load_file(scratch_dir + "/tree/leaf.txt"), "still here")
	assert_false(LFFile.path_exists("user://" + _user_dir_name()), "nothing created either")


func test_is_inside_accepts_the_root_and_paths_below_it_only():
	assert_true(LFFile.is_inside(scratch_dir, scratch_dir))
	assert_true(LFFile.is_inside(scratch_dir, scratch_dir + "/a/b.txt"))
	assert_true(LFFile.is_inside(scratch_dir + "/", scratch_dir + "/a/../b.txt"))
	assert_false(LFFile.is_inside(scratch_dir, scratch_dir + "/../x.txt"))
	assert_false(LFFile.is_inside(scratch_dir, scratch_dir + "-sibling/x.txt"), "a shared prefix is not containment")
	assert_false(LFFile.is_inside(scratch_dir, "/etc/passwd"))


func test_is_inside_refuses_an_empty_root():
	assert_false(LFFile.is_inside("", "/etc/passwd"))
	assert_false(LFFile.is_inside("  ", LFFile.to_absolute(scratch_dir)))


func test_is_inside_refuses_a_path_that_goes_through_a_link():
	LFFile.ensure_dir(scratch_dir + "/root/")
	LFFile.ensure_dir(scratch_dir + "/outside/")
	if !_link(scratch_dir + "/outside", scratch_dir + "/root/link"):
		pending("symbolic links can't be created here")
		return

	assert_false(LFFile.is_inside(scratch_dir + "/root", scratch_dir + "/root/link/x.txt"))
	assert_false(LFFile.is_inside(scratch_dir + "/root", scratch_dir + "/root/link"))
	assert_true(LFFile.is_inside(scratch_dir + "/root", scratch_dir + "/root/plain/x.txt"))


func test_join_inside_joins_a_contained_name_and_refuses_an_escaping_one():
	var root := LFFile.to_absolute(scratch_dir)
	assert_eq(LFFile.join_inside(scratch_dir, "a/b.txt"), root + "/a/b.txt")
	assert_eq(LFFile.join_inside(scratch_dir, "/abs.txt"), root + "/abs.txt", "a leading slash stays inside")
	assert_eq(LFFile.join_inside(scratch_dir, "a\\..\\b.txt"), root + "/b.txt")
	assert_eq(LFFile.join_inside(scratch_dir, "../x.txt"), "")
	assert_eq(LFFile.join_inside(scratch_dir, "a/../../x.txt"), "")
	assert_eq(LFFile.join_inside("", "etc/passwd"), "", "an empty root contains nothing")


func test_join_inside_portable_only_refuses_names_windows_reserves_or_alters():
	var root := LFFile.to_absolute(scratch_dir)
	for name in ["a/b:c.txt", "C:/x.txt", "file.txt:stream", "CON", "con.txt", "a/Nul.tar.gz", "COM1",
			"lpt9.log", "AUX /x", "dir./x.txt", "x.txt.", "x.txt ", "a /b"]:
		assert_eq(LFFile.join_inside(scratch_dir, name, true), "", name)
	for name in ["CONFIG.txt", "com10.txt", "console/x", "a.b/c", ".hidden", "LPT.txt"]:
		assert_eq(LFFile.join_inside(scratch_dir, name, true), root + "/" + name, name)


## Names Linux and macOS create without trouble (a log named after the time, a file
## ending in a dot) are not refused by default there: only the zip extractor asks for the
## Windows-portable check.
func test_join_inside_by_default_keeps_names_legal_on_linux_and_macos():
	var root := LFFile.to_absolute(scratch_dir)
	for system in ["Linux", "macOS"]:
		LFFile._system_name = system
		for name in ["logs/12:30.log", "notes.", "CON", "a /b", "x.txt "]:
			assert_eq(LFFile.join_inside(scratch_dir, name), root + "/" + name, "%s on %s" % [name, system])
	assert_eq(LFFile.join_inside(scratch_dir, "logs/../../x.txt"), "", "escaping is still refused")


## On Windows those names would open a device (CON), write an NTFS stream (a.txt:stream)
## or land on a different file (a trailing dot or space is dropped), so they are refused
## without asking; portable names still join.
func test_join_inside_on_windows_refuses_names_windows_cannot_hold_by_default():
	var root := LFFile.to_absolute(scratch_dir)
	LFFile._system_name = "Windows"
	for name in ["CON", "logs/con.txt", "a.txt:stream", "logs/12:30.log", "notes.", "x.txt ", "a /b"]:
		assert_eq(LFFile.join_inside(scratch_dir, name), "", name)
	assert_eq(LFFile.join_inside(scratch_dir, "logs/save.json"), root + "/logs/save.json")
	assert_eq(LFFile.join_inside(scratch_dir, "CONFIG.txt"), root + "/CONFIG.txt")


## The real platform decides when nothing overrides it.
func test_join_inside_applies_the_rule_of_the_system_it_runs_on():
	var refused := LFFile.join_inside(scratch_dir, "CON") == ""
	assert_eq(refused, OS.get_name() == "Windows")


func test_is_portable_name_checks_one_segment():
	assert_true(LFFile.is_portable_name("save.json"))
	assert_false(LFFile.is_portable_name(""))
	assert_false(LFFile.is_portable_name("prn"))
	assert_false(LFFile.is_portable_name("a:b"))
	assert_false(LFFile.is_portable_name("end."))


func test_move_aside_keeps_the_content_under_a_free_name():
	var path := scratch_dir + "/data.json"
	LFFile.save(path, "first")
	var aside := LFFile.move_aside(path, "corrupt")
	LFFile.save(path, "second")
	var again := LFFile.move_aside(path, "corrupt")

	assert_true(aside.begins_with(LFFile.to_absolute(path) + ".corrupt-"), aside)
	assert_ne(again, aside, "a taken name is not reused")
	assert_eq(LFFile.load_file(aside), "first")
	assert_eq(LFFile.load_file(again), "second")
	assert_false(FileAccess.file_exists(LFFile.to_absolute(path)))
	assert_eq(LFFile.move_aside(path, "corrupt"), "", "no file, nothing moved")
	assert_engine_error_count(0)


# ---- saving

func test_save_and_load_file_round_trips_content():
	assert_true(LFFile.save(scratch_dir + "/round-trip.txt", "hello world"))
	assert_eq(LFFile.load_file(scratch_dir + "/round-trip.txt"), "hello world")


func test_save_bytes_round_trips_binary_content():
	var bytes := PackedByteArray([0, 1, 2, 255, 0, 7])
	assert_true(LFFile.save_bytes(scratch_dir + "/blob.bin", bytes))
	assert_eq(FileAccess.get_file_as_bytes(LFFile.to_absolute(scratch_dir + "/blob.bin")), bytes)


func test_save_json_and_load_json_round_trips_a_dictionary():
	LFFile.save_json(scratch_dir + "/data.json", {"a": 1, "b": "two"})
	# JSON has one numeric type, so ints round-trip as floats — that's JSON's
	# contract, not LFFile's.
	assert_eq(LFFile.load_json(scratch_dir + "/data.json"), {"a": 1.0, "b": "two"})


func test_save_json_takes_any_json_value():
	assert_true(LFFile.save_json(scratch_dir + "/list.json", [1, "two"]))
	assert_eq(LFFile.load_json_value(scratch_dir + "/list.json"), [1.0, "two"])


func test_saving_to_a_path_that_does_not_yet_exist_creates_its_parent_directories():
	var nested_path = scratch_dir + "/nested/dir/file.txt"
	assert_false(LFFile.path_exists(scratch_dir + "/nested"))

	assert_true(LFFile.save(nested_path, "content"))

	assert_true(LFFile.path_exists(nested_path))
	assert_eq(LFFile.load_file(nested_path), "content")


func test_save_without_ensure_file_leaves_a_missing_file_missing():
	var path := scratch_dir + "/no-such-dir/x.txt"

	var ok = LFFile.save(path, "content", false)

	assert_false(ok)
	assert_false(FileAccess.file_exists(path), "ensure_file=false must never create the file")


func test_save_without_ensure_file_overwrites_an_existing_file():
	LFFile.save(scratch_dir + "/x.txt", "old")
	assert_true(LFFile.save(scratch_dir + "/x.txt", "new", false))
	assert_eq(LFFile.load_file(scratch_dir + "/x.txt"), "new")


func test_save_json_reports_success_and_failure():
	assert_true(LFFile.save_json(scratch_dir + "/ok.json", {"a": 1}))
	LFFile.save(scratch_dir + "/blocker", "a file, not a dir")
	assert_false(LFFile.save_json(scratch_dir + "/blocker/inside.json", {"a": 1}), "a path under a file cannot be written")
	assert_push_error("LFFile")


func test_a_save_replaces_the_file_whole_instead_of_rewriting_it_in_place():
	if OS.get_name() == "Windows":
		pending("an open file can't be replaced on Windows")
		return
	LFFile.save(scratch_dir + "/item_a.json", "old content")
	var reader := FileAccess.open(LFFile.to_absolute(scratch_dir + "/item_a.json"), FileAccess.READ)

	assert_true(LFFile.save(scratch_dir + "/item_a.json", "new content"))

	assert_eq(reader.get_as_text(), "old content", "a reader that opened the file earlier still sees one whole version")
	reader.close()
	assert_eq(LFFile.load_file(scratch_dir + "/item_a.json"), "new content")


func test_a_save_that_cannot_complete_leaves_the_previous_content_intact():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(scratch_dir + "/locked/item_a.json", "previous")
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/locked"), READ_ONLY_DIR)

	var ok := LFFile.save(scratch_dir + "/locked/item_a.json", "next")

	assert_false(ok, "the save reports that it did not happen")
	assert_push_error("LFFile")
	assert_eq(LFFile.load_file(scratch_dir + "/locked/item_a.json"), "previous")


func test_a_save_leaves_no_temporary_file_behind():
	LFFile.save(scratch_dir + "/clean/a.txt", "one")
	LFFile.save(scratch_dir + "/clean/a.txt", "two")
	assert_eq(Array(DirAccess.get_files_at(LFFile.to_absolute(scratch_dir + "/clean"))), ["a.txt"])


func test_a_save_works_for_a_file_name_near_the_longest_the_system_allows():
	var long_name := "n".repeat(240) + ".txt"
	var path := scratch_dir + "/long/" + long_name

	assert_true(LFFile.save(path, "one"), "the temporary name must not push a legal name past the limit")
	assert_true(LFFile.save(path, "two"))

	assert_eq(LFFile.load_file(path), "two")
	assert_eq(Array(DirAccess.get_files_at(LFFile.to_absolute(scratch_dir + "/long"))), [long_name])


func test_a_copy_works_for_a_file_name_near_the_longest_the_system_allows():
	var long_name := "n".repeat(240) + ".txt"
	LFFile.save(scratch_dir + "/src/" + long_name, "payload")

	assert_true(LFFile.copy_to_dir(scratch_dir + "/src/" + long_name, scratch_dir + "/dst"))

	assert_eq(LFFile.load_file(scratch_dir + "/dst/" + long_name), "payload")


func test_saving_to_a_path_ending_in_a_slash_is_refused_instead_of_making_a_file():
	assert_false(LFFile.save(scratch_dir + "/saves/", "x"))
	assert_push_error("LFFile")
	assert_false(LFFile.path_exists(scratch_dir + "/saves"))
	assert_false(LFFile.save_bytes(scratch_dir + "\\saves\\", PackedByteArray([1])))
	assert_push_error("LFFile")


func test_saving_over_a_directory_fails():
	LFFile.ensure_dir(scratch_dir + "/a-dir/")
	assert_false(LFFile.save(scratch_dir + "/a-dir", "x"))
	assert_push_error("LFFile")
	assert_eq(LFFile.path_leads_to(scratch_dir + "/a-dir"), LFFile.PathTarget.DIR)


func test_ensure_dir_creates_the_parent_directory_and_reports_ok():
	var file_path := scratch_dir + "/made/by/ensure/file.txt"

	assert_eq(LFFile.ensure_dir(file_path), OK)

	assert_eq(LFFile.path_leads_to(scratch_dir + "/made/by/ensure"), LFFile.PathTarget.DIR, "the parent directory exists")
	assert_false(LFFile.path_exists(file_path), "the file itself is not created")


func test_ensure_dir_with_a_trailing_slash_creates_that_directory_itself():
	LFFile.ensure_dir(scratch_dir + "/made/here/")

	assert_true(DirAccess.dir_exists_absolute(LFFile.to_absolute(scratch_dir + "/made/here")))


func test_ensure_dir_reports_an_error_when_a_file_is_in_the_way():
	LFFile.save(scratch_dir + "/blocker", "a file")
	assert_ne(LFFile.ensure_dir(scratch_dir + "/blocker/inner/file.txt"), OK)
	assert_engine_error("failed")


# ---- reading

func test_path_exists_is_false_for_a_path_never_created():
	assert_false(LFFile.path_exists(scratch_dir + "/never-created.txt"))


func test_path_leads_to_distinguishes_files_from_directories():
	LFFile.save(scratch_dir + "/a-file.txt", "x")
	assert_eq(LFFile.path_leads_to(LFFile.to_absolute(scratch_dir + "/a-file.txt")), LFFile.PathTarget.FILE)
	assert_eq(LFFile.path_leads_to(LFFile.to_absolute(scratch_dir)), LFFile.PathTarget.DIR)
	assert_eq(LFFile.path_leads_to(LFFile.to_absolute(scratch_dir + "/missing")), LFFile.PathTarget.MISSING)


func test_path_exists_sees_project_files_through_their_scheme():
	assert_eq(LFFile.path_leads_to("res://project.godot"), LFFile.PathTarget.FILE)
	assert_eq(LFFile.path_leads_to(_test_dir()), LFFile.PathTarget.DIR)
	assert_true(LFFile.path_exists("res://project.godot"))


func test_a_res_file_is_read_through_its_own_scheme():
	assert_string_contains(LFFile.load_file("res://project.godot", false), "config_version")


func test_read_text_tells_a_missing_file_from_one_it_read():
	LFFile.save(scratch_dir + "/here.txt", "text")

	var found := LFFile.read_text(scratch_dir + "/here.txt")
	var missing := LFFile.read_text(scratch_dir + "/gone.txt")

	assert_eq(found.error, OK)
	assert_eq(found.text, "text")
	assert_eq(missing.error, ERR_FILE_NOT_FOUND)
	assert_eq(missing.text, "")
	assert_engine_error_count(0, "a missing file is not an engine error")


func test_read_text_reports_an_existing_file_it_cannot_read():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(scratch_dir + "/secret.json", '{"key_a": 999}')
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/secret.json"), WRITE_ONLY)

	var read := LFFile.read_text(scratch_dir + "/secret.json")

	assert_eq(read.error, ERR_FILE_CANT_READ)
	assert_eq(read.text, "")


func test_load_file_reports_an_existing_file_it_cannot_read():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(scratch_dir + "/secret.txt", "hidden")
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/secret.txt"), WRITE_ONLY)

	assert_eq(LFFile.load_file(scratch_dir + "/secret.txt"), "")
	assert_push_error("could not read")


func test_read_text_refuses_a_file_larger_than_max_bytes():
	LFFile.save(scratch_dir + "/big.txt", "x".repeat(BIG_FILE_BYTES))

	var capped := LFFile.read_text(scratch_dir + "/big.txt", SMALLER_CAP)
	var enough := LFFile.read_text(scratch_dir + "/big.txt", BIG_FILE_BYTES)

	assert_eq(capped.error, ERR_OUT_OF_MEMORY)
	assert_eq(capped.text, "")
	assert_eq(enough.error, OK)
	assert_eq(enough.text.length(), BIG_FILE_BYTES)


func test_read_text_turns_invalid_utf8_into_replacement_characters_quietly():
	LFFile.save_bytes(scratch_dir + "/garbled.txt", PackedByteArray([0x61, 0xFF, 0x62]))

	var read := LFFile.read_text(scratch_dir + "/garbled.txt")

	assert_eq(read.error, OK)
	assert_eq(read.text, "a\uFFFDb")
	assert_engine_error_count(0, "a garbled file is not an engine error")


func test_read_text_of_a_directory_reports_no_file():
	LFFile.ensure_dir(scratch_dir + "/a-dir/")
	assert_eq(LFFile.read_text(scratch_dir + "/a-dir").error, ERR_FILE_NOT_FOUND)


func test_a_save_through_a_link_replaces_the_link_and_leaves_its_target_alone():
	LFFile.save(scratch_dir + "/real.txt", "original")
	if !_link(scratch_dir + "/real.txt", scratch_dir + "/alias.txt"):
		pending("symbolic links can't be created here")
		return

	assert_true(LFFile.save(scratch_dir + "/alias.txt", "new"))

	assert_eq(LFFile.load_file(scratch_dir + "/real.txt"), "original")
	assert_eq(LFFile.load_file(scratch_dir + "/alias.txt"), "new")
	var dir := DirAccess.open(LFFile.to_absolute(scratch_dir))
	assert_false(dir.is_link(LFFile.to_absolute(scratch_dir + "/alias.txt")), "the alias is now a plain file")


func test_load_json_of_an_empty_or_invalid_file_is_an_empty_dictionary():
	LFFile.save(scratch_dir + "/bad.json", "{ not json")

	assert_eq(LFFile.load_json(scratch_dir + "/empty.json"), {})
	assert_eq(LFFile.load_json(scratch_dir + "/bad.json"), {})


func test_load_json_value_returns_any_json_value_and_null_when_invalid():
	LFFile.save(scratch_dir + "/list.json", "[1, 2, 3]")
	LFFile.save(scratch_dir + "/bad-value.json", "{nope")
	assert_eq(LFFile.load_json_value(scratch_dir + "/list.json"), [1.0, 2.0, 3.0])
	assert_null(LFFile.load_json_value(scratch_dir + "/bad-value.json"))
	assert_eq(LFFile.load_json(scratch_dir + "/list.json"), {}, "load_json still only returns objects")


func test_reading_a_missing_file_by_default_creates_nothing_and_is_quiet():
	var missing := scratch_dir + "/never/written.json"

	assert_eq(LFFile.load_file(missing), "")
	assert_eq(LFFile.load_json(missing), {})
	assert_null(LFFile.load_json_value(missing))

	assert_false(LFFile.path_exists(missing), "a plain read must not create the file")
	assert_engine_error_count(0, "a missing file reads as empty without an engine error")


func test_reading_with_ensure_file_still_creates_the_missing_file():
	var missing := scratch_dir + "/ensured.txt"
	assert_eq(LFFile.load_file(missing, true), "")
	assert_true(LFFile.path_exists(missing))


func test_load_json_value_with_ensure_file_creates_an_empty_file_and_reads_null():
	var missing := scratch_dir + "/ensured.json"
	assert_null(LFFile.load_json_value(missing, true))
	assert_true(LFFile.path_exists(missing))
	assert_eq(LFFile.load_file(missing), "")


# ---- copying

func test_copy_to_dir_copies_the_file_into_the_destination_directory():
	LFFile.save(scratch_dir + "/source.txt", "copied content")
	var ok = LFFile.copy_to_dir(scratch_dir + "/source.txt", scratch_dir + "/dest")
	assert_true(ok)
	assert_eq(LFFile.load_file(scratch_dir + "/dest/source.txt"), "copied content")


func test_copy_to_dir_refuses_to_overwrite_when_overwrite_is_false():
	LFFile.save(scratch_dir + "/source.txt", "original")
	LFFile.copy_to_dir(scratch_dir + "/source.txt", scratch_dir + "/dest")
	LFFile.save(scratch_dir + "/source.txt", "changed")

	var ok = LFFile.copy_to_dir(scratch_dir + "/source.txt", scratch_dir + "/dest", false)
	assert_push_error("overwrite=false")

	assert_false(ok)
	assert_eq(LFFile.load_file(scratch_dir + "/dest/source.txt"), "original")


func test_copy_to_dir_with_overwrite_replaces_an_existing_file():
	LFFile.save(scratch_dir + "/source.txt", "original")
	LFFile.copy_to_dir(scratch_dir + "/source.txt", scratch_dir + "/dest")
	LFFile.save(scratch_dir + "/source.txt", "changed")

	var ok = LFFile.copy_to_dir(scratch_dir + "/source.txt", scratch_dir + "/dest", true)

	assert_true(ok, "overwrite=true succeeds over an existing file")
	assert_eq(LFFile.load_file(scratch_dir + "/dest/source.txt"), "changed", "the destination holds the new content")


func test_copying_a_file_into_its_own_directory_keeps_it():
	LFFile.save(scratch_dir + "/sub/a.txt", "keep me")

	assert_true(LFFile.copy_to_dir(scratch_dir + "/sub/a.txt", scratch_dir + "/sub/"))

	assert_eq(LFFile.load_file(scratch_dir + "/sub/a.txt"), "keep me")


func test_copying_a_file_into_another_spelling_of_its_directory_keeps_it():
	LFFile.save(scratch_dir + "/sub/b.txt", "keep me")
	var alias := scratch_dir + "/alias"
	if !_link(scratch_dir + "/sub", alias):
		pending("symbolic links can't be created here")
		return

	assert_true(LFFile.copy_to_dir(scratch_dir + "/sub/b.txt", alias), "a copy onto itself is a successful no-op")

	assert_eq(LFFile.load_file(scratch_dir + "/sub/b.txt"), "keep me", "the source survives")


func test_a_failed_copy_keeps_the_existing_destination():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(scratch_dir + "/dest/c.txt", "old destination")
	LFFile.save(scratch_dir + "/c.txt", "unreadable source")
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/c.txt"), WRITE_ONLY)

	var ok := LFFile.copy_to_dir(scratch_dir + "/c.txt", scratch_dir + "/dest")

	assert_false(ok)
	assert_push_error("copy_to_dir")
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/c.txt"), OWNER_READ_WRITE)
	assert_eq(LFFile.load_file(scratch_dir + "/dest/c.txt"), "old destination")
	assert_eq(Array(DirAccess.get_files_at(LFFile.to_absolute(scratch_dir + "/dest"))), ["c.txt"], "no temporary file is left behind")


# ---- removing

func test_remove_deletes_a_file_and_an_empty_directory():
	LFFile.save(scratch_dir + "/x.txt", "x")
	LFFile.ensure_dir(scratch_dir + "/empty/")

	assert_eq(LFFile.remove(scratch_dir + "/x.txt"), OK)
	assert_eq(LFFile.remove(scratch_dir + "/empty"), OK)

	assert_false(LFFile.path_exists(scratch_dir + "/x.txt"))
	assert_false(LFFile.path_exists(scratch_dir + "/empty"))


func test_removing_a_missing_path_is_ok_and_quiet():
	assert_eq(LFFile.remove(scratch_dir + "/never.txt"), OK)
	assert_eq(LFFile.remove_recursive(scratch_dir + "/never"), OK)
	assert_engine_error_count(0)


func test_remove_refuses_a_directory_that_is_not_empty():
	LFFile.save(scratch_dir + "/full/x.txt", "x")
	assert_ne(LFFile.remove(scratch_dir + "/full"), OK)
	assert_true(LFFile.path_exists(scratch_dir + "/full/x.txt"))


func test_remove_recursive_deletes_a_whole_tree_including_hidden_files():
	LFFile.save(scratch_dir + "/tree/a.txt", "a")
	LFFile.save(scratch_dir + "/tree/sub/deeper/b.txt", "b")
	LFFile.save(scratch_dir + "/tree/.hidden", "h")

	assert_eq(LFFile.remove_recursive(scratch_dir + "/tree"), OK)

	assert_false(LFFile.path_exists(scratch_dir + "/tree"))


func test_removing_refuses_an_empty_path():
	assert_eq(LFFile.remove(""), ERR_INVALID_PARAMETER)
	assert_eq(LFFile.remove_recursive(" "), ERR_INVALID_PARAMETER)
	assert_push_error("remove: refusing")
	assert_push_error("remove_recursive: refusing")
	assert_true(LFFile.path_exists("res://project.godot"))


func test_remove_recursive_removes_links_without_following_them():
	LFFile.save(scratch_dir + "/outside/keep.txt", "keep")
	LFFile.save(scratch_dir + "/tree/a.txt", "a")
	if !_link(scratch_dir + "/outside", scratch_dir + "/tree/dir-link"):
		pending("symbolic links can't be created here")
		return
	_link(scratch_dir + "/outside/keep.txt", scratch_dir + "/tree/file-link")

	assert_eq(LFFile.remove_recursive(scratch_dir + "/tree"), OK)

	assert_false(LFFile.path_exists(scratch_dir + "/tree"))
	assert_eq(LFFile.load_file(scratch_dir + "/outside/keep.txt"), "keep", "what a link points at is never touched")


func test_removing_a_link_to_a_directory_removes_only_the_link():
	LFFile.save(scratch_dir + "/outside/keep.txt", "keep")
	if !_link(scratch_dir + "/outside", scratch_dir + "/dir-link"):
		pending("symbolic links can't be created here")
		return

	assert_eq(LFFile.remove_recursive(scratch_dir + "/dir-link"), OK)

	assert_false(DirAccess.dir_exists_absolute(LFFile.to_absolute(scratch_dir + "/dir-link")))
	assert_eq(LFFile.load_file(scratch_dir + "/outside/keep.txt"), "keep")


func test_remove_recursive_stops_at_an_entry_it_cannot_remove_and_returns_its_error():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(scratch_dir + "/tree/locked/kept.txt", "kept")
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/tree/locked"), READ_ONLY_DIR)

	var err := LFFile.remove_recursive(scratch_dir + "/tree")

	assert_ne(err, OK, "the entry that could not be removed reports its error")
	assert_eq(LFFile.load_file(scratch_dir + "/tree/locked/kept.txt"), "kept")
	assert_eq(LFFile.path_leads_to(scratch_dir + "/tree"), LFFile.PathTarget.DIR, "the walk stopped before removing the root")


# ---- copy_to_dir failures

func test_copy_to_dir_refuses_a_missing_source():
	var ok := LFFile.copy_to_dir(scratch_dir + "/never.txt", scratch_dir + "/dest")

	assert_false(ok)
	assert_push_error("Source file does not exist")
	assert_false(LFFile.path_exists(scratch_dir + "/dest"), "nothing was created")


func test_copy_to_dir_refuses_an_unreadable_source():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(scratch_dir + "/secret.txt", "secret")
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/secret.txt"), WRITE_ONLY)

	var ok := LFFile.copy_to_dir(scratch_dir + "/secret.txt", scratch_dir + "/dest")

	assert_false(ok)
	assert_push_error("can't be read")
	assert_false(LFFile.path_exists(scratch_dir + "/dest/secret.txt"))


func test_copy_to_dir_refuses_a_destination_that_is_a_file():
	LFFile.save(scratch_dir + "/a.txt", "a")
	LFFile.save(scratch_dir + "/not-a-dir", "file")

	var ok := LFFile.copy_to_dir(scratch_dir + "/a.txt", scratch_dir + "/not-a-dir")

	assert_false(ok)
	assert_push_error("Destination is a file")
	assert_eq(LFFile.load_file(scratch_dir + "/not-a-dir"), "file", "the file in the way is untouched")


## This test file's folder (a res:// path), wherever the library is installed.
func _test_dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir()


# ---- further edges

func test_an_empty_path_resolves_to_the_project_root():
	assert_eq(LFFile.readable_path(""), "res://")
	assert_eq(LFFile.readable_path("   "), "res://")
	assert_eq(LFFile.to_absolute(""), ProjectSettings.globalize_path("res://").simplify_path())


func test_a_readable_path_keeps_a_windows_drive_path_absolute():
	assert_eq(LFFile.readable_path("C:\\games\\save.json"), "C:/games/save.json")
	assert_eq(LFFile.readable_path("1:/x"), "res://1:/x", "a digit is not a drive letter")


func test_ensure_dir_with_a_trailing_backslash_creates_that_directory_itself():
	assert_eq(LFFile.ensure_dir(scratch_dir + "/made\\back\\"), OK)
	assert_true(DirAccess.dir_exists_absolute(LFFile.to_absolute(scratch_dir + "/made/back")))


func test_join_inside_portable_only_allows_dot_and_dot_dot_segments_that_stay_inside():
	var root := LFFile.to_absolute(scratch_dir)
	assert_eq(LFFile.join_inside(scratch_dir, "a/./b/../c.txt", true), root + "/a/c.txt")


func test_is_inside_allows_a_root_that_is_itself_a_link():
	LFFile.ensure_dir(scratch_dir + "/real/")
	if !_link(scratch_dir + "/real", scratch_dir + "/root-link"):
		pending("symbolic links can't be created here")
		return

	assert_true(LFFile.is_inside(scratch_dir + "/root-link", scratch_dir + "/root-link/x.txt"))


func test_remove_deletes_a_dangling_link():
	LFFile.save(scratch_dir + "/target.txt", "t")
	if !_link(scratch_dir + "/target.txt", scratch_dir + "/dangling"):
		pending("symbolic links can't be created here")
		return
	LFFile.remove(scratch_dir + "/target.txt")

	assert_eq(LFFile.remove(scratch_dir + "/dangling"), OK)

	var dir := DirAccess.open(LFFile.to_absolute(scratch_dir))
	assert_false(dir.is_link(LFFile.to_absolute(scratch_dir + "/dangling")), "the link itself is gone")


func test_move_aside_returns_empty_when_the_file_cannot_be_moved():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(scratch_dir + "/locked/data.json", "kept")
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/locked"), READ_ONLY_DIR)

	assert_eq(LFFile.move_aside(scratch_dir + "/locked/data.json", "corrupt"), "")

	assert_eq(LFFile.load_file(scratch_dir + "/locked/data.json"), "kept")


func test_move_aside_of_a_directory_moves_nothing():
	LFFile.ensure_dir(scratch_dir + "/a-dir/")
	assert_eq(LFFile.move_aside(scratch_dir + "/a-dir", "old"), "")
	assert_eq(LFFile.path_leads_to(scratch_dir + "/a-dir"), LFFile.PathTarget.DIR)


func test_copy_to_dir_reports_a_destination_directory_it_cannot_create():
	LFFile.save(scratch_dir + "/a.txt", "a")
	LFFile.save(scratch_dir + "/blocker", "a file")

	var ok := LFFile.copy_to_dir(scratch_dir + "/a.txt", scratch_dir + "/blocker/inner")

	assert_false(ok)
	assert_push_error("Failed to create directory")
	assert_engine_error("failed")
	assert_eq(LFFile.load_file(scratch_dir + "/blocker"), "a file")


func test_copy_to_dir_reports_a_copy_it_cannot_write_and_keeps_the_destination():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(scratch_dir + "/src.txt", "new")
	LFFile.save(scratch_dir + "/dest/src.txt", "old destination")
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/dest"), READ_ONLY_DIR)

	var ok := LFFile.copy_to_dir(scratch_dir + "/src.txt", scratch_dir + "/dest")

	assert_false(ok)
	assert_push_error("Copy failed")
	assert_engine_error("err != OK")
	assert_eq(LFFile.load_file(scratch_dir + "/dest/src.txt"), "old destination")
	assert_eq(Array(DirAccess.get_files_at(LFFile.to_absolute(scratch_dir + "/dest"))), ["src.txt"], "no temporary file is left behind")


func test_remove_recursive_returns_the_error_of_a_directory_it_cannot_open():
	if !_permissions_apply():
		pending("permission bits don't apply here")
		return
	LFFile.save(scratch_dir + "/sealed/kept.txt", "kept")
	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/sealed"), 0)

	assert_ne(LFFile.remove_recursive(scratch_dir + "/sealed"), OK)

	FileAccess.set_unix_permissions(LFFile.to_absolute(scratch_dir + "/sealed"), OWNER_ALL)
	assert_eq(LFFile.load_file(scratch_dir + "/sealed/kept.txt"), "kept")


func test_a_save_whose_directory_cannot_be_created_fails_and_reports_it():
	LFFile.save(scratch_dir + "/blocker", "a file")

	assert_false(LFFile.save(scratch_dir + "/blocker/inner/x.txt", "x"))

	assert_push_error("could not be created")
	assert_engine_error("failed")
	assert_eq(LFFile.load_file(scratch_dir + "/blocker"), "a file")


func test_remove_recursive_treats_a_root_as_something_it_will_not_delete() -> void:
	# The helper behind remove_recursive's refusal; the call itself is not made on a root.
	for root in ["/", "C:/", "z:/", LFFile.to_absolute("/..")]:
		assert_true(LFFile._is_filesystem_root(root), root)
	for other in ["", "/tmp", "C:/x", "C:", LFFile.to_absolute(scratch_dir)]:
		assert_false(LFFile._is_filesystem_root(other), other)


func test_is_blank_tells_empty_and_whitespace_from_control_bytes() -> void:
	var dir := 'user://lf_file_is_blank'
	LFFile.ensure_dir(dir)
	LFFile.save(dir + '/empty.txt', '')
	LFFile.save(dir + '/spaces.txt', ' \n\t ')
	LFFile.save_bytes(dir + '/zeros.bin', PackedByteArray([0, 0]))
	LFFile.save(dir + '/text.txt', '{}')
	assert_true(LFFile.is_blank(dir + '/empty.txt'))
	assert_true(LFFile.is_blank(dir + '/spaces.txt'))
	assert_false(LFFile.is_blank(dir + '/zeros.bin'))
	assert_false(LFFile.is_blank(dir + '/text.txt'))
	LFFile.remove_recursive(dir)
