## Turns typed messages into `{type, payload}` dictionaries and back, rejecting malformed ones.
##
## You give it the message kinds (an enum value for each wire name) and the payload keys each
## kind must carry. `decode` never throws: a message from an untrusted peer that is unknown or
## incomplete comes back as null. Checks beyond required keys stay with the caller.
class_name LFWireMessage
extends RefCounted

var _names: Dictionary
var _kinds: Dictionary
var _required: Dictionary
var _once_has := false
var _once_kind: Variant = null
var _once_payload: Variant = null
var _once_text := ''


## `kind_names`: `{kind: wire name}`. `required`: `{kind: [payload keys]}`; a kind not listed needs none.
func _init(kind_names: Dictionary, required := {}) -> void:
	_names = kind_names
	_kinds = LFDictionary.invert(kind_names)
	_required = required


## `{type: <wire name of kind>, payload: payload}`.
func encode(kind: Variant, payload: Dictionary = {}) -> Dictionary:
	return {'type': _names.get(kind, ''), 'payload': payload}


## `encode(kind, payload)` as JSON text, kept: asking again with the very same `payload`
## object (not an equal copy) and `kind` returns the kept text without encoding again. For a
## message sent to many peers; do not change the object in between.
func encode_text_once(kind: Variant, payload: Dictionary) -> String:
	if not (_once_has and is_same(payload, _once_payload) and kind == _once_kind):
		_once_text = JSON.stringify(encode(kind, payload))
		_once_payload = payload
		_once_kind = kind
		_once_has = true
	return _once_text


## The JSON text of `encode(kind, payload)` with `field` taken out of `payload` and its
## already encoded `field_text` put last, so a big field shared by many messages is encoded
## once. It parses to the same message; only the key order differs. `payload` is not changed.
func splice_text(kind: Variant, payload: Dictionary, field: String, field_text: String) -> String:
	var rest := payload.duplicate()
	rest.erase(field)
	var rest_text := JSON.stringify(rest)
	var separator := '' if rest.is_empty() else ','
	return '{"type":%s,"payload":%s%s%s:%s}}' % [
		JSON.stringify(_names.get(kind, '')), rest_text.left(-1), separator, JSON.stringify(field), field_text,
	]


## `{kind, payload}` for a known type whose payload is a Dictionary holding the required keys;
## null otherwise. A missing payload counts as `{}`.
func decode(message: Dictionary) -> Variant:
	var type: Variant = message.get('type')
	if type == null or not _kinds.has(type):
		return null
	var kind: Variant = _kinds[type]
	var payload: Variant = message.get('payload', {})
	if not payload is Dictionary or not payload.has_all(_required.get(kind, [])):
		return null
	return {'kind': kind, 'payload': payload}
