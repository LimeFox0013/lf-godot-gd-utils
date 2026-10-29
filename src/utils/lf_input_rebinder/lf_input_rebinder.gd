## Lets the player reassign the keys and pad buttons of input actions, and keeps the choice between runs.
##
## It works on the project's `InputMap`: every action it tracks has a keyboard binding and a pad
## binding, and `rebind` replaces one of them. The code that reads `Input.is_action_pressed` does not
## change. It remembers the bindings the project started with (for `reset`), saves the changes to a
## file and applies them again with `load_saved`.
class_name LFInputRebinder
extends RefCounted

## What kind of device an event comes from.
enum Kind {
	KEYBOARD,
	PAD,
}

## How far a stick must be pushed to count as a binding.
const AXIS_THRESHOLD := 0.6
## The file's version, so a later format can tell an old file.
const FILE_VERSION := 1

## Where the bindings are saved.
var path: String
## The actions it looks after, in the order they were given.
var actions: Array[StringName] = []

var _defaults := {}
var _log := LFLogger.new(["LFInputRebinder"])


## Looks after `tracked_actions` (they must exist in the `InputMap`), saving to `save_path`. The bindings
## the actions have now are the defaults `reset` returns to.
func _init(save_path: String, tracked_actions: Array) -> void:
	path = save_path
	for action in tracked_actions:
		if not InputMap.has_action(action):
			_log.warning("no such action: %s" % action)
			continue
		actions.append(StringName(action))
		_defaults[StringName(action)] = _copies(InputMap.action_get_events(action))


## The kind of device of `event`, or -1 when it is neither a key nor a pad button or stick.
static func kind_of(event: InputEvent) -> int:
	if event is InputEventKey:
		return Kind.KEYBOARD
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return Kind.PAD
	return -1


## Whether `event` is a press the player can bind: a key going down (not repeating), a pad button going
## down, a stick pushed far enough.
static func is_bindable(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and _key_of(event) != KEY_NONE
	if event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventJoypadMotion:
		return absf(event.axis_value) >= AXIS_THRESHOLD
	return false


## Whether two events are the same binding: the same physical key, pad button, or stick direction.
static func same(first: InputEvent, second: InputEvent) -> bool:
	if first is InputEventKey and second is InputEventKey:
		return _key_of(first) == _key_of(second)
	if first is InputEventJoypadButton and second is InputEventJoypadButton:
		return first.button_index == second.button_index
	if first is InputEventJoypadMotion and second is InputEventJoypadMotion:
		return first.axis == second.axis and signf(first.axis_value) == signf(second.axis_value)
	return false


## A short name for `event` for a button label: "A", "Space", "Stick Left".
static func describe(event: InputEvent, style: LFInputKeys.PadStyle = LFInputKeys.PadStyle.XBOX) -> String:
	if event is InputEventKey:
		return LFInputKeys.key_name(_key_of(event))
	if event is InputEventJoypadButton:
		return LFInputKeys.joy_button_name(event.button_index, style)
	if event is InputEventJoypadMotion:
		var direction := signf(event.axis_value)
		if event.axis == JOY_AXIS_LEFT_X:
			return "Stick Left" if direction < 0.0 else "Stick Right"
		if event.axis == JOY_AXIS_LEFT_Y:
			return "Stick Up" if direction < 0.0 else "Stick Down"
		return "Axis %d%s" % [event.axis, "-" if direction < 0.0 else "+"]
	return "?"


## The bindings of `action` of one kind; empty (and a warning is logged) when `action` is not in the `InputMap`.
func events_of(action: StringName, kind: Kind) -> Array:
	var found := []
	if not InputMap.has_action(action):
		_log.warning("no such action: %s" % action)
		return found
	for event in InputMap.action_get_events(action):
		if kind_of(event) == kind:
			found.append(event)
	return found


## The names of the bindings of `action` of one kind, joined ("A / D-pad Up"); "-" when it has none (also for an action that is not in the `InputMap`, which logs a warning).
func label_of(action: StringName, kind: Kind, style: LFInputKeys.PadStyle = LFInputKeys.PadStyle.XBOX) -> String:
	var names := []
	for event in events_of(action, kind):
		names.append(describe(event, style))
	return " / ".join(names) if not names.is_empty() else "-"


## Makes `event` the binding of `action` for its kind, in place of the ones it had. An action that
## used `event` takes what `action` had before (a swap), or stays without a binding if `action` had none.
## Returns the actions that were changed by the swap. A tracked action that is not known, or an event
## that cannot be bound, changes nothing.
func rebind(action: StringName, event: InputEvent) -> Array[StringName]:
	var changed: Array[StringName] = []
	if not actions.has(action) or not is_bindable(event):
		return changed
	var kind := kind_of(event) as Kind
	var chosen := _normalised(event)
	var previous := events_of(action, kind)
	for other in actions:
		if other == action:
			continue
		var kept := []
		var lost := false
		for existing in events_of(other, kind):
			if same(existing, chosen):
				lost = true
			else:
				kept.append(existing)
		if lost:
			kept.append_array(_copies(previous))
			_set_events(other, kind, kept)
			changed.append(other)
	_set_events(action, kind, [chosen])
	return changed


## Returns `action` (every tracked action when empty) to the bindings the project started with.
func reset(action: StringName = &"") -> void:
	for each in actions:
		if action != &"" and action != each:
			continue
		if not InputMap.has_action(each):
			_log.warning("no such action: %s" % each)
			continue
		InputMap.action_erase_events(each)
		for event in _defaults[each]:
			InputMap.action_add_event(each, event.duplicate())


## Writes the bindings of every tracked action to `path`. False (and a logged error) when the file
## cannot be written.
func save() -> bool:
	var data := {}
	for action in actions:
		if not InputMap.has_action(action):
			_log.warning("no such action: %s" % action)
			continue
		data[str(action)] = []
		for event in InputMap.action_get_events(action):
			var entry := _to_entry(event)
			if not entry.is_empty():
				data[str(action)].append(entry)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_log.error("cannot write %s" % path)
		return false
	file.store_string(JSON.stringify({"version": FILE_VERSION, "bindings": data}))
	return true


## Applies the saved bindings. False when there is no file or it is not readable (nothing changes then);
## an action missing from the file keeps what it has.
func load_saved() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var json := JSON.new()
	var parsed = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not (parsed is Dictionary) or not (parsed.get("bindings") is Dictionary):
		_log.warning("unreadable bindings in %s" % path)
		return false
	for action in actions:
		if not InputMap.has_action(action):
			_log.warning("no such action: %s" % action)
			continue
		var entries = parsed.bindings.get(str(action))
		if not (entries is Array):
			continue
		var events := []
		for entry in entries:
			var event := _from_entry(entry)
			if event:
				events.append(event)
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for event in events:
			InputMap.action_add_event(action, event)
	return true


func _set_events(action: StringName, kind: Kind, kind_events: Array) -> void:
	var all := []
	for event in InputMap.action_get_events(action):
		if kind_of(event) != kind:
			all.append(event)
	all.append_array(kind_events)
	InputMap.action_erase_events(action)
	for event in all:
		InputMap.action_add_event(action, event)


## What is stored for a binding: no modifiers, no device, the stick pushed fully.
func _normalised(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key := InputEventKey.new()
		key.physical_keycode = _key_of(event)
		return key
	if event is InputEventJoypadButton:
		var button := InputEventJoypadButton.new()
		button.button_index = event.button_index
		return button
	var motion := InputEventJoypadMotion.new()
	motion.axis = event.axis
	motion.axis_value = signf(event.axis_value)
	return motion


func _to_entry(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "code": _key_of(event)}
	if event is InputEventJoypadButton:
		return {"type": "button", "index": event.button_index}
	if event is InputEventJoypadMotion:
		return {"type": "stick", "axis": event.axis, "value": signf(event.axis_value)}
	return {}


func _from_entry(entry) -> InputEvent:
	if not (entry is Dictionary):
		return null
	var event: InputEvent = null
	if entry.get("type") == "key" and entry.has("code"):
		event = InputEventKey.new()
		event.physical_keycode = int(entry.code)
	elif entry.get("type") == "button" and entry.has("index"):
		event = InputEventJoypadButton.new()
		event.button_index = int(entry.index)
	elif entry.get("type") == "stick" and entry.has("axis") and entry.has("value"):
		event = InputEventJoypadMotion.new()
		event.axis = int(entry.axis)
		event.axis_value = signf(float(entry.value))
	return event


static func _key_of(event: InputEventKey) -> Key:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode


func _copies(events: Array) -> Array:
	var copies := []
	for event in events:
		copies.append(event.duplicate())
	return copies
