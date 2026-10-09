## Keeps a Dictionary in sync with a JSON file, e.g. a configuration file.
##
## A [LFFileObserver] whose [member LFFileObserver.data] is a Dictionary stored as JSON.
## Dotted-path helpers read and change nested keys: "audio.volume" means
## `data["audio"]["volume"]`. Every change is written to the file at once; one whose
## write fails is not kept.
class_name LFJsonFileObserver
extends LFFileObserver

## Tag of a corrupt file's backup: `<file>.corrupt-<unix time>` (see LFFile.move_aside).
const _CORRUPT_TAG := 'corrupt'


## Observes the JSON file at file_path. Missing, empty or whitespace-only content loads as {}. Content
## that is not a JSON object (unparseable, or e.g. an array; a file of control bytes such as
## zero bytes counts as unparseable, not as empty) is first moved aside to
## `<file>.corrupt-<unix time>` with a pushed warning, then loads as {} — so no write
## ever destroys it, and later observers find no corrupt file to back up again. When
## it can't be moved aside, writes are refused.
func _init(file_path: String = '') -> void:
	super._init(file_path)


## Sets the value at a dotted props_path (e.g. "a.b") and saves it (see edit).
## Returns whether it was written.
func set_by_path(props_path: String, value: Variant) -> bool:
	return edit(func(d: Dictionary) -> Dictionary: return LFDictionary.set_by_path(d, props_path, value))


## Erases the value at a dotted props_path and saves it (see edit); a missing path
## leaves the rest as it was. Returns whether it was written.
func erase_by_path(props_path: String) -> bool:
	return edit(func(d: Dictionary) -> Dictionary: return LFDictionary.erase_by_path(d, props_path))


## A copy of the value at a dotted props_path, or fallback_value when it is null or
## missing (a stored 0, false, "" or empty container is returned as it is).
func get_by_path(props_path: String, fallback_value: Variant = null) -> Variant:
	var value: Variant = LFDictionary.get_by_path(data, props_path)
	return LFFileObserver._copy(value) if value != null else fallback_value


func _decode(text: String) -> Variant:
	if text.strip_edges() == '' and LFFile.is_blank(_path):
		return {}
	var parsed: Variant = LFJson.parse_object(text)
	if parsed != null:
		return parsed
	_set_aside_corrupt()
	return {}


func _encode(value: Variant) -> Variant:
	if !(value is Dictionary):
		return null # not a JSON object: refused
	return JSON.stringify(value)


## Moves the corrupt file to a `.corrupt-<unix time>` sibling and warns. When it can't be
## moved, the content is unknown to this observer, so writes stay blocked.
func _set_aside_corrupt() -> void:
	var backup := LFFile.move_aside(_path, _CORRUPT_TAG)
	if backup != '':
		_log.warning('LFJsonFileObserver: %s is not a JSON object; moved it to %s and started fresh' % [_path, backup])
		_disk_text = ''
	else:
		_log.warning('LFJsonFileObserver: %s is not a JSON object and could not be moved aside; it will not be overwritten' % _path)
		_disk_text = null
