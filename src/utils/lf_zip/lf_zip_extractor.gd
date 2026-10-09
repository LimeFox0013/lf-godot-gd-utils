## Unzips an archive into a folder in the background, checking it first and undoing a
## partial result.
##
## The work runs on an [LFThread] so the main thread doesn't freeze; progress and the
## result arrive on the main thread, and a run can be canceled. Without thread support
## (e.g. a web export built without threads) LFThread runs the whole extraction on the main
## thread, blocking, in one frame, and canceling cannot interrupt it. The archive's central
## directory is checked first (entry count, declared sizes, paths that would leave the
## target or that Windows cannot create, existing files); every entry is then decompressed
## into a staging folder beside the target (only its declared size is read, and shorter
## content fails the run), and only a fully staged archive is moved into the target. If a move fails partway, the files
## already moved in are removed, the files they replaced are put back, and the folders the
## run created are removed when empty; if that undo itself fails, [member failure_reason]
## says what is left and where the replaced files were kept. A crash or power loss during
## the moves is not undone. Keep a reference to the extractor until `finished`: dropping
## the last one cancels the run.
class_name LFZipExtractor
extends RefCounted

## Default for max_entries.
const DEFAULT_MAX_ENTRIES := 10000
## Default for max_entry_bytes: 256 MiB.
const DEFAULT_MAX_ENTRY_BYTES := 256 * 1024 * 1024
## Default for max_total_bytes: 1 GiB.
const DEFAULT_MAX_TOTAL_BYTES := 1024 * 1024 * 1024

## Signature of the end-of-central-directory record ("PK\x05\x06").
const _EOCD := 0x06054b50
## Signature of the zip64 end-of-central-directory locator ("PK\x06\x07").
const _ZIP64_LOCATOR := 0x07064b50
## Signature of the zip64 end-of-central-directory record ("PK\x06\x06").
const _ZIP64_EOCD := 0x06064b50
## Signature of a central directory file header ("PK\x01\x02").
const _CENTRAL_HEADER := 0x02014b50
## A 32-bit field holding this value means "the real value is in the zip64 record".
const _U32_MAX := 0xFFFFFFFF
## Largest int: the cap the running total of declared sizes saturates at.
const _INT_MAX := 0x7FFFFFFFFFFFFFFF
## A 16-bit entry count holding this value means "the real count is in the zip64 record".
const _U16_MAX := 0xFFFF

## Size of the end-of-central-directory record without its comment, in bytes.
const _EOCD_SIZE := 22
## Longest comment the end-of-central-directory record can carry, in bytes.
const _EOCD_MAX_COMMENT := 0xFFFF
## Offset of the total entry count (u16) in the end-of-central-directory record.
const _EOCD_COUNT_OFFSET := 10
## Offset of the central directory size (u32) in the end-of-central-directory record.
const _EOCD_DIR_SIZE_OFFSET := 12
## Offset of the central directory start (u32) in the end-of-central-directory record.
const _EOCD_DIR_OFFSET_OFFSET := 16
## Size of the zip64 locator, which sits right before the end-of-central-directory record.
const _ZIP64_LOCATOR_SIZE := 20
## Offset of the zip64 record's position (u64) in the zip64 locator.
const _ZIP64_LOCATOR_RECORD_OFFSET := 8
## Size of the zip64 end-of-central-directory record without its extensible data, in bytes.
const _ZIP64_EOCD_SIZE := 56
## Offset of the total entry count (u64) in the zip64 end-of-central-directory record.
const _ZIP64_EOCD_COUNT_OFFSET := 32
## Offset of the central directory size (u64) in the zip64 end-of-central-directory record.
const _ZIP64_EOCD_DIR_SIZE_OFFSET := 40
## Offset of the central directory start (u64) in the zip64 end-of-central-directory record.
const _ZIP64_EOCD_DIR_OFFSET_OFFSET := 48
## Size of a central directory file header before its variable-length name, in bytes.
const _CENTRAL_HEADER_SIZE := 46
## Offset of the uncompressed size (u32) in a central directory file header.
const _CENTRAL_UNCOMPRESSED_SIZE_OFFSET := 24
## Offset of the file name length (u16) in a central directory file header.
const _CENTRAL_NAME_LENGTH_OFFSET := 28
## Offset of the extra field length (u16) in a central directory file header.
const _CENTRAL_EXTRA_LENGTH_OFFSET := 30
## Offset of the file comment length (u16) in a central directory file header.
const _CENTRAL_COMMENT_LENGTH_OFFSET := 32
## Header ID of the zip64 extended information extra field.
const _ZIP64_EXTRA_ID := 0x0001
## Size of an extra field block header (u16 id + u16 data size), in bytes.
const _EXTRA_HEADER_SIZE := 4
## Offset of the data size (u16) in an extra field block header.
const _EXTRA_SIZE_OFFSET := 2
## Size of one u64 value, in bytes: the zip64 extra field's uncompressed size.
const _U64_SIZE := 8

## Suffix that marks an archive entry as a directory.
const _DIR_SUFFIX := '/'
## Name of the worker thread (shows in logs and debuggers).
const _THREAD_NAME := 'lf-zip'
## Log line prefix.
const _LOG_PREFIX := '[LFZipExtractor]'
## Staging folder beside the target: target path, process id, start time in microseconds.
const _STAGING_FORMAT := '%s.partial-%d-%d'
## Suffix of the folder beside the staging folder that holds files an entry replaced,
## until the run has moved everything in.
const _BACKUP_SUFFIX := '-replaced'
## Progress at the last entry, in percent.
const _PERCENT_DONE := 100.0

## One archive entry was decompressed into the staging folder (or failed to be); percent
## is index / total * 100. Emitted on the main thread, once per entry, a frame or so after
## the worker got there.
signal entry_processed(percent: float, file: String, index: int, total: int)
## The run ended. success: every entry is now in the target (an empty archive succeeds
## and only creates the target). canceled: `cancel` stopped it before anything was moved
## into the target. Emitted on the main thread.
signal finished(success: bool, canceled: bool)

## The archive (any path LFFile resolves).
var path_to_zip: String = ''
## The destination directory, created if missing: absolute, res:// or user://. An empty
## or relative path is refused by `start`.
var path_to_extract: String = ''
## Most entries an archive may hold; 0 means unlimited.
var max_entries: int = DEFAULT_MAX_ENTRIES
## Largest uncompressed size one entry may declare, in bytes; 0 means unlimited.
## Checked before the entry is decompressed, so it bounds memory as well as disk.
var max_entry_bytes: int = DEFAULT_MAX_ENTRY_BYTES
## Largest uncompressed size all entries together may declare; 0 means unlimited.
var max_total_bytes: int = DEFAULT_MAX_TOTAL_BYTES
## Whether an entry may replace a file already in the target. When false, an archive
## holding such an entry is refused whole.
var overwrite: bool = false
## After `finished`: the entries that made the run fail (refused, unreadable, corrupt
## or not written); empty on success or when the archive itself was refused.
var failed_entries: PackedStringArray = PackedStringArray()
## After `finished`: why the whole archive was refused (bad directory, a limit, a file
## listed twice…) or why moving into the target failed (and whether it was undone);
## empty on success, and when the failure is only individual entries (refused before
## staging or failed while staging), which `failed_entries` names.
var failure_reason: String = ''

var _log := LFLogger.new([_LOG_PREFIX])
var _thread: LFThread
## True while a per-frame loop reports this extractor's progress and results.
var _polling := false
## The frame `start` was called in; the loop reports nothing before the next one, so a
## caller connecting to `finished` right after `start` never misses it.
var _start_frame := -1
## Shared with the worker: the run's settings, plus queued progress under a mutex.
var _job: Dictionary = {}


## Starts extracting on a worker thread with a snapshot of the settings above; connect to
## [signal finished] for the result. Returns false (and starts nothing) while a run is in
## progress, or with a pushed error when path_to_zip or path_to_extract is empty,
## path_to_extract is not absolute (res://, user:// or an OS path), or no SceneTree is
## running.
func start() -> bool:
	if _thread != null:
		return false
	if path_to_zip.strip_edges() == '':
		_log.error('start: path_to_zip is empty')
		return false
	if path_to_extract.strip_edges() == '' or !path_to_extract.is_absolute_path():
		_log.error('start: path_to_extract must be an absolute directory, got "%s"' % path_to_extract)
		return false
	if LFUtils.tree_root == null:
		_log.error('start: needs a SceneTree main loop to report back on')
		return false

	failed_entries = PackedStringArray()
	failure_reason = ''
	var job := {
		'zip': LFFile.to_absolute(path_to_zip),
		'target': LFFile.to_absolute(path_to_extract),
		'max_entries': max_entries,
		'max_entry_bytes': max_entry_bytes,
		'max_total_bytes': max_total_bytes,
		'overwrite': overwrite,
		'progress': [],
		'mutex': Mutex.new(),
	}
	var thread := LFThread.new(_THREAD_NAME)
	thread.finished.connect(_on_thread_ended)
	thread.canceled.connect(_on_thread_ended)
	# The task captures only the job, never this object (see LFThread). A new LFThread with
	# a valid task always starts (inline when threads are unavailable).
	thread.start_cancelable(func(should_stop: Callable) -> Dictionary:
		return LFZipExtractor._extract(job, should_stop)
	)
	_job = job
	_thread = thread
	_log.log('start -> zip: %s -> dir: %s' % [job.zip, job.target])
	_start_frame = Engine.get_process_frames()
	if !_polling:
		_polling = true
		@warning_ignore("missing_await")
		LFUtils.poll_each_frame(self, &'_poll_step')
	return true


## Stops the run before the next entry, or before anything is moved into the target;
## finished(false, true) follows. A run already moving entries into place completes.
func cancel() -> void:
	if _thread != null:
		_thread.request_stop()


## One frame of reporting: queued progress, then the worker's result once it is done.
## False (ending the loop) once no run is in progress.
func _poll_step() -> bool:
	if Engine.get_process_frames() != _start_frame:
		_emit_progress()
		# A step only runs while a run is in progress, so `_thread` is set here.
		var thread := _thread # keeps it alive through its own finished/canceled emission
		thread.poll()
	_polling = _thread != null
	return _polling


func _on_thread_ended(_id: String, _key: String, result: Variant) -> void:
	_emit_progress()
	_thread = null
	var outcome: Dictionary = result if result is Dictionary else {}
	failed_entries = outcome.get('failed', PackedStringArray())
	failure_reason = outcome.get('reason', '')
	var success: bool = outcome.get('success', false)
	var canceled: bool = outcome.get('canceled', false)
	if outcome.get('reason', '') != '':
		_log.log(outcome.reason)
	_log.log('finished. success=%s canceled=%s' % [success, canceled])
	finished.emit(success, canceled)


func _emit_progress() -> void:
	var mutex: Mutex = _job.mutex
	mutex.lock()
	var queued: Array = _job.progress.duplicate()
	_job.progress.clear()
	mutex.unlock()
	for args: Array in queued:
		entry_processed.emit(args[0], args[1], args[2], args[3])


# ---- Worker (never touches this object or the scene tree) ----

static func _extract(job: Dictionary, should_stop: Callable) -> Dictionary:
	var result := {'success': false, 'canceled': false, 'failed': PackedStringArray(), 'reason': ''}
	var target: String = job.target

	var zip_path: String = job.zip
	var declared := _declared_sizes(zip_path)
	if declared.has('error'):
		result.reason = 'refused %s: %s' % [zip_path, declared.error]
		return result
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		result.reason = 'could not open %s' % zip_path
		return result

	var names := _unique_names(zip.get_files())
	var sizes: Dictionary = declared.sizes
	var plan: Variant = _plan(names, sizes, job, result)
	if plan == null:
		zip.close()
		return result
	var entries: Array = plan

	var staging := _STAGING_FORMAT % [target, OS.get_process_id(), Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		zip.close()
		result.reason = 'could not create %s' % staging
		return result

	_stage_all(zip, entries, staging, job, should_stop, result)
	zip.close()

	if !result.canceled and result.failed.is_empty() and should_stop.call():
		result.canceled = true
	if result.canceled or !result.failed.is_empty():
		LFFile.remove_recursive(staging)
		return result

	var may_overwrite: bool = job.overwrite
	var committed := _commit(entries, staging, target, may_overwrite)
	LFFile.remove_recursive(staging)
	result.failed = committed.failed
	result.reason = committed.reason
	result.success = result.failed.is_empty() and result.reason == ''
	return result


## The entry names without repeats, in order. Some writers (Godot's ZIPPacker among them)
## list a directory more than once; it is the same directory, so it counts once. A file
## listed twice was refused already.
static func _unique_names(listed: PackedStringArray) -> PackedStringArray:
	var names := PackedStringArray()
	var seen := {}
	for name in listed:
		if !seen.has(name):
			seen[name] = true
			names.append(name)
	return names


## Extracts every planned entry into `staging`, queueing a progress record per entry on the
## job. Stops early (and sets `result.canceled`) when `should_stop` says so; entries that
## fail are added to `result.failed`.
static func _stage_all(zip: ZIPReader, plan: Array, staging: String, job: Dictionary, should_stop: Callable, result: Dictionary) -> void:
	var total := plan.size()
	for i in total:
		if should_stop.call():
			result.canceled = true
			break
		var entry: Dictionary = plan[i]
		if !_stage(zip, entry, staging):
			result.failed.append(entry.name)
		var mutex: Mutex = job.mutex
		mutex.lock()
		job.progress.append([float(i + 1) * _PERCENT_DONE / float(total), entry.name, i + 1, total])
		mutex.unlock()


## Moves every staged entry into the target. On the first entry that can't be moved, undoes
## the run: removes the files it moved in, puts back the files they replaced and removes
## the folders it created (when empty). Returns {failed: the entry that stopped it, reason:
## why, saying so when the undo itself failed and where the replaced files were kept}.
static func _commit(plan: Array, staging: String, target: String, may_overwrite: bool) -> Dictionary:
	var outcome := {'failed': PackedStringArray(), 'reason': ''}
	var backup_dir := staging + _BACKUP_SUFFIX
	var done := {'dirs': [], 'moved': [], 'backups': {}}
	var created_dirs: Array = done.dirs
	if !_make_dirs(target, created_dirs):
		outcome.reason = 'could not create %s' % target
		_roll_back(done)
		return outcome
	for entry: Dictionary in plan:
		if !_move_into_place(entry, staging, target, may_overwrite, backup_dir, done):
			outcome.failed.append(entry.name)
			break
	if outcome.failed.is_empty():
		LFFile.remove_recursive(backup_dir)
		return outcome
	var not_undone := _roll_back(done)
	if not_undone.is_empty():
		LFFile.remove_recursive(backup_dir)
		outcome.reason = 'could not move %s into place; everything moved before it was undone' % outcome.failed[0]
	else:
		outcome.reason = 'could not move %s into place, and could not undo %s; replaced files are kept in %s' \
				% [outcome.failed[0], ', '.join(not_undone), backup_dir]
	return outcome


## Creates `dir` and any missing parents, recording each one it created (outermost first)
## in `created`. Returns whether `dir` exists afterwards.
static func _make_dirs(dir: String, created: Array) -> bool:
	var missing: Array[String] = []
	var walk := dir
	while !DirAccess.dir_exists_absolute(walk) and walk != walk.get_base_dir():
		missing.push_front(walk)
		walk = walk.get_base_dir()
	for path in missing:
		if FileAccess.file_exists(path) or DirAccess.make_dir_absolute(path) != OK:
			return false
		created.append(path)
	return DirAccess.dir_exists_absolute(dir)


## Undoes a partial commit: removes moved-in files, restores replaced ones from their
## backups, then removes created folders that are empty again. Returns the paths it could
## not undo.
static func _roll_back(done: Dictionary) -> PackedStringArray:
	var not_undone := PackedStringArray()
	var moved: Array = done.moved
	for i in range(moved.size() - 1, -1, -1):
		var moved_path: String = moved[i]
		if DirAccess.remove_absolute(moved_path) != OK:
			not_undone.append(moved_path)
	var backups: Dictionary = done.backups
	for dest: String in backups:
		var backup: String = backups[dest]
		if DirAccess.rename_absolute(backup, dest) != OK:
			not_undone.append(dest)
	var dirs: Array = done.dirs
	for i in range(dirs.size() - 1, -1, -1):
		var dir_path: String = dirs[i]
		DirAccess.remove_absolute(dir_path) # a folder something else wrote into stays
	return not_undone


## Checks every entry before anything is decompressed; returns one {name, size, is_dir,
## dest} per entry in archive order, or null (with result's reason/failed set) to refuse.
static func _plan(names: PackedStringArray, sizes: Dictionary, job: Dictionary, result: Dictionary) -> Variant:
	var entry_limit: int = job.max_entries
	if entry_limit > 0 and names.size() > entry_limit:
		result.reason = 'archive has %d entries, over max_entries %d' % [names.size(), entry_limit]
		return null
	if names.size() != sizes.size():
		result.reason = 'the archive lists %d entries but its directory %d' % [names.size(), sizes.size()]
		return null
	var max_entry: int = job.max_entry_bytes
	var plan := []
	var total_bytes := 0
	# Destinations already claimed by a file entry: two names that resolve to one file
	# ("x.txt" and "/x.txt", or "A.txt" and "a.txt" on a case-insensitive disk) are as
	# ambiguous as a file listed twice. Compared lower-cased, so every disk agrees.
	var file_dests := {}
	# Folders the entries need (each entry's parents, and a directory entry itself),
	# lower-cased: a file entry at one of them ("f" beside "f/g") can't be both.
	var dir_dests := {}
	var target: String = job.target
	var may_overwrite: bool = job.overwrite
	var root := LFFile.to_absolute(target)
	for name in names:
		var size: int = sizes.get(name, -1)
		var is_dir := name.ends_with(_DIR_SUFFIX)
		var dest := LFFile.join_inside(target, name, true)
		var ok := size >= 0 and dest != '' and (max_entry <= 0 or size <= max_entry)
		if ok and !is_dir and DirAccess.dir_exists_absolute(dest):
			ok = false
		if ok and !is_dir and !may_overwrite and FileAccess.file_exists(dest):
			ok = false
		if ok and is_dir and FileAccess.file_exists(dest):
			ok = false
		if ok and !is_dir:
			ok = !file_dests.has(dest.to_lower())
			file_dests[dest.to_lower()] = true
		if !ok:
			result.failed.append(name)
		elif dest != '':
			var folder := dest if is_dir else dest.get_base_dir()
			while folder.length() > root.length():
				dir_dests[folder.to_lower()] = true
				folder = folder.get_base_dir()
		# Saturating: sizes up to 2^63 - 1 can be declared, and a wrapped sum would pass the limit.
		if size > 0:
			total_bytes = total_bytes + size if total_bytes <= _INT_MAX - size else _INT_MAX
		plan.append({'name': name, 'size': size, 'is_dir': is_dir, 'dest': dest})
	for entry: Dictionary in plan:
		var entry_name: String = entry.name
		if !entry.is_dir and dir_dests.has(String(entry.dest).to_lower()) and !result.failed.has(entry_name):
			result.failed.append(entry_name)
	var max_total: int = job.max_total_bytes
	if max_total > 0 and total_bytes > max_total:
		result.reason = 'entries total %d bytes, over max_total_bytes %d' % [total_bytes, max_total]
	if !result.failed.is_empty() or result.reason != '':
		return null
	return plan


## Decompresses one entry into the staging folder; false when the engine reports it
## corrupt (a CRC mismatch), it is shorter than declared, or it can't be written. The engine
## reads only the declared size, so longer content is cut there, not refused.
static func _stage(zip: ZIPReader, entry: Dictionary, staging: String) -> bool:
	var entry_name: String = entry.name
	var staged := LFFile.join_inside(staging, entry_name, true)
	if staged == '':
		return false
	if entry.is_dir:
		return DirAccess.make_dir_recursive_absolute(staged) == OK
	var bytes := zip.read_file(entry_name)
	if bytes.size() != entry.size:
		return false
	return LFFile.save_bytes(staged, bytes)


## Moves one staged entry to its place in the target, checking the path again first. A
## file it replaces is first moved into `backup_dir`; folders it creates, files it moves
## in and backups are recorded in `done` for _roll_back.
static func _move_into_place(entry: Dictionary, staging: String, target: String, may_overwrite: bool,
		backup_dir: String, done: Dictionary) -> bool:
	var entry_name: String = entry.name
	var created_dirs: Array = done.dirs
	var dest := LFFile.join_inside(target, entry_name, true)
	if dest == '':
		return false
	if entry.is_dir:
		return _make_dirs(dest, created_dirs)
	if !_make_dirs(dest.get_base_dir(), created_dirs) or DirAccess.dir_exists_absolute(dest):
		return false
	var staged := LFFile.join_inside(staging, entry_name, true)
	if staged == '' or !FileAccess.file_exists(staged):
		return false
	if FileAccess.file_exists(dest):
		if !may_overwrite:
			return false
		var backup := backup_dir.path_join(str(done.backups.size()))
		if DirAccess.make_dir_recursive_absolute(backup_dir) != OK or DirAccess.rename_absolute(dest, backup) != OK:
			return false
		done.backups[dest] = backup
	if DirAccess.rename_absolute(staged, dest) != OK:
		return false
	done.moved.append(dest)
	return true


## Reads the archive's central directory: {'sizes': {entry name: declared uncompressed
## bytes}} or {'error': why it can't be trusted}. Only the directory itself is read, so
## a lying archive costs at most its own size.
static func _declared_sizes(zip_path: String) -> Dictionary:
	var f := FileAccess.open(zip_path, FileAccess.READ)
	if f == null:
		return {'error': 'it could not be opened'}
	var length := f.get_length()
	if length < _EOCD_SIZE:
		return {'error': 'it is not a zip archive'}
	var tail_length := mini(length, _EOCD_SIZE + _EOCD_MAX_COMMENT)
	f.seek(length - tail_length)
	var tail := f.get_buffer(tail_length)
	var eocd := -1
	for i in range(tail_length - _EOCD_SIZE, -1, -1):
		if tail.decode_u32(i) == _EOCD:
			eocd = i
			break
	if eocd < 0:
		return {'error': 'it has no central directory'}

	var located := _locate_directory(f, tail, eocd, length - tail_length + eocd)
	if located.has('error'):
		return located
	var dir_offset: int = located.offset
	var dir_size: int = located.size
	var count: int = located.count
	f.seek(dir_offset)
	var directory := f.get_buffer(dir_size)
	return _read_central_directory(directory, count)


## Where the central directory is: {'count', 'size', 'offset'} or {'error': why it can't
## be trusted}. `tail` is the end of the file, `eocd` the end record's index in it and
## `dir_end` the file offset where that record starts. `f` is left positioned anywhere.
##
## ZIPReader (minizip) must read the very directory read here, or the declared sizes
## checked later say nothing about what it will decompress: a zip64 locator anywhere in
## the tail must be the one right before the end record (and is then always followed), and
## the directory must end exactly where its end record starts (no bytes before the archive).
static func _locate_directory(f: FileAccess, tail: PackedByteArray, eocd: int, dir_end: int) -> Dictionary:
	var length := f.get_length()
	var locators := 0
	for i in range(0, tail.size() - _ZIP64_LOCATOR_SIZE + 1):
		if tail.decode_u32(i) == _ZIP64_LOCATOR:
			locators += 1
	var count: int = tail.decode_u16(eocd + _EOCD_COUNT_OFFSET)
	var dir_size: int = tail.decode_u32(eocd + _EOCD_DIR_SIZE_OFFSET)
	var dir_offset: int = tail.decode_u32(eocd + _EOCD_DIR_OFFSET_OFFSET)
	var locator := eocd - _ZIP64_LOCATOR_SIZE
	var has_locator := locator >= 0 and tail.decode_u32(locator) == _ZIP64_LOCATOR
	if locators > (1 if has_locator else 0):
		return {'error': 'its zip64 locator is ambiguous'}
	if has_locator or count == _U16_MAX or dir_size == _U32_MAX or dir_offset == _U32_MAX:
		if !has_locator:
			return {'error': 'its zip64 directory is missing'}
		var record_offset: int = tail.decode_u64(locator + _ZIP64_LOCATOR_RECORD_OFFSET)
		# Compared against what is left, never by adding: two 64-bit fields can overflow a sum.
		if record_offset < 0 or record_offset > length - _ZIP64_EOCD_SIZE:
			return {'error': 'its zip64 directory is out of range'}
		f.seek(record_offset)
		var record := f.get_buffer(_ZIP64_EOCD_SIZE)
		if record.decode_u32(0) != _ZIP64_EOCD:
			return {'error': 'its zip64 directory is corrupt'}
		count = record.decode_u64(_ZIP64_EOCD_COUNT_OFFSET)
		dir_size = record.decode_u64(_ZIP64_EOCD_DIR_SIZE_OFFSET)
		dir_offset = record.decode_u64(_ZIP64_EOCD_DIR_OFFSET_OFFSET)
		dir_end = record_offset
	if dir_offset < 0 or dir_size < 0 or dir_offset > length or dir_size > length - dir_offset:
		return {'error': 'its central directory is out of range'}
	if dir_offset + dir_size != dir_end:
		return {'error': 'its central directory does not end where its end record starts (data before the archive?)'}
	return {'count': count, 'size': dir_size, 'offset': dir_offset}


## {'sizes': {entry name: declared uncompressed bytes}} from the `count` headers of a
## central directory, or {'error': why it is corrupt or lists a file twice}.
static func _read_central_directory(directory: PackedByteArray, count: int) -> Dictionary:
	var sizes := {}
	var pos := 0
	for n in count:
		if pos + _CENTRAL_HEADER_SIZE > directory.size() or directory.decode_u32(pos) != _CENTRAL_HEADER:
			return {'error': 'its central directory is corrupt'}
		var size: int = directory.decode_u32(pos + _CENTRAL_UNCOMPRESSED_SIZE_OFFSET)
		var name_length: int = directory.decode_u16(pos + _CENTRAL_NAME_LENGTH_OFFSET)
		var extra_length: int = directory.decode_u16(pos + _CENTRAL_EXTRA_LENGTH_OFFSET)
		var comment_length: int = directory.decode_u16(pos + _CENTRAL_COMMENT_LENGTH_OFFSET)
		var name_start := pos + _CENTRAL_HEADER_SIZE
		var extra_start := name_start + name_length
		var next := extra_start + extra_length + comment_length
		if next > directory.size():
			return {'error': 'its central directory is corrupt'}
		if size == _U32_MAX:
			size = _zip64_size(directory, extra_start, extra_length)
			if size < 0:
				return {'error': 'an entry lacks its zip64 size'}
		var name := LFText.decode_utf8_lossy(directory.slice(name_start, extra_start))
		pos = next
		if sizes.has(name):
			if name.ends_with(_DIR_SUFFIX):
				continue
			return {'error': 'it lists %s more than once' % name}
		sizes[name] = size
	return {'sizes': sizes}


## The uncompressed size from an entry's zip64 extra field, or -1 when it has none, or has
## more than one (ZIPReader would use the last, this reads the first).
static func _zip64_size(directory: PackedByteArray, extra_start: int, extra_length: int) -> int:
	var pos := extra_start
	var extra_end := extra_start + extra_length
	var size := -1
	var blocks := 0
	while pos + _EXTRA_HEADER_SIZE <= extra_end:
		var id: int = directory.decode_u16(pos)
		var block_size: int = directory.decode_u16(pos + _EXTRA_SIZE_OFFSET)
		if id == _ZIP64_EXTRA_ID:
			blocks += 1
			if block_size >= _U64_SIZE and pos + _EXTRA_HEADER_SIZE + _U64_SIZE <= extra_end:
				size = directory.decode_u64(pos + _EXTRA_HEADER_SIZE)
		pos += _EXTRA_HEADER_SIZE + block_size
	return size if blocks == 1 else -1
