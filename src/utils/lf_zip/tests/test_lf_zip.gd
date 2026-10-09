extends GutTest

## Builds real ZIPs with ZIPPacker (the write-side counterpart to the ZIPReader the
## extractor reads with) in a scratch folder under user://, so extraction is exercised
## end-to-end without any fixture checked into the repo.

## The process id keeps two runs that share one user:// folder apart.
var scratch_dir := "user://lf_zip_test_%d" % OS.get_process_id()
var zip_path := scratch_dir + "/archive.zip"
var out_dir := scratch_dir + "/out/"
## LFThread.force_main_thread as it was before each test; after_each puts it back.
var _saved_force_main_thread := false
## Long enough for any extraction here; a run that takes longer has hung.
const DEADLINE_MSEC := 20000
## The extractor's default total limit, 1 GiB.
const DEFAULT_TOTAL := 1024 * 1024 * 1024

## Signature of a local file header ("PK\x03\x04").
const LOCAL_HEADER := 0x04034b50
## Signature of a central directory file header ("PK\x01\x02").
const CENTRAL_HEADER := 0x02014b50
## Size of a local file header before its variable-length name, in bytes.
const LOCAL_HEADER_SIZE := 30
## Offset of the uncompressed size (u32) in a local file header.
const LOCAL_UNCOMPRESSED_SIZE_OFFSET := 22
## Offset of the file name length (u16) in a local file header.
const LOCAL_NAME_LENGTH_OFFSET := 26
## Offset of the extra field length (u16) in a local file header.
const LOCAL_EXTRA_LENGTH_OFFSET := 28
## Offset of the uncompressed size (u32) in a central directory file header.
const CENTRAL_UNCOMPRESSED_SIZE_OFFSET := 24
## Offset of the "version made by" (u16) in a central directory file header.
const CENTRAL_VERSION_MADE_BY_OFFSET := 4
## "Version made by" of a Unix archiver (host 3, spec 3.0).
const MADE_BY_UNIX := 0x031E
## Offset of the external file attributes (u32) in a central directory file header.
const CENTRAL_EXTERNAL_ATTRIBUTES_OFFSET := 38
## External attributes of a Unix symbolic link: mode 0120777 in the high 16 bits.
const UNIX_SYMLINK_ATTRIBUTES := 0xA1FF0000
## Size of one u32 signature, in bytes.
const SIGNATURE_SIZE := 4
## How many compressed bytes of the first entry get scribbled over.
const CORRUPTED_BYTES := 40
## The byte pattern XORed into them.
const CORRUPTION_MASK := 0x5A

## Signature of the end-of-central-directory record ("PK\x05\x06").
const EOCD := 0x06054b50
## Size of the end-of-central-directory record without its comment, in bytes.
const EOCD_SIZE := 22
## Offset of this disk's entry count (u16) in the end-of-central-directory record.
const EOCD_DISK_COUNT_OFFSET := 8
## Offset of the total entry count (u16) in the end-of-central-directory record.
const EOCD_COUNT_OFFSET := 10
## Offset of the central directory size (u32) in the end-of-central-directory record.
const EOCD_DIR_SIZE_OFFSET := 12
## Offset of the central directory start (u32) in the end-of-central-directory record.
const EOCD_DIR_OFFSET_OFFSET := 16
## Offset of the file name length (u16) in a central directory file header.
const CENTRAL_NAME_LENGTH_OFFSET := 28
## Offset of the extra field length (u16) in a central directory file header.
const CENTRAL_EXTRA_LENGTH_OFFSET := 30
## Size of a central directory file header before its variable-length name, in bytes.
const CENTRAL_HEADER_SIZE := 46
## Header ID of the zip64 extended information extra field.
const ZIP64_EXTRA_ID := 0x0001
## Size of an extra field block header (u16 id + u16 data size), in bytes.
const EXTRA_HEADER_SIZE := 4
## Offset of the data size (u16) in an extra field block header.
const EXTRA_DATA_SIZE_OFFSET := 2
## Data size of a zip64 extra field holding only the uncompressed size (one u64).
const ZIP64_EXTRA_DATA_SIZE := 8
## Whole zip64 extra field built here: header plus one u64.
const ZIP64_EXTRA_SIZE := EXTRA_HEADER_SIZE + ZIP64_EXTRA_DATA_SIZE
## A 16-bit field holding this value means "see the zip64 record".
const U16_MAX := 0xFFFF
## A 32-bit field holding this value means "see the zip64 record".
const U32_MAX := 0xFFFFFFFF
## Signature of the zip64 end-of-central-directory record ("PK\x06\x06").
const ZIP64_EOCD := 0x06064b50
## Size of the zip64 end-of-central-directory record without extensible data, in bytes.
const ZIP64_EOCD_SIZE := 56
## Leading bytes (signature + size field) the record's own size field leaves out.
const ZIP64_EOCD_LEADING_BYTES := 12
## Offset of the record's remaining size (u64) in the zip64 end record.
const ZIP64_EOCD_RECORD_SIZE_OFFSET := 4
## Offset of "version needed to extract" (u16) in the zip64 end record.
const ZIP64_EOCD_VERSION_NEEDED_OFFSET := 12
## Version 4.5: the first one with zip64.
const ZIP64_VERSION_NEEDED := 45
## Offset of this disk's entry count (u64) in the zip64 end record.
const ZIP64_EOCD_DISK_COUNT_OFFSET := 24
## Offset of the total entry count (u64) in the zip64 end record.
const ZIP64_EOCD_COUNT_OFFSET := 32
## Offset of the central directory size (u64) in the zip64 end record.
const ZIP64_EOCD_DIR_SIZE_OFFSET := 40
## Offset of the central directory start (u64) in the zip64 end record.
const ZIP64_EOCD_DIR_OFFSET_OFFSET := 48
## Signature of the zip64 end-of-central-directory locator ("PK\x06\x07").
const ZIP64_LOCATOR := 0x07064b50
## Size of the zip64 locator, in bytes.
const ZIP64_LOCATOR_SIZE := 20
## Offset of the zip64 end record's position (u64) in the locator.
const ZIP64_LOCATOR_RECORD_OFFSET := 8
## Offset of the total number of disks (u32) in the locator.
const ZIP64_LOCATOR_DISK_TOTAL_OFFSET := 16


func before_each():
	_saved_force_main_thread = LFThread.force_main_thread
	LFFile.remove_recursive(scratch_dir)
	LFFile.ensure_dir(scratch_dir + "/")


func after_each():
	LFThread.force_main_thread = _saved_force_main_thread
	LFFile.remove_recursive(scratch_dir)


func _create_test_zip(path: String, entries: Dictionary) -> void:
	var packer := ZIPPacker.new()
	packer.open(LFFile.to_absolute(path))
	for entry_path in entries.keys():
		packer.start_file(entry_path)
		packer.write_file(String(entries[entry_path]).to_utf8_buffer())
		packer.close_file()
	packer.close()


func _many_entries(count: int) -> Dictionary:
	var entries := {}
	for i in count:
		entries["file_%s.txt" % i] = "content %s" % i
	return entries


## Starts the extractor and waits for finished; [success, canceled], or [] on a hang.
func _run(extractor: LFZipExtractor) -> Array:
	var result := []
	extractor.finished.connect(func(success: bool, canceled: bool): result.append_array([success, canceled]))
	if !extractor.start():
		return ["not started"]
	var deadline := Time.get_ticks_msec() + DEADLINE_MSEC
	while result.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return result


## Rewrites the uncompressed size every header of the archive declares.
func _declare_size(path: String, declared: int) -> void:
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(path))
	for i in bytes.size() - SIGNATURE_SIZE:
		var signature := bytes.decode_u32(i)
		if signature == LOCAL_HEADER:
			bytes.encode_u32(i + LOCAL_UNCOMPRESSED_SIZE_OFFSET, declared)
		elif signature == CENTRAL_HEADER:
			bytes.encode_u32(i + CENTRAL_UNCOMPRESSED_SIZE_OFFSET, declared)
	var f := FileAccess.open(LFFile.to_absolute(path), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


## Scribbles over the compressed bytes of the archive's first entry, headers intact.
func _corrupt_first_entry(path: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(path))
	var data_start := LOCAL_HEADER_SIZE + bytes.decode_u16(LOCAL_NAME_LENGTH_OFFSET) + bytes.decode_u16(LOCAL_EXTRA_LENGTH_OFFSET)
	for i in range(data_start, data_start + CORRUPTED_BYTES):
		bytes[i] = bytes[i] ^ CORRUPTION_MASK
	var f := FileAccess.open(LFFile.to_absolute(path), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


## Creates a symbolic link at `link` pointing to `target`; false where links can't be made.
func _link(target: String, link: String) -> bool:
	var dir := DirAccess.open(LFFile.to_absolute(link).get_base_dir())
	return dir != null and dir.create_link(LFFile.to_absolute(target), LFFile.to_absolute(link)) == OK


func _leftover_staging() -> Array:
	return Array(DirAccess.get_directories_at(LFFile.to_absolute(scratch_dir))).filter(
		func(d: String) -> bool: return d.contains(".partial-")
	)


func _files_in(dir: String) -> Array:
	var absolute := LFFile.to_absolute(dir)
	return Array(DirAccess.get_files_at(absolute)) if DirAccess.dir_exists_absolute(absolute) else []


# ---- extracting

func test_extracts_files_including_nested_paths_with_matching_content():
	_create_test_zip(zip_path, {
		"top.txt": "top content",
		"sub/dir/nested.txt": "nested content",
	})

	var result = await LFZip.extract(zip_path, out_dir)

	assert_eq(result, [true, false])
	assert_eq(LFFile.load_file(out_dir + "top.txt"), "top content")
	assert_eq(LFFile.load_file(out_dir + "sub/dir/nested.txt"), "nested content")
	assert_eq(_leftover_staging(), [], "the staging folder is gone")


func test_progress_reports_the_correct_total_and_reaches_100_percent():
	_create_test_zip(zip_path, {"a.txt": "a", "b.txt": "b", "c.txt": "c"})
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	var totals := []
	var last_percent := [0.0]
	extractor.entry_processed.connect(func(percent, _file, _index, total):
		totals.append(total)
		last_percent[0] = percent
	)

	assert_eq(await _run(extractor), [true, false])

	assert_eq(totals, [3, 3, 3])
	assert_eq(last_percent[0], 100.0)


func test_a_target_directory_without_a_trailing_slash_is_still_the_target():
	_create_test_zip(zip_path, { "top.txt": "top content" })

	var result = await LFZip.extract(zip_path, out_dir.trim_suffix("/"))

	assert_true(result[0])
	assert_eq(LFFile.load_file(out_dir + "top.txt"), "top content", "must land inside the directory, not beside it")


func test_an_entry_with_a_leading_slash_lands_inside_the_target():
	_create_test_zip(zip_path, { "/abs.txt": "inside" })

	assert_eq(await LFZip.extract(zip_path, out_dir), [true, false])

	assert_eq(LFFile.load_file(out_dir + "abs.txt"), "inside")


## Unix `zip -y` stores a symbolic link as an entry whose content is the link's target and
## whose external attributes say "link". ZIPReader does not expose those attributes, so
## the entry becomes an ordinary file holding the target path; nothing is linked.
func test_a_symbolic_link_entry_is_written_as_a_plain_file_holding_its_target():
	_create_test_zip(zip_path, { "link": "/etc" })
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var dir_offset := bytes.decode_u32(bytes.size() - EOCD_SIZE + EOCD_DIR_OFFSET_OFFSET)
	bytes.encode_u32(dir_offset + CENTRAL_EXTERNAL_ATTRIBUTES_OFFSET, UNIX_SYMLINK_ATTRIBUTES)
	bytes.encode_u16(dir_offset + CENTRAL_VERSION_MADE_BY_OFFSET, MADE_BY_UNIX)
	_write_zip(bytes)

	assert_eq(await LFZip.extract(zip_path, out_dir), [true, false])

	var link := LFFile.to_absolute(out_dir + "link")
	assert_false(DirAccess.open(link.get_base_dir()).is_link(link), "not a link")
	assert_eq(LFFile.path_leads_to(link), LFFile.PathTarget.FILE)
	assert_eq(LFFile.load_file(link), "/etc")


## "f" as a file and "f/g" inside it can't both exist: refused before anything is staged,
## naming the file entry, whatever order they come in.
func test_a_file_entry_that_another_entry_needs_as_a_folder_refuses_the_archive():
	for entries in [{ "f": "file", "f/g": "child" }, { "F/g/h.txt": "child", "f": "file" }, { "d/": "", "D": "file" }]:
		LFFile.remove_recursive(out_dir)
		_create_test_zip(zip_path, entries)
		var extractor := LFZip.create_extractor(zip_path, out_dir)
		assert_eq(await _run(extractor), [false, false], str(entries))
		var file_entry: String = entries.keys().filter(func(n: String) -> bool: return !n.contains("/"))[0]
		assert_eq(Array(extractor.failed_entries), [file_entry], str(entries))
		assert_false(LFFile.path_exists(out_dir), "nothing is written")
		assert_eq(_leftover_staging(), [], "nothing was staged")
	assert_engine_error_count(0)


func test_a_second_start_while_running_is_ignored():
	_create_test_zip(zip_path, _many_entries(20))
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	var runs := []
	extractor.finished.connect(func(s: bool, c: bool): runs.append([s, c]))

	assert_true(extractor.start())
	assert_false(extractor.start(), "already running")
	var deadline := Time.get_ticks_msec() + DEADLINE_MSEC
	while runs.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(runs, [[true, false]], "one run, one finished")


func test_settings_changed_after_start_do_not_affect_the_run():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	var result := []
	extractor.finished.connect(func(s: bool, c: bool): result.append_array([s, c]))

	extractor.start()
	extractor.path_to_extract = LFFile.to_absolute(scratch_dir + "/elsewhere")
	var deadline := Time.get_ticks_msec() + DEADLINE_MSEC
	while result.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	assert_eq(result, [true, false])
	assert_eq(LFFile.load_file(out_dir + "a.txt"), "a")
	assert_false(LFFile.path_exists(scratch_dir + "/elsewhere"))


# ---- refusing a target

func test_an_empty_target_is_refused():
	_create_test_zip(zip_path, { "x.txt": "x" })
	var extractor := LFZipExtractor.new()
	extractor.path_to_zip = LFFile.to_absolute(zip_path)

	assert_false(extractor.start())
	assert_push_error("path_to_extract")


func test_a_relative_target_is_refused():
	_create_test_zip(zip_path, { "x.txt": "x" })
	var extractor := LFZipExtractor.new()
	extractor.path_to_zip = LFFile.to_absolute(zip_path)
	extractor.path_to_extract = "out"

	assert_false(extractor.start())
	assert_push_error("path_to_extract")


func test_extract_into_an_empty_target_reports_failure_without_writing():
	_create_test_zip(zip_path, { "x.txt": "x" })

	assert_eq(await LFZip.extract(zip_path, ""), [false, false])

	assert_push_error("path_to_extract")


func test_an_archive_that_fails_to_open_reports_failure():
	assert_eq(await LFZip.extract(scratch_dir + "/missing.zip", out_dir), [false, false])
	assert_eq(_files_in(out_dir), [])


# ---- unsafe entries

func test_entries_that_escape_the_target_directory_refuse_the_whole_archive():
	_create_test_zip(zip_path, {
		"../evil1.txt": "evil",
		"..\\evil2.txt": "evil",
		"sub/../../evil3.txt": "evil",
		"ok.txt": "fine",
	})
	var extractor := LFZip.create_extractor(zip_path, out_dir)

	assert_eq(await _run(extractor), [false, false])

	assert_eq(_files_in(scratch_dir), ["archive.zip"], "nothing lands outside the target (zip-slip)")
	assert_eq(_files_in(out_dir), [], "and nothing from a refused archive lands inside it")
	for unsafe in ["../evil1.txt", "..\\evil2.txt", "sub/../../evil3.txt"]:
		assert_has(extractor.failed_entries, unsafe)
	assert_does_not_have(extractor.failed_entries, "ok.txt")


func test_an_entry_through_a_link_in_the_target_is_refused():
	LFFile.ensure_dir(out_dir)
	LFFile.ensure_dir(scratch_dir + "/outside/")
	if !_link(scratch_dir + "/outside", out_dir + "link"):
		pending("symbolic links can't be created here")
		return
	_create_test_zip(zip_path, { "link/via_link.txt": "x" })

	assert_eq(await LFZip.extract(zip_path, out_dir), [false, false])

	assert_eq(_files_in(scratch_dir + "/outside"), [], "a link never carries an entry out of the target")


func test_an_existing_file_is_kept_unless_overwrite_is_on():
	LFFile.save(out_dir + "item_a.json", '{"mine": true}')
	_create_test_zip(zip_path, { "item_a.json": '{"theirs": true}', "new.txt": "new" })
	var extractor := LFZip.create_extractor(zip_path, out_dir)

	assert_eq(await _run(extractor), [false, false])

	assert_eq(LFFile.load_file(out_dir + "item_a.json"), '{"mine": true}')
	assert_false(LFFile.path_exists(out_dir + "new.txt"), "a refused archive writes nothing")
	assert_eq(Array(extractor.failed_entries), ["item_a.json"])


func test_overwrite_replaces_existing_files():
	LFFile.save(out_dir + "item_a.json", '{"mine": true}')
	_create_test_zip(zip_path, { "item_a.json": '{"theirs": true}' })

	assert_eq(await LFZip.extract(zip_path, out_dir, true), [true, false])

	assert_eq(LFFile.load_file(out_dir + "item_a.json"), '{"theirs": true}')


# ---- corrupt and oversized entries

func test_a_corrupt_entry_fails_the_run_and_never_replaces_an_existing_file():
	_create_test_zip(zip_path, { "item_b.json": '{"k": "' + "abcdefgh".repeat(400) + '"}' })
	_corrupt_first_entry(zip_path)
	LFFile.save(out_dir + "item_b.json", "previous content")
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	extractor.overwrite = true

	assert_eq(await _run(extractor), [false, false])
	await get_tree().process_frame # the worker's engine error reaches the log

	assert_engine_error("bytes_read")
	assert_eq(LFFile.load_file(out_dir + "item_b.json"), "previous content")
	assert_eq(Array(extractor.failed_entries), ["item_b.json"])
	assert_eq(_leftover_staging(), [])


func test_an_entry_declaring_more_than_max_entry_bytes_is_refused_before_it_is_decompressed():
	_create_test_zip(zip_path, { "liar.bin": "tiny" })
	_declare_size(zip_path, 900 * 1024 * 1024)
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	extractor.max_entry_bytes = 1024
	var peak_before := OS.get_static_memory_peak_usage()

	assert_eq(await _run(extractor), [false, false])

	assert_lt(OS.get_static_memory_peak_usage() - peak_before, 100 * 1024 * 1024, "the declared 900 MB was never allocated")
	assert_eq(Array(extractor.failed_entries), ["liar.bin"])
	assert_false(LFFile.path_exists(out_dir + "liar.bin"))


func test_an_entry_whose_content_is_shorter_than_declared_fails_the_run():
	_create_test_zip(zip_path, { "short.bin": "tiny" })
	_declare_size(zip_path, 64)

	var extractor := LFZip.create_extractor(zip_path, out_dir)
	assert_eq(await _run(extractor), [false, false])
	await get_tree().process_frame # the worker's engine error reaches the log

	assert_engine_error("bytes_read")
	assert_false(LFFile.path_exists(out_dir + "short.bin"))
	assert_eq(Array(extractor.failed_entries), ["short.bin"])


func test_an_entry_larger_than_max_entry_bytes_refuses_the_whole_archive():
	_create_test_zip(zip_path, { "big.txt": "x".repeat(100), "small.txt": "fine" })
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	extractor.max_entry_bytes = 50

	assert_eq(await _run(extractor), [false, false])

	assert_eq(_files_in(out_dir), [], "nothing is written from a refused archive")
	assert_eq(Array(extractor.failed_entries), ["big.txt"])


func test_entries_adding_up_to_more_than_max_total_bytes_refuse_the_archive():
	_create_test_zip(zip_path, { "a.txt": "x".repeat(60), "b.txt": "y".repeat(60) })
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	extractor.max_total_bytes = 100

	assert_eq(await _run(extractor), [false, false])

	assert_eq(_files_in(out_dir), [])
	assert_string_contains(extractor.failure_reason, "max_total_bytes")
	assert_eq(Array(extractor.failed_entries), [], "no single entry is to blame")


func test_an_archive_with_more_entries_than_max_entries_is_refused_whole():
	_create_test_zip(zip_path, { "a.txt": "a", "b.txt": "b", "c.txt": "c" })
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	extractor.max_entries = 2

	assert_eq(await _run(extractor), [false, false])

	assert_false(FileAccess.file_exists(out_dir + "a.txt"), "nothing is written from a refused archive")
	assert_string_contains(extractor.failure_reason, "max_entries")


func test_limits_are_on_by_default():
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	assert_eq(extractor.max_entries, LFZipExtractor.DEFAULT_MAX_ENTRIES)
	assert_eq(extractor.max_entry_bytes, LFZipExtractor.DEFAULT_MAX_ENTRY_BYTES)
	assert_eq(extractor.max_total_bytes, LFZipExtractor.DEFAULT_MAX_TOTAL_BYTES)
	assert_eq(LFZipExtractor.DEFAULT_MAX_ENTRIES, 10000)
	assert_eq(LFZipExtractor.DEFAULT_MAX_ENTRY_BYTES, 256 * 1024 * 1024)
	assert_eq(LFZipExtractor.DEFAULT_MAX_TOTAL_BYTES, 1024 * 1024 * 1024)
	assert_false(extractor.overwrite)


# ---- canceling and freeing

func test_a_canceled_run_reports_cancellation_and_writes_nothing():
	_create_test_zip(zip_path, _many_entries(2000))
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	var result := []
	extractor.finished.connect(func(s: bool, c: bool): result.append_array([s, c]))

	extractor.start()
	extractor.cancel()
	var deadline := Time.get_ticks_msec() + DEADLINE_MSEC
	while result.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	assert_eq(_leftover_staging(), [], "the staging folder is removed either way")
	if result == [true, false]:
		assert_eq(_files_in(out_dir).size(), 2000, "a cancel that came after the last entry changes nothing")
	else:
		assert_eq(result, [false, true])
		assert_eq(_files_in(out_dir), [], "a canceled run moves nothing into the target")


func test_dropping_a_running_extractor_stops_its_worker_and_cleans_up():
	_create_test_zip(zip_path, _many_entries(2000))
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	extractor.start()

	extractor = null # the last reference: stops and joins the worker

	assert_eq(_leftover_staging(), [], "the worker removed its staging folder before it was joined")
	var written := _files_in(out_dir).size()
	assert_true(written == 0 or written == 2000, "the target holds all of the archive or none of it, not %d entries" % written)


func test_a_canceled_run_reports_no_failed_entries():
	_create_test_zip(zip_path, _many_entries(2000))
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	var result := []
	extractor.finished.connect(func(s: bool, c: bool): result.append_array([s, c]))

	extractor.start()
	extractor.cancel()
	var deadline := Time.get_ticks_msec() + DEADLINE_MSEC
	while result.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	assert_false(result.is_empty(), "the run finished")
	assert_eq(Array(extractor.failed_entries), [], "a cancel is not a failure of any entry")


func test_finished_is_never_emitted_in_the_frame_start_was_called():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var extractor := LFZip.create_extractor(zip_path, "")
	extractor.path_to_extract = LFFile.to_absolute(out_dir)
	var runs := []
	assert_true(extractor.start())
	extractor.finished.connect(func(s: bool, c: bool): runs.append([s, c]))

	var deadline := Time.get_ticks_msec() + DEADLINE_MSEC
	while runs.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	assert_eq(runs, [[true, false]], "a listener connected right after start hears the result")


# ---- file and directory conflicts

func test_a_file_entry_where_the_target_has_a_directory_refuses_the_archive():
	_create_test_zip(zip_path, { "clash": "file content", "other.txt": "other" })
	LFFile.ensure_dir(out_dir + "clash/")
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	extractor.overwrite = true

	assert_eq(await _run(extractor), [false, false])

	assert_eq(Array(extractor.failed_entries), ["clash"])
	assert_eq(LFFile.path_leads_to(out_dir + "clash"), LFFile.PathTarget.DIR, "the directory is untouched")
	assert_false(LFFile.path_exists(out_dir + "other.txt"), "a refused archive writes nothing")


func test_a_directory_entry_where_the_target_has_a_file_refuses_the_archive():
	# ZIPPacker writes a "thing/" directory entry ahead of "thing/inner.txt".
	_create_test_zip(zip_path, { "thing/inner.txt": "inner", "other.txt": "other" })
	LFFile.save(out_dir + "thing", "a file")
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	extractor.overwrite = true

	assert_eq(await _run(extractor), [false, false])

	assert_has(Array(extractor.failed_entries), "thing/")
	assert_eq(LFFile.load_file(out_dir + "thing"), "a file")
	assert_false(LFFile.path_exists(out_dir + "other.txt"))


# ---- zip64

## Rewrites a single-entry archive in zip64 form: the entry's central header declares
## 0xFFFFFFFF and carries its real size in a zip64 extra field (when `entry_size_in_extra`),
## and the end record points at a zip64 end record through a zip64 locator (left out when
## `with_locator` is false, which leaves the zip64 directory missing).
func _rewrite_as_zip64(path: String, entry_size_in_extra: bool, with_locator := true) -> void:
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(path))
	var eocd := bytes.size() - EOCD_SIZE
	assert_eq(bytes.decode_u32(eocd), EOCD, "the archive ends with a plain end record")
	var count := bytes.decode_u16(eocd + EOCD_COUNT_OFFSET)
	var dir_size := bytes.decode_u32(eocd + EOCD_DIR_SIZE_OFFSET)
	var dir_offset := bytes.decode_u32(eocd + EOCD_DIR_OFFSET_OFFSET)
	var directory := bytes.slice(dir_offset, dir_offset + dir_size)
	if entry_size_in_extra:
		assert_eq(count, 1, "only single-entry archives are rewritten")
		var real_size := directory.decode_u32(CENTRAL_UNCOMPRESSED_SIZE_OFFSET)
		var name_length := directory.decode_u16(CENTRAL_NAME_LENGTH_OFFSET)
		var extra_length := directory.decode_u16(CENTRAL_EXTRA_LENGTH_OFFSET)
		var extra := PackedByteArray()
		extra.resize(ZIP64_EXTRA_SIZE)
		extra.encode_u16(0, ZIP64_EXTRA_ID)
		extra.encode_u16(EXTRA_DATA_SIZE_OFFSET, ZIP64_EXTRA_DATA_SIZE)
		extra.encode_u64(EXTRA_HEADER_SIZE, real_size)
		var insert_at := CENTRAL_HEADER_SIZE + name_length + extra_length
		var rewritten := directory.slice(0, insert_at)
		rewritten.append_array(extra)
		rewritten.append_array(directory.slice(insert_at))
		rewritten.encode_u32(CENTRAL_UNCOMPRESSED_SIZE_OFFSET, U32_MAX)
		rewritten.encode_u16(CENTRAL_EXTRA_LENGTH_OFFSET, extra_length + ZIP64_EXTRA_SIZE)
		directory = rewritten
	var out := bytes.slice(0, dir_offset)
	out.append_array(directory)
	var record_offset := out.size()
	if with_locator:
		var record := PackedByteArray()
		record.resize(ZIP64_EOCD_SIZE)
		record.encode_u32(0, ZIP64_EOCD)
		record.encode_u64(ZIP64_EOCD_RECORD_SIZE_OFFSET, ZIP64_EOCD_SIZE - ZIP64_EOCD_LEADING_BYTES)
		record.encode_u16(ZIP64_EOCD_VERSION_NEEDED_OFFSET, ZIP64_VERSION_NEEDED)
		record.encode_u64(ZIP64_EOCD_DISK_COUNT_OFFSET, count)
		record.encode_u64(ZIP64_EOCD_COUNT_OFFSET, count)
		record.encode_u64(ZIP64_EOCD_DIR_SIZE_OFFSET, directory.size())
		record.encode_u64(ZIP64_EOCD_DIR_OFFSET_OFFSET, dir_offset)
		out.append_array(record)
		var locator := PackedByteArray()
		locator.resize(ZIP64_LOCATOR_SIZE)
		locator.encode_u32(0, ZIP64_LOCATOR)
		locator.encode_u64(ZIP64_LOCATOR_RECORD_OFFSET, record_offset)
		locator.encode_u32(ZIP64_LOCATOR_DISK_TOTAL_OFFSET, 1)
		out.append_array(locator)
	var end := bytes.slice(eocd, eocd + EOCD_SIZE)
	end.encode_u16(EOCD_DISK_COUNT_OFFSET, U16_MAX)
	end.encode_u16(EOCD_COUNT_OFFSET, U16_MAX)
	end.encode_u32(EOCD_DIR_SIZE_OFFSET, U32_MAX)
	end.encode_u32(EOCD_DIR_OFFSET_OFFSET, U32_MAX)
	out.append_array(end)
	var f := FileAccess.open(LFFile.to_absolute(path), FileAccess.WRITE)
	f.store_buffer(out)
	f.close()


func test_a_zip64_archive_is_read_through_its_zip64_records():
	_create_test_zip(zip_path, { "big.txt": "zip64 content" })
	_rewrite_as_zip64(zip_path, true)

	assert_eq(LFZipExtractor._declared_sizes(LFFile.to_absolute(zip_path)), { "sizes": { "big.txt": 13 } })
	assert_eq(await LFZip.extract(zip_path, out_dir), [true, false])
	assert_eq(LFFile.load_file(out_dir + "big.txt"), "zip64 content")


func test_a_zip64_size_is_checked_against_max_entry_bytes():
	_create_test_zip(zip_path, { "big.txt": "zip64 content" })
	_rewrite_as_zip64(zip_path, true)
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	extractor.max_entry_bytes = 5

	assert_eq(await _run(extractor), [false, false])
	assert_eq(Array(extractor.failed_entries), ["big.txt"])


func test_an_archive_whose_zip64_directory_is_missing_is_refused():
	_create_test_zip(zip_path, { "a.txt": "a" })
	_rewrite_as_zip64(zip_path, false, false)

	assert_eq(LFZipExtractor._declared_sizes(LFFile.to_absolute(zip_path)), { "error": "its zip64 directory is missing" })
	assert_eq(await LFZip.extract(zip_path, out_dir), [false, false])
	assert_false(LFFile.path_exists(out_dir + "a.txt"))


func _create_raw_zip(path: String, entries: Array) -> void:
	var packer := ZIPPacker.new()
	packer.open(LFFile.to_absolute(path))
	for entry: Array in entries:
		packer.start_file(entry[0])
		if entry[1] != null:
			packer.write_file(String(entry[1]).to_utf8_buffer())
		packer.close_file()
	packer.close()


func test_an_archive_with_explicit_directory_entries_extracts():
	# ZIPPacker lists an explicit "dir/" twice: once for the entry itself, once ahead of
	# the file inside it.
	_create_raw_zip(zip_path, [["dir/", null], ["dir/f.txt", "inside"]])
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	var totals := []
	extractor.entry_processed.connect(func(_percent, _file, _index, total): totals.append(total))

	assert_eq(await _run(extractor), [true, false])

	assert_eq(LFFile.load_file(out_dir + "dir/f.txt"), "inside")
	assert_true(totals.all(func(total): return total == 2), "a repeated directory counts once: %s" % [totals])


func test_a_file_listed_twice_refuses_the_archive():
	_create_raw_zip(zip_path, [["same.txt", "first"], ["same.txt", "second"], ["other.txt", "other"]])
	var extractor := LFZip.create_extractor(zip_path, out_dir)

	assert_eq(await _run(extractor), [false, false])

	assert_false(LFFile.path_exists(out_dir + "same.txt"), "which copy is meant is ambiguous, so nothing is written")
	assert_false(LFFile.path_exists(out_dir + "other.txt"))
	assert_string_contains(extractor.failure_reason, "same.txt")


func test_the_failure_reason_is_empty_after_a_success():
	_create_test_zip(zip_path, {"a.txt": "a"})
	var extractor := LFZip.create_extractor(zip_path, out_dir)

	assert_eq(await _run(extractor), [true, false])

	assert_eq(extractor.failure_reason, "")


func test_two_names_for_one_file_refuse_the_archive():
	_create_raw_zip(zip_path, [["x.txt", "first"], ["/x.txt", "second"], ["other.txt", "other"]])
	var extractor := LFZip.create_extractor(zip_path, out_dir)

	assert_eq(await _run(extractor), [false, false])

	assert_eq(_files_in(out_dir), [], "neither copy is written")
	assert_eq(Array(extractor.failed_entries), ["/x.txt"])


func test_names_differing_only_in_case_refuse_the_archive_on_every_disk():
	_create_raw_zip(zip_path, [["Readme.txt", "first"], ["README.txt", "second"]])
	var extractor := LFZip.create_extractor(zip_path, out_dir)

	assert_eq(await _run(extractor), [false, false])

	assert_eq(_files_in(out_dir), [])
	assert_eq(Array(extractor.failed_entries), ["README.txt"])


func test_an_empty_archive_succeeds_and_creates_the_target():
	_create_raw_zip(zip_path, [])
	var extractor := LFZip.create_extractor(zip_path, out_dir)

	assert_eq(await _run(extractor), [true, false])

	assert_eq(LFFile.path_leads_to(out_dir), LFFile.PathTarget.DIR)
	assert_eq(extractor.failure_reason, "")
	assert_eq(_leftover_staging(), [])


func test_entry_names_windows_reserves_refuse_the_archive():
	for name in ["CON.txt", "a/aux", "data.txt:stream", "trailing.", "space /x.txt"]:
		LFFile.remove(zip_path)
		_create_test_zip(zip_path, {"ok.txt": "fine", name: "bad"})
		var extractor := LFZip.create_extractor(zip_path, out_dir)

		assert_eq(await _run(extractor), [false, false], name)
		assert_has(extractor.failed_entries, name)
		assert_does_not_have(extractor.failed_entries, "ok.txt")
		assert_eq(_files_in(out_dir), [], "nothing was written for %s" % name)


## A move that fails partway (here: the third entry's staged file is gone) undoes the
## moves before it: new files removed, the file it replaced restored, new folders removed.
func test_a_commit_that_fails_partway_rolls_everything_back():
	var target := LFFile.to_absolute(out_dir)
	var staging := LFFile.to_absolute(scratch_dir + "/staging")
	LFFile.save(out_dir + "a.txt", "old a")
	LFFile.save(scratch_dir + "/staging/a.txt", "new a")
	LFFile.save(scratch_dir + "/staging/sub/c.txt", "new c")
	var plan := [
		{"name": "a.txt", "is_dir": false},
		{"name": "sub/", "is_dir": true},
		{"name": "sub/c.txt", "is_dir": false},
		{"name": "b.txt", "is_dir": false},
	]

	var outcome := LFZipExtractor._commit(plan, staging, target, true)

	assert_eq(Array(outcome.failed), ["b.txt"])
	assert_string_contains(outcome.reason, "undone")
	assert_eq(LFFile.load_file(out_dir + "a.txt"), "old a", "the replaced file is back")
	assert_eq(_files_in(out_dir), ["a.txt"], "the moved-in files are gone")
	assert_false(DirAccess.dir_exists_absolute(target.path_join("sub")), "the folder it created is gone")
	assert_false(DirAccess.dir_exists_absolute(staging + "-replaced"), "no backups are left")


func test_a_commit_that_fails_into_a_new_target_removes_the_target_again():
	var target := LFFile.to_absolute(scratch_dir + "/fresh/out")
	var staging := LFFile.to_absolute(scratch_dir + "/staging")
	LFFile.save(scratch_dir + "/staging/a.txt", "new a")

	var outcome := LFZipExtractor._commit([{"name": "a.txt", "is_dir": false}, {"name": "b.txt", "is_dir": false}], staging, target, false)

	assert_eq(Array(outcome.failed), ["b.txt"])
	assert_false(DirAccess.dir_exists_absolute(LFFile.to_absolute(scratch_dir + "/fresh")), "every folder it created is gone")


## As on a web export without thread support: the run happens, blocking, in one frame.
func test_without_threads_the_run_still_completes_on_the_main_thread():
	_create_test_zip(zip_path, {"a.txt": "a", "sub/b.txt": "b"})
	LFThread.force_main_thread = true
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	var percents := []
	extractor.entry_processed.connect(func(percent, _file, _index, _total): percents.append(percent))

	var result := await _run(extractor)

	assert_eq(result, [true, false])
	assert_eq(LFFile.load_file(out_dir + "sub/b.txt"), "b")
	assert_eq(percents.size(), 3, "progress still arrives for each entry (the folder counts), all at once")
	assert_eq(percents[-1], 100.0)


# ---- refusing a start

func test_an_empty_archive_path_is_refused():
	var extractor := LFZip.create_extractor("  ", out_dir)

	assert_false(extractor.start())
	assert_push_error("path_to_zip is empty")


func test_cancel_without_a_run_does_nothing():
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	extractor.cancel()
	_create_test_zip(zip_path, { "a.txt": "a" })

	assert_eq(await _run(extractor), [true, false], "an earlier cancel does not stop a later run")


func test_create_extractor_sets_both_paths():
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	assert_eq(extractor.path_to_zip, zip_path)
	assert_eq(extractor.path_to_extract, out_dir)


func test_an_extractor_can_run_again_after_finishing():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	assert_eq(await _run(extractor), [true, false])
	assert_eq(await _run(extractor), [false, false], "the second run finds a.txt already there")
	assert_eq(Array(extractor.failed_entries), ["a.txt"], "the results are the second run's")
	extractor.overwrite = true
	assert_eq(await _run(extractor), [true, false])
	assert_eq(Array(extractor.failed_entries), [], "cleared again for the third run")


# ---- progress

func test_progress_names_each_entry_with_its_index_and_share():
	_create_test_zip(zip_path, {"a.txt": "a", "b.txt": "b", "c.txt": "c", "d.txt": "d"})
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	var seen := []
	extractor.entry_processed.connect(func(percent, file, index, total): seen.append([percent, file, index, total]))

	assert_eq(await _run(extractor), [true, false])

	assert_eq(seen, [[25.0, "a.txt", 1, 4], [50.0, "b.txt", 2, 4], [75.0, "c.txt", 3, 4], [100.0, "d.txt", 4, 4]])


func test_progress_also_reports_an_entry_that_fails_while_staging():
	_create_test_zip(zip_path, { "short.bin": "tiny" })
	_declare_size(zip_path, 64)
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	var files := []
	extractor.entry_processed.connect(func(_percent, file, _index, _total): files.append(file))

	assert_eq(await _run(extractor), [false, false])
	await get_tree().process_frame # the worker's engine error reaches the log

	assert_engine_error("bytes_read")
	assert_eq(files, ["short.bin"])


# ---- unreadable archives: why, in failure_reason

## Writes `bytes` as the archive.
func _write_zip(bytes: PackedByteArray) -> void:
	var f := FileAccess.open(LFFile.to_absolute(zip_path), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


## Runs an extractor over zip_path and returns its failure_reason (after checking the run failed).
func _refusal() -> String:
	var extractor := LFZip.create_extractor(zip_path, out_dir)
	assert_eq(await _run(extractor), [false, false])
	assert_eq(Array(extractor.failed_entries), [], "the archive as a whole is refused")
	assert_false(LFFile.path_exists(out_dir), "nothing is written")
	return extractor.failure_reason


func test_a_missing_archive_says_it_could_not_be_opened():
	assert_string_contains(await _refusal(), "it could not be opened")


func test_a_file_too_short_for_a_zip_is_refused():
	_write_zip("tiny".to_utf8_buffer())
	assert_string_contains(await _refusal(), "it is not a zip archive")


func test_a_file_without_an_end_record_is_refused():
	_write_zip("not a zip at all, just some text long enough".to_utf8_buffer())
	assert_string_contains(await _refusal(), "it has no central directory")


func test_an_end_record_pointing_past_the_file_is_refused():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	bytes.encode_u32(bytes.size() - EOCD_SIZE + EOCD_DIR_OFFSET_OFFSET, bytes.size())
	_write_zip(bytes)
	assert_string_contains(await _refusal(), "its central directory is out of range")


func test_a_central_header_with_a_bad_signature_is_refused():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var dir_offset := bytes.decode_u32(bytes.size() - EOCD_SIZE + EOCD_DIR_OFFSET_OFFSET)
	bytes.encode_u32(dir_offset, 0x12345678)
	_write_zip(bytes)
	assert_string_contains(await _refusal(), "its central directory is corrupt")


func test_more_entries_than_the_directory_holds_is_refused():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	bytes.encode_u16(bytes.size() - EOCD_SIZE + EOCD_COUNT_OFFSET, 2)
	_write_zip(bytes)
	assert_eq(LFZipExtractor._declared_sizes(LFFile.to_absolute(zip_path)), { "error": "its central directory is corrupt" })


func test_a_name_running_past_the_directory_is_refused():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var dir_offset := bytes.decode_u32(bytes.size() - EOCD_SIZE + EOCD_DIR_OFFSET_OFFSET)
	bytes.encode_u16(dir_offset + CENTRAL_NAME_LENGTH_OFFSET, 5000)
	_write_zip(bytes)
	assert_eq(LFZipExtractor._declared_sizes(LFFile.to_absolute(zip_path)), { "error": "its central directory is corrupt" })


func test_an_entry_marked_zip64_without_its_size_is_refused():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var dir_offset := bytes.decode_u32(bytes.size() - EOCD_SIZE + EOCD_DIR_OFFSET_OFFSET)
	bytes.encode_u32(dir_offset + CENTRAL_UNCOMPRESSED_SIZE_OFFSET, U32_MAX)
	_write_zip(bytes)
	assert_string_contains(await _refusal(), "an entry lacks its zip64 size")


func test_a_zip64_locator_pointing_past_the_file_is_refused():
	_create_test_zip(zip_path, { "big.txt": "zip64 content" })
	_rewrite_as_zip64(zip_path, true)
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var locator := bytes.size() - EOCD_SIZE - ZIP64_LOCATOR_SIZE
	bytes.encode_u64(locator + ZIP64_LOCATOR_RECORD_OFFSET, bytes.size())
	_write_zip(bytes)
	assert_string_contains(await _refusal(), "its zip64 directory is out of range")


## Two zip64 fields of 2^62 each add up past the largest int and wrap negative; the check
## must not be fooled into reading 2^62 bytes.
func test_a_zip64_directory_whose_offset_plus_size_overflows_is_refused():
	_create_test_zip(zip_path, { "big.txt": "zip64 content" })
	_rewrite_as_zip64(zip_path, true)
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var locator := bytes.size() - EOCD_SIZE - ZIP64_LOCATOR_SIZE
	var record := bytes.decode_u64(locator + ZIP64_LOCATOR_RECORD_OFFSET)
	bytes.encode_u64(record + ZIP64_EOCD_DIR_SIZE_OFFSET, 1 << 62)
	bytes.encode_u64(record + ZIP64_EOCD_DIR_OFFSET_OFFSET, 1 << 62)
	_write_zip(bytes)
	assert_string_contains(await _refusal(), "its central directory is out of range")
	assert_engine_error_count(0)


## A locator offset just below 2^63 wraps negative once the record's size is added.
func test_a_zip64_locator_offset_that_overflows_is_refused():
	_create_test_zip(zip_path, { "big.txt": "zip64 content" })
	_rewrite_as_zip64(zip_path, true)
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var locator := bytes.size() - EOCD_SIZE - ZIP64_LOCATOR_SIZE
	bytes.encode_u64(locator + ZIP64_LOCATOR_RECORD_OFFSET, 0x7FFFFFFFFFFFFFF6)
	_write_zip(bytes)
	assert_string_contains(await _refusal(), "its zip64 directory is out of range")
	assert_engine_error_count(0)


func test_a_zip64_record_with_a_bad_signature_is_refused():
	_create_test_zip(zip_path, { "big.txt": "zip64 content" })
	_rewrite_as_zip64(zip_path, true)
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var locator := bytes.size() - EOCD_SIZE - ZIP64_LOCATOR_SIZE
	bytes.encode_u32(bytes.decode_u64(locator + ZIP64_LOCATOR_RECORD_OFFSET), 0x12345678)
	_write_zip(bytes)
	assert_string_contains(await _refusal(), "its zip64 directory is corrupt")


func test_the_zip64_size_is_found_after_other_extra_fields():
	_create_test_zip(zip_path, { "big.txt": "zip64 content" })
	_rewrite_as_zip64(zip_path, true)
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	# Prepend an unrelated 4-byte extra block to the entry's extra field.
	var locator := bytes.size() - EOCD_SIZE - ZIP64_LOCATOR_SIZE
	var record_offset := bytes.decode_u64(locator + ZIP64_LOCATOR_RECORD_OFFSET)
	var dir_offset := bytes.decode_u64(record_offset + ZIP64_EOCD_DIR_OFFSET_OFFSET)
	var name_length := bytes.decode_u16(dir_offset + CENTRAL_NAME_LENGTH_OFFSET)
	var extra_length := bytes.decode_u16(dir_offset + CENTRAL_EXTRA_LENGTH_OFFSET)
	var other := PackedByteArray([0x99, 0x99, 4, 0, 1, 2, 3, 4])
	var insert_at := dir_offset + CENTRAL_HEADER_SIZE + name_length
	var out := bytes.slice(0, insert_at)
	out.append_array(other)
	out.append_array(bytes.slice(insert_at))
	out.encode_u16(dir_offset + CENTRAL_EXTRA_LENGTH_OFFSET, extra_length + other.size())
	var new_record := record_offset + other.size()
	out.encode_u64(new_record + ZIP64_EOCD_DIR_SIZE_OFFSET, out.decode_u64(new_record + ZIP64_EOCD_DIR_SIZE_OFFSET) + other.size())
	out.encode_u64(out.size() - EOCD_SIZE - ZIP64_LOCATOR_SIZE + ZIP64_LOCATOR_RECORD_OFFSET, new_record)
	_write_zip(out)

	assert_eq(LFZipExtractor._declared_sizes(LFFile.to_absolute(zip_path)), { "sizes": { "big.txt": 13 } })


func test_a_zip64_extra_field_too_short_for_a_size_is_not_read():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var dir_offset := bytes.decode_u32(bytes.size() - EOCD_SIZE + EOCD_DIR_OFFSET_OFFSET)
	var name_length := bytes.decode_u16(dir_offset + CENTRAL_NAME_LENGTH_OFFSET)
	var extra_length := bytes.decode_u16(dir_offset + CENTRAL_EXTRA_LENGTH_OFFSET)
	var short := PackedByteArray([ZIP64_EXTRA_ID, 0, 4, 0, 1, 0, 0, 0]) # a zip64 block holding 4 bytes
	var insert_at := dir_offset + CENTRAL_HEADER_SIZE + name_length + extra_length
	var out := bytes.slice(0, insert_at)
	out.append_array(short)
	out.append_array(bytes.slice(insert_at))
	out.encode_u32(dir_offset + CENTRAL_UNCOMPRESSED_SIZE_OFFSET, U32_MAX)
	out.encode_u16(dir_offset + CENTRAL_EXTRA_LENGTH_OFFSET, extra_length + short.size())
	var eocd := out.size() - EOCD_SIZE
	out.encode_u32(eocd + EOCD_DIR_SIZE_OFFSET, out.decode_u32(eocd + EOCD_DIR_SIZE_OFFSET) + short.size())
	_write_zip(out)

	assert_eq(LFZipExtractor._declared_sizes(LFFile.to_absolute(zip_path)), { "error": "an entry lacks its zip64 size" })


## ZIPReader takes the entry sizes from the directory its own search finds; a directory
## the extractor reads somewhere else would let an archive declare small sizes here and
## huge ones there, past max_entry_bytes.
func test_a_directory_read_at_a_different_place_than_ZIPReader_reads_it_is_refused():
	_create_test_zip(zip_path, { "big.txt": "zip64 content" })
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var end := bytes.size() - EOCD_SIZE
	var dir_offset := bytes.decode_u32(end + EOCD_DIR_OFFSET_OFFSET)
	var directory := bytes.slice(dir_offset, end)
	var decoy := directory.duplicate()
	decoy.encode_u32(CENTRAL_UNCOMPRESSED_SIZE_OFFSET, 1)
	# Junk before the archive moves where ZIPReader finds the real directory; the end
	# record's offset now lands on the decoy placed inside that junk.
	var out := PackedByteArray()
	out.resize(dir_offset + decoy.size() + 16)
	out.encode_u32(0, 0x4A4A4A4A)
	for i in decoy.size():
		out[dir_offset + i] = decoy[i]
	out.append_array(bytes)
	_write_zip(out)

	var reader := ZIPReader.new()
	assert_eq(reader.open(LFFile.to_absolute(zip_path)), OK)
	assert_eq(reader.read_file("big.txt").size(), 13, "ZIPReader reads the real directory")
	reader.close()
	assert_has(LFZipExtractor._declared_sizes(LFFile.to_absolute(zip_path)), "error")


## Zip64 sizes go up to 2^63 - 1; two of 2^62 + 2^62 wrap negative if simply added.
func test_declared_sizes_that_overflow_when_added_still_pass_the_total_limit_check():
	var job := {
		"target": LFFile.to_absolute(out_dir), "max_entries": 0, "max_entry_bytes": 0,
		"max_total_bytes": DEFAULT_TOTAL, "overwrite": false,
	}
	var result := { "success": false, "canceled": false, "failed": PackedStringArray(), "reason": "" }
	var plan: Variant = LFZipExtractor._plan(PackedStringArray(["a", "b", "c"]),
			{ "a": 1 << 62, "b": 1 << 62, "c": 1 << 62 }, job, result)

	assert_null(plan)
	assert_string_contains(result.reason, "over max_total_bytes")


func test_a_zip64_locator_outside_its_place_is_refused():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var locator := PackedByteArray()
	locator.resize(ZIP64_LOCATOR_SIZE)
	locator.encode_u32(0, ZIP64_LOCATOR)
	bytes.encode_u16(bytes.size() - 2, locator.size())
	bytes.append_array(locator)
	_write_zip(bytes)

	assert_eq(LFZipExtractor._declared_sizes(LFFile.to_absolute(zip_path)), { "error": "its zip64 locator is ambiguous" })


func test_an_entry_with_two_zip64_size_fields_is_refused():
	_create_test_zip(zip_path, { "big.txt": "zip64 content" })
	_rewrite_as_zip64(zip_path, true)
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var locator := bytes.size() - EOCD_SIZE - ZIP64_LOCATOR_SIZE
	var record_offset := bytes.decode_u64(locator + ZIP64_LOCATOR_RECORD_OFFSET)
	var dir_offset := bytes.decode_u64(record_offset + ZIP64_EOCD_DIR_OFFSET_OFFSET)
	var name_length := bytes.decode_u16(dir_offset + CENTRAL_NAME_LENGTH_OFFSET)
	var extra_length := bytes.decode_u16(dir_offset + CENTRAL_EXTRA_LENGTH_OFFSET)
	var second := PackedByteArray([ZIP64_EXTRA_ID, 0, ZIP64_EXTRA_DATA_SIZE, 0, 99, 0, 0, 0, 0, 0, 0, 0])
	var insert_at := dir_offset + CENTRAL_HEADER_SIZE + name_length + extra_length
	var out := bytes.slice(0, insert_at)
	out.append_array(second)
	out.append_array(bytes.slice(insert_at))
	out.encode_u16(dir_offset + CENTRAL_EXTRA_LENGTH_OFFSET, extra_length + second.size())
	var new_record := record_offset + second.size()
	out.encode_u64(new_record + ZIP64_EOCD_DIR_SIZE_OFFSET, out.decode_u64(new_record + ZIP64_EOCD_DIR_SIZE_OFFSET) + second.size())
	out.encode_u64(out.size() - EOCD_SIZE - ZIP64_LOCATOR_SIZE + ZIP64_LOCATOR_RECORD_OFFSET, new_record)
	_write_zip(out)

	assert_eq(LFZipExtractor._declared_sizes(LFFile.to_absolute(zip_path)), { "error": "an entry lacks its zip64 size" })


func test_a_comment_after_the_end_record_is_read_past():
	_create_test_zip(zip_path, { "a.txt": "a" })
	var bytes := FileAccess.get_file_as_bytes(LFFile.to_absolute(zip_path))
	var comment := "a comment".to_utf8_buffer()
	bytes.encode_u16(bytes.size() - 2, comment.size())
	bytes.append_array(comment)
	_write_zip(bytes)

	assert_eq(await LFZip.extract(zip_path, out_dir), [true, false])
	assert_eq(LFFile.load_file(out_dir + "a.txt"), "a")


# ---- staging and committing

func test_a_target_whose_parent_is_a_file_fails_without_leaving_anything():
	LFFile.save(scratch_dir + "/blocker", "a file, not a folder")
	_create_test_zip(zip_path, { "a.txt": "a" })
	var extractor := LFZip.create_extractor(zip_path, scratch_dir + "/blocker/out")

	assert_eq(await _run(extractor), [false, false])
	await get_tree().process_frame # the worker's engine error reaches the log

	assert_engine_error("Could not create directory")
	assert_string_contains(extractor.failure_reason, "could not create")
	assert_eq(LFFile.load_file(scratch_dir + "/blocker"), "a file, not a folder")


func test_a_commit_into_a_target_that_cannot_be_created_moves_nothing():
	LFFile.save(scratch_dir + "/blocker", "a file")
	LFFile.save(scratch_dir + "/staging/a.txt", "new a")
	var target := LFFile.to_absolute(scratch_dir + "/blocker/out")

	var outcome := LFZipExtractor._commit([{"name": "a.txt", "is_dir": false}], LFFile.to_absolute(scratch_dir + "/staging"), target, false)

	assert_eq(outcome.reason, "could not create %s" % target)
	assert_eq(Array(outcome.failed), [])
	assert_eq(LFFile.load_file(scratch_dir + "/staging/a.txt"), "new a", "the staged file was not moved")


func test_a_commit_that_meets_a_file_it_may_not_replace_undoes_the_run():
	LFFile.save(scratch_dir + "/staging/a.txt", "new a")
	LFFile.save(scratch_dir + "/staging/b.txt", "new b")
	LFFile.save(out_dir + "b.txt", "appeared meanwhile")

	var outcome := LFZipExtractor._commit([{"name": "a.txt", "is_dir": false}, {"name": "b.txt", "is_dir": false}],
			LFFile.to_absolute(scratch_dir + "/staging"), LFFile.to_absolute(out_dir), false)

	assert_eq(Array(outcome.failed), ["b.txt"])
	assert_eq(LFFile.load_file(out_dir + "b.txt"), "appeared meanwhile")
	assert_false(LFFile.path_exists(out_dir + "a.txt"), "a.txt was taken back out")


func test_a_commit_that_meets_a_folder_where_a_file_goes_undoes_the_run():
	LFFile.save(scratch_dir + "/staging/a.txt", "new a")
	LFFile.save(scratch_dir + "/staging/b.txt", "new b")
	LFFile.ensure_dir(out_dir + "b.txt/")

	var outcome := LFZipExtractor._commit([{"name": "a.txt", "is_dir": false}, {"name": "b.txt", "is_dir": false}],
			LFFile.to_absolute(scratch_dir + "/staging"), LFFile.to_absolute(out_dir), true)

	assert_eq(Array(outcome.failed), ["b.txt"])
	assert_false(LFFile.path_exists(out_dir + "a.txt"))
	assert_eq(LFFile.path_leads_to(out_dir + "b.txt"), LFFile.PathTarget.DIR)


func test_a_commit_keeps_a_folder_something_else_wrote_into():
	LFFile.save(scratch_dir + "/staging/sub/a.txt", "new a")
	var target := LFFile.to_absolute(out_dir)
	var plan := [{"name": "sub/", "is_dir": true}, {"name": "sub/a.txt", "is_dir": false}, {"name": "missing.txt", "is_dir": false}]
	# A folder the run creates, then fills with a file of someone else's before the failure.
	var outcome := LFZipExtractor._commit(plan.slice(0, 1), LFFile.to_absolute(scratch_dir + "/staging"), target, false)
	assert_eq(outcome.reason, "")
	LFFile.save(out_dir + "sub/theirs.txt", "theirs")
	LFFile.remove_recursive(out_dir + "sub/a.txt")

	outcome = LFZipExtractor._commit(plan.slice(1), LFFile.to_absolute(scratch_dir + "/staging"), target, false)

	assert_eq(Array(outcome.failed), ["missing.txt"])
	assert_eq(LFFile.load_file(out_dir + "sub/theirs.txt"), "theirs", "a folder holding someone else's file stays")
	assert_false(LFFile.path_exists(out_dir + "sub/a.txt"))


func test_entries_refused_one_by_one_leave_the_failure_reason_empty():
	LFFile.save(out_dir + "taken.txt", "mine")
	_create_test_zip(zip_path, { "taken.txt": "theirs", "../escape.txt": "x" })
	var extractor := LFZip.create_extractor(zip_path, out_dir)

	assert_eq(await _run(extractor), [false, false])

	assert_eq(extractor.failure_reason, "", "failed_entries says it all")
	assert_has(extractor.failed_entries, "taken.txt")
	assert_has(extractor.failed_entries, "../escape.txt")
