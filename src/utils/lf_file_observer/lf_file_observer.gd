## Keeps a value in sync with a file: read [member data] to load it, change it to save it.
##
## The file is loaded lazily (on the first read of [member data]) and every change is
## written straight to the file (replace-by-rename, via [method LFFile.save]), then
## [signal saved] is emitted. Optional transforms convert file text <-> data. A write
## that fails changes nothing in memory. A file that exists but can't be read is not
## overwritten, and every write first checks whether another writer changed the file
## since this observer read it: [method edit] then re-reads and re-applies, a whole
## [member data] replacement is refused. The check and the write are separate steps, so
## two writes in the same instant can still race. For a JSON object file, use
## [LFJsonFileObserver].
class_name LFFileObserver
extends RefCounted

static var _log := LFLogger.new()

## Emitted after every successful write.
signal saved

var _path: String
var _transform_out: Callable = func(text: Variant) -> Variant: return text
var _transform_in: Callable = func(value: Variant) -> Variant: return value

var _data: Variant
var _loaded := false
## The file's text as this observer last read or wrote it; null when unknown (the file
## could not be read, or its content could not be kept), which blocks writes.
var _disk_text: Variant = null

## The file's content after transform_out (loaded on first read; a missing file reads
## as "" and is not created). This is the cached value itself: change it through `edit`
## or by assigning a new value, never in place. Assigning saves transform_in(new_data)
## and, only when that save succeeds, caches it and emits `saved`. The assignment is
## refused (with a pushed error) when the file changed on disk since it was read.
var data: Variant:
	get():
		_ensure_loaded()
		return _data
	set(new_data):
		_commit(func(_current: Variant) -> Variant: return new_data, false)


## Observes [param file_path]. [param transform_out] turns the file's text into data on
## load; [param transform_in] turns data into text on save and must return a String. Both
## default to passing the value through unchanged (data is the file's text). A transform that refers to this observer (a lambda using
## `self` or one of its members) keeps it alive forever — pass a method of another
## object or a lambda that captures nothing of this one.
func _init(
	file_path: String = '',
	transform_out: Callable = _transform_out,
	transform_in: Callable = _transform_in,
) -> void:
	_transform_out = transform_out
	_transform_in = transform_in
	_path = file_path


## Applies `change` to the current data and writes the result once. `change` receives a
## deep copy of the data and returns the new data. When the file changed on disk since
## it was read, it is re-read first and `change` applies to that content. Returns
## whether the result was written; a refusal pushes an error and changes nothing.
## `change` must not call back into this observer: an inner write would be overwritten
## by the outer result.
func edit(change: Callable) -> bool:
	return _commit(change, true)


## Re-reads the file, replacing the cached data (`saved` is not emitted). Returns false
## when the file exists but could not be read; the data then reads as for an empty file
## and writes stay blocked until a later read succeeds.
func reload() -> bool:
	_apply_read(LFFile.read_text(_path))
	return _disk_text != null


## Turns file text into data.
func _decode(text: String) -> Variant:
	return _transform_out.call(text)


## Turns data into file text; a result other than a String refuses the write.
func _encode(value: Variant) -> Variant:
	return _transform_in.call(value)


func _ensure_loaded() -> void:
	if !_loaded:
		reload()


func _apply_read(read: LFFile.TextRead) -> void:
	_loaded = true
	if read.error == OK or read.error == ERR_FILE_NOT_FOUND:
		_disk_text = read.text
		_data = _decode(read.text)
		return
	_log.error('LFFileObserver: could not read %s (err=%s); it will not be overwritten' % [_path, read.error])
	_disk_text = null
	_data = _decode('')


func _commit(change: Callable, reapply: bool) -> bool:
	var read := LFFile.read_text(_path)
	if read.error != OK and read.error != ERR_FILE_NOT_FOUND:
		_log.error('LFFileObserver: could not read %s (err=%s); nothing was written' % [_path, read.error])
		return false
	if !_loaded:
		_apply_read(read)
	elif _disk_text == null or read.text != _disk_text:
		if !reapply:
			_log.error('LFFileObserver: %s changed on disk since it was read; call reload() or use edit()' % _path)
			return false
		_apply_read(read)
	if _disk_text == null:
		_log.error('LFFileObserver: %s is not written while its content could not be kept' % _path)
		return false

	var new_data: Variant = change.call(_copy(_data))
	var text: Variant = _encode(new_data)
	if !(text is String):
		_log.error('LFFileObserver: %s cannot store this value (it is not text after transform_in); nothing was written' % _path)
		return false
	if !LFFile.save(_path, text):
		_log.error('LFFileObserver: could not save %s; the value is unchanged' % _path)
		return false
	_data = new_data
	_disk_text = text
	saved.emit()
	return true


static func _copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
