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


## `kind_names`: `{kind: wire name}`. `required`: `{kind: [payload keys]}`; a kind not listed needs none.
func _init(kind_names: Dictionary, required := {}) -> void:
	_names = kind_names
	_kinds = LFDictionary.invert(kind_names)
	_required = required


## `{type: <wire name of kind>, payload: payload}`.
func encode(kind: Variant, payload: Dictionary = {}) -> Dictionary:
	return {'type': _names.get(kind, ''), 'payload': payload}


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
