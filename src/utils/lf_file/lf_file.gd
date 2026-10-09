## Saves, loads, copies and deletes files and folders on any kind of path.
##
## Accepts res:// (the project), user:// (the app's user-data folder), absolute and relative
## paths, and resolves them to one absolute OS path before saving, checking, copying or
## removing. Loading reads res:// and user:// natively ([method readable_path]), so it also
## works inside an exported project's pack. Saves are atomic: the new content is written
## beside the file, checked, then renamed over it, so the game crashing mid-save leaves the
## old content (on Windows, see save). Nothing is forced to the disk, so a power loss right
## after a save is not covered. All methods are static: call them on the class, e.g.
## `LFFile.save_json("user://data.json", data)`.
class_name LFFile


## Log line prefix.
const _LOG_PREFIX := "[LFFile]"
## Scheme of project paths; alone, the project root.
const _RES_ROOT := 'res://'
## Scheme of user-data paths.
const _USER_ROOT := 'user://'
## Ends a path scheme ("res://", "user://").
const _SCHEME_SEPARATOR := '://'
## The path separator every path is normalized to.
const _SEPARATOR := '/'
## The Windows path separator, turned into _SEPARATOR.
const _BACKSLASH := '\\'
## The parent-directory path segment.
const _PARENT_DIR := '..'
## OS feature tag present when running from the editor.
const _FEATURE_EDITOR := 'editor'
## Temporary file name: process id, thread id, time in microseconds, counter. A fixed
## length, so it fits wherever the file it stands in for does.
const _TEMP_NAME_FORMAT := '.lf-tmp-%d-%d-%d-%d'
## Separates a Windows drive letter from the rest of the path.
const _DRIVE_SEPARATOR := ':'
## The current-directory path segment, and the separator before a file extension.
const _CURRENT_DIR := '.'
## A space, which Windows drops from the end of a file name.
const _SPACE := ' '
## File names Windows reserves for devices, with or without an extension.
const _RESERVED_DEVICE_NAMES: Array[String] = [
	'CON', 'PRN', 'AUX', 'NUL',
	'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
	'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
]
## Name of a file moved aside: path, tag, unix time in seconds.
const _ASIDE_FORMAT := '%s.%s-%d'
## A further aside name when that one is taken: the base name, then a counter.
const _ASIDE_TAKEN_FORMAT := '%s-%d'
## Length of the shortest Windows absolute path: drive letter, colon, slash ("C:/").
const _WINDOWS_ROOT_LENGTH := 3
## `OS.get_name()` on Windows.
const _WINDOWS_OS_NAME := 'Windows'
## Code point of 'A', the first upper-case drive letter.
const _ASCII_UPPER_A := 65
## Code point of 'Z', the last upper-case drive letter.
const _ASCII_UPPER_Z := 90
## Code point of 'a', the first lower-case drive letter.
const _ASCII_LOWER_A := 97
## Code point of 'z', the last lower-case drive letter.
const _ASCII_LOWER_Z := 122

static var _log := LFLogger.new([_LOG_PREFIX])
## Makes temporary names unique within one process.
static var _temp_counter := 0
## `OS.get_name()` value of the system `join_inside` applies its rule for; "" (the
## default) means the system this runs on. Internal: tests set it to check the Windows
## rule elsewhere.
static var _system_name := ''


## What a path points at, as returned by [method path_leads_to].
enum PathTarget {
	MISSING, ## Nothing exists at the path.
	FILE, ## A file.
	DIR, ## A directory (folder).
}


## The outcome of [method read_text]: the text, or why there is none.
class TextRead:
	## The file's text; "" unless error is OK.
	var text: String = ''
	## OK; ERR_FILE_NOT_FOUND when no file is at the path (nothing, or a directory);
	## ERR_FILE_CANT_READ when a file is there but could not be read; ERR_OUT_OF_MEMORY
	## when it is larger than max_bytes.
	var error: Error = OK


## Writes `content` to `path`, replacing the whole file atomically: written to a
## hidden temporary file in the same folder, checked, then renamed over the file — so a
## failed save, or the process dying mid-save, leaves the previous content intact (on
## Windows the engine removes the old file just before the rename, so a crash in that
## instant leaves the new content only in the temporary file). Not forced to the disk (no
## fsync). A missing file is created (with its directories) only when `ensure_file` is
## true; otherwise nothing is written. A path ending in a slash names a directory and is
## refused. Returns whether the file now holds `content`; a failure pushes an error.
static func save(path: String, content: String, ensure_file := true) -> bool:
	return _save(path, content.to_utf8_buffer(), ensure_file)


## Like save, for binary content.
static func save_bytes(path: String, bytes: PackedByteArray, ensure_file := true) -> bool:
	return _save(path, bytes, ensure_file)


## Saves `value` as a JSON string (see save). Returns whether it was written. JSON is
## lossy: numbers come back as float (and lose precision past 2^53), NaN becomes null,
## and a Vector, Color or Object is written as its String.
static func save_json(path: String, value: Variant) -> bool:
	return LFFile.save(path, JSON.stringify(value))


## Creates the directory a file at `path` would live in. A `path` ending in a slash
## names a directory, so that directory itself is created. Returns OK when it exists.
static func ensure_dir(path: String) -> Error:
	var absolute_path := to_absolute(path) # simplify_path() drops a trailing slash
	var is_dir_path := path.ends_with(_SEPARATOR) or path.ends_with(_BACKSLASH)
	var dir := absolute_path if is_dir_path else absolute_path.get_base_dir()
	if DirAccess.dir_exists_absolute(dir):
		return OK
	return DirAccess.make_dir_recursive_absolute(dir)


## Reads the file's text, telling a missing file from one that exists but can't be
## read. A file larger than `max_bytes` (when above 0) is refused unread. Quiet: bytes
## that are not valid UTF-8 become U+FFFD without an engine error.
static func read_text(path: String, max_bytes := 0) -> TextRead:
	var read := TextRead.new()
	var readable := readable_path(path)
	if !FileAccess.file_exists(readable):
		read.error = ERR_FILE_NOT_FOUND
		return read
	var f := FileAccess.open(readable, FileAccess.READ)
	if f == null:
		read.error = ERR_FILE_CANT_READ
		return read
	if max_bytes > 0 and f.get_length() > max_bytes:
		read.error = ERR_OUT_OF_MEMORY
		return read
	var bytes := f.get_buffer(f.get_length())
	var err := f.get_error()
	if err != OK and err != ERR_FILE_EOF:
		read.error = ERR_FILE_CANT_READ
		return read
	read.text = LFText.decode_utf8_lossy(bytes)
	return read


## Returns the file's text, or "" when it is missing (quietly) or can't be read (with a
## pushed error; read_text tells the two apart). A missing file is first created empty
## only when ensure_file is true.
static func load_file(path: String, ensure_file := false) -> String:
	var read := read_text(path)
	if read.error == OK:
		return read.text
	if read.error != ERR_FILE_NOT_FOUND:
		_log.error("could not read %s (err=%s)" % [readable_path(path), read.error])
		return ''
	# An exported project's res:// is read-only, inside its pack — never create there.
	var packed := readable_path(path).begins_with(_RES_ROOT) and !OS.has_feature(_FEATURE_EDITOR)
	if ensure_file and !packed:
		LFFile.save(path, '')
	return ''


## The file's JSON object, or an empty Dictionary when the file is missing, empty,
## invalid, or holds something other than an object.
static func load_json(path: String, ensure_file := false) -> Dictionary:
	var value: Variant = load_json_value(path, ensure_file)
	return value if value is Dictionary else {}


## The file's parsed JSON value of any kind (Dictionary, Array, number, ...), or null
## when the file is missing, empty or invalid.
static func load_json_value(path: String, ensure_file := false) -> Variant:
	return LFJson.parse(LFFile.load_file(path, ensure_file))


## The path Godot's own file API should open for `input_path`: res:// and user:// paths
## stay as they are (FileAccess reads them natively — in an exported project res:// lives
## inside the pack, where a globalized disk path would not exist), a relative path
## becomes res://-relative, and an absolute path stays absolute. A res:// or user://
## path never resolves outside its root: `..` stops there, and an embedded scheme or drive
## letter after the root (`user://res://../..`) is a plain name.
static func readable_path(input_path: String) -> String:
	var path := _normalize_slashes(input_path.strip_edges())
	if path == '':
		return _RES_ROOT
	if path.begins_with(_RES_ROOT) or path.begins_with(_USER_ROOT):
		return _clamp_scheme_path(path)
	if _is_windows_absolute(path) or path.begins_with(_SEPARATOR):
		return path.simplify_path()
	return _clamp_scheme_path(_RES_ROOT + path)


## Returns whether path is a PathTarget.FILE, DIR or MISSING. res:// is checked through
## its own scheme, so a file inside an exported project's pack counts.
static func path_leads_to(path: String) -> PathTarget:
	var readable := readable_path(path)
	if FileAccess.file_exists(readable):
		return PathTarget.FILE
	if DirAccess.dir_exists_absolute(readable):
		return PathTarget.DIR
	return PathTarget.MISSING


## Whether the file at `path` holds only whitespace bytes (or nothing). Text decoding stops
## at a zero byte, so a file of control bytes reads as "" through `read_text`; this tells it
## from an empty one.
static func is_blank(path: String) -> bool:
	for byte in FileAccess.get_file_as_bytes(readable_path(path)):
		if byte != 32 and (byte < 9 or byte > 13):
			return false
	return true


## True when path leads to an existing file or directory.
static func path_exists(path: String) -> bool:
	return LFFile.path_leads_to(path) != PathTarget.MISSING


## Resolves input_path to a simplified absolute OS path: absolute paths stay as-is,
## res:// and user:// are globalized, relative paths resolve against res://, "" -> res://.
## `..` never climbs above res:// or user://.
static func to_absolute(input_path: String) -> String:
	var path := _normalize_slashes(input_path.strip_edges())
	if _is_windows_absolute(path) or path.begins_with(_SEPARATOR):
		return path.simplify_path()
	return ProjectSettings.globalize_path(readable_path(path)).simplify_path()


## True when `path` is `root` or lies below it, compared as absolute paths after `..`
## is resolved, and no existing entry below `root` on the way to `path` (`path` itself
## included) is a symbolic link, which could lead anywhere. `root` itself may be a link.
## An empty root contains nothing.
static func is_inside(root: String, path: String) -> bool:
	if root.strip_edges() == '':
		return false
	var base := to_absolute(root)
	var target := to_absolute(path)
	var prefix := base if base.ends_with(_SEPARATOR) else base + _SEPARATOR
	if target != base and !target.begins_with(prefix):
		return false
	var walked := base
	for part in target.substr(prefix.length()).split(_SEPARATOR, false):
		walked = walked.path_join(part)
		if _is_link(walked):
			return false
	return true


## `root` joined with the relative `name` (backslashes and `..` resolved, a leading
## slash ignored), or "" when the result would not be inside `root` (see is_inside). Also
## "" when a segment of `name` is not a name Windows can create as written (see
## is_portable_name) and either this runs on Windows (where such a name would open a
## device, an NTFS stream or a different file) or `portable_only` is set. Elsewhere,
## without `portable_only`, a name the system allows (`12:30.log` on Linux or macOS) is kept.
static func join_inside(root: String, name: String, portable_only := false) -> String:
	if root.strip_edges() == '':
		return ''
	if portable_only or _runs_on_windows():
		for segment in _normalize_slashes(name).split(_SEPARATOR, false):
			if segment != _CURRENT_DIR and segment != _PARENT_DIR and !is_portable_name(segment):
				return ''
	var base := to_absolute(root)
	var joined := (base + _SEPARATOR + _normalize_slashes(name)).simplify_path()
	return joined if is_inside(base, joined) else ''


## Whether `join_inside` applies the Windows naming rule by default.
static func _runs_on_windows() -> bool:
	return (_system_name if _system_name != '' else OS.get_name()) == _WINDOWS_OS_NAME


## True when `segment` (one file or folder name, no slashes) can be created on Windows as
## well as elsewhere: it is not empty, holds no `:` (which would name a drive or an NTFS
## alternate data stream), does not end in `.` or a space (Windows drops those, so two
## names would land on one file), and is not a reserved device name (`CON`, `PRN`, `AUX`,
## `NUL`, `COM1`-`COM9`, `LPT1`-`LPT9`, in any case, with or without an extension).
## Other characters Windows refuses (`<>"|?*`, control characters) are not checked here;
## creating such a file fails there instead.
static func is_portable_name(segment: String) -> bool:
	if segment == '' or segment.contains(_DRIVE_SEPARATOR):
		return false
	if segment.ends_with(_CURRENT_DIR) or segment.ends_with(_SPACE):
		return false
	var stem := segment.get_slice(_CURRENT_DIR, 0).strip_edges(false, true).to_upper()
	return !_RESERVED_DEVICE_NAMES.has(stem)


## Moves the file at `path` to a free sibling name, `<file>.<tag>-<unix time>` (with
## `-1`, `-2`... added when that is taken), so its content is kept while a fresh file
## takes its place. Returns the new absolute path, or "" when there is no file at `path`
## or it could not be moved. Quiet: the caller reports the outcome.
static func move_aside(path: String, tag: String) -> String:
	var source := to_absolute(path)
	if !FileAccess.file_exists(source):
		return ''
	var base := _ASIDE_FORMAT % [source, tag, int(Time.get_unix_time_from_system())]
	var aside := base
	var n := 1
	while FileAccess.file_exists(aside) or DirAccess.dir_exists_absolute(aside):
		aside = _ASIDE_TAKEN_FORMAT % [base, n]
		n += 1
	return aside if DirAccess.rename_absolute(source, aside) == OK else ''


## Copies a file into dst_dir_path (created if missing), keeping its name. The copy is
## written beside the destination first and renamed into place, so a failed copy leaves
## an existing destination as it was; copying a file onto itself (through any spelling
## of its directory) is a successful no-op. Returns false with a pushed error on a
## missing source, a file destination, a blocked overwrite or a failed copy.
static func copy_to_dir(src_path: String, dst_dir_path: String, overwrite := true) -> bool:
	var src_abs := to_absolute(src_path)
	if not FileAccess.file_exists(src_abs):
		_log.error("copy_to_dir: Source file does not exist: %s" % src_abs)
		return false
	if FileAccess.open(src_abs, FileAccess.READ) == null:
		_log.error("copy_to_dir: Source file can't be read: %s" % src_abs)
		return false

	var dst_dir_abs := to_absolute(dst_dir_path)
	match path_leads_to(dst_dir_abs):
		PathTarget.FILE:
			_log.error("copy_to_dir: Destination is a file, expected a directory: %s" % dst_dir_abs)
			return false
		PathTarget.MISSING:
			var mk_err := DirAccess.make_dir_recursive_absolute(dst_dir_abs)
			if mk_err != OK:
				_log.error("copy_to_dir: Failed to create directory %s (err=%s)" % [dst_dir_abs, mk_err])
				return false

	var dst_abs := dst_dir_abs.path_join(src_abs.get_file())
	if FileAccess.file_exists(dst_abs):
		if _same_file(src_abs, dst_abs):
			return true
		if not overwrite:
			_log.error("copy_to_dir: File already exists and overwrite=false: %s" % dst_abs)
			return false

	var temp := _temp_sibling(dst_abs)
	var cp_err := DirAccess.copy_absolute(src_abs, temp)
	if cp_err == OK:
		cp_err = DirAccess.rename_absolute(temp, dst_abs)
	if cp_err != OK:
		DirAccess.remove_absolute(temp)
		_log.error("copy_to_dir: Copy failed %s -> %s (err=%s)" % [src_abs, dst_abs, cp_err])
		return false
	return true


## Removes one file, one empty directory or one symbolic link (never what it points
## at). A path where nothing exists is OK; an empty path is refused.
static func remove(path: String) -> Error:
	if path.strip_edges() == '':
		_log.error("remove: refusing an empty path")
		return ERR_INVALID_PARAMETER
	var absolute_path := to_absolute(path)
	if !_is_link(absolute_path) and !FileAccess.file_exists(absolute_path) \
			and !DirAccess.dir_exists_absolute(absolute_path):
		return OK
	return DirAccess.remove_absolute(absolute_path)


## Removes a file, or a directory with everything in it (hidden entries included). A
## symbolic link is removed itself and never followed, so nothing outside the tree is
## touched. A path where nothing exists is OK; an empty path or a filesystem root is
## refused. Stops at the first entry that can't be removed and returns its error.
static func remove_recursive(path: String) -> Error:
	if path.strip_edges() == '':
		_log.error("remove_recursive: refusing an empty path")
		return ERR_INVALID_PARAMETER
	var absolute_path := to_absolute(path)
	if _is_filesystem_root(absolute_path):
		_log.error("remove_recursive: refusing the filesystem root %s" % absolute_path)
		return ERR_INVALID_PARAMETER
	return _remove_tree(absolute_path)


static func _remove_tree(absolute_path: String) -> Error:
	if _is_link(absolute_path) or !DirAccess.dir_exists_absolute(absolute_path):
		return remove(absolute_path)
	var dir := DirAccess.open(absolute_path)
	if dir == null:
		return DirAccess.get_open_error()
	dir.include_hidden = true
	dir.include_navigational = false
	var children: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != '':
		children.append(absolute_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	for child in children:
		var err := _remove_tree(child)
		if err != OK:
			return err
	return DirAccess.remove_absolute(absolute_path)


static func _save(path: String, bytes: PackedByteArray, ensure_file: bool) -> bool:
	if path.ends_with(_SEPARATOR) or path.ends_with(_BACKSLASH):
		_log.error("cannot save %s: a path ending in a slash names a directory" % path)
		return false
	var target := to_absolute(path)
	if !ensure_file and !FileAccess.file_exists(target):
		return false
	if DirAccess.dir_exists_absolute(target):
		_log.error("cannot save %s: it is a directory" % target)
		return false
	var dir_err := ensure_dir(target)
	if dir_err != OK:
		_log.error("cannot save %s: its directory could not be created (err=%s)" % [target, dir_err])
		return false
	var temp := _temp_sibling(target)
	var err := _write_checked(temp, bytes)
	if err == OK:
		err = DirAccess.rename_absolute(temp, target)
	if err != OK:
		DirAccess.remove_absolute(temp)
		_log.error("cannot save %s (err=%s); the previous content is unchanged" % [target, err])
		return false
	return true


## Writes bytes to a new file and confirms every byte reached it.
static func _write_checked(path: String, bytes: PackedByteArray) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var stored := f.store_buffer(bytes)
	f.flush()
	var err := f.get_error()
	f.close()
	if !stored or err != OK:
		return ERR_FILE_CANT_WRITE
	var check := FileAccess.open(path, FileAccess.READ)
	if check == null:
		return ERR_FILE_CANT_WRITE
	var written := check.get_length()
	check.close()
	return OK if written == bytes.size() else ERR_FILE_CANT_WRITE


## A hidden name in `path`'s folder that no other save is using.
static func _temp_sibling(path: String) -> String:
	_temp_counter += 1
	return path.get_base_dir().path_join(_TEMP_NAME_FORMAT % [
		OS.get_process_id(), OS.get_thread_caller_id(), Time.get_ticks_usec(), _temp_counter,
	])


static func _same_file(a: String, b: String) -> bool:
	var dir := DirAccess.open(b.get_base_dir())
	return dir != null and dir.is_equivalent(a, b)


static func _is_link(absolute_path: String) -> bool:
	var dir := DirAccess.open(absolute_path.get_base_dir())
	return dir != null and dir.is_link(absolute_path)


## Resolves a res:// or user:// path segment by segment so it can never leave its root:
## empty segments and segments made only of spaces and at most one dot (`.`, `. `) are
## dropped; `..` and any other segment made only of dots and spaces (`...`, `.. `, which
## Windows trims to `..`) removes the segment before it, and is dropped at the root.
## Everything else is a plain name, including one holding `:` (an embedded `res://` or
## `C:`), so nothing after the scheme can act as a new root.
static func _clamp_scheme_path(path: String) -> String:
	var scheme := path.substr(0, path.find(_SCHEME_SEPARATOR) + _SCHEME_SEPARATOR.length())
	var kept := PackedStringArray()
	for segment in path.substr(scheme.length()).split(_SEPARATOR, false):
		if segment.replace(_CURRENT_DIR, '').replace(_SPACE, '') != '':
			kept.append(segment)
		elif segment.count(_CURRENT_DIR) >= _PARENT_DIR.length() and !kept.is_empty():
			kept.remove_at(kept.size() - 1)
	return scheme + _SEPARATOR.join(kept)


## Whether `absolute_path` is `/` or a bare Windows drive root such as `C:/`.
static func _is_filesystem_root(absolute_path: String) -> bool:
	return absolute_path == _SEPARATOR \
		or (absolute_path.length() == _WINDOWS_ROOT_LENGTH and _is_windows_absolute(absolute_path))


static func _normalize_slashes(p: String) -> String:
	return p.replace(_BACKSLASH, _SEPARATOR)


## Whether `p` is a Windows absolute path such as `C:/...` or `z:/...` (an ASCII letter,
## a colon, then a forward slash).
static func _is_windows_absolute(p: String) -> bool:
	if p.length() < _WINDOWS_ROOT_LENGTH:
		return false
	if p[1] != _DRIVE_SEPARATOR or p[2] != _SEPARATOR:
		return false
	var c := p.unicode_at(0)
	var is_letter := (c >= _ASCII_UPPER_A and c <= _ASCII_UPPER_Z) \
		or (c >= _ASCII_LOWER_A and c <= _ASCII_LOWER_Z)
	return is_letter
