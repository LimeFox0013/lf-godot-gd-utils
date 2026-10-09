## A text display any script can update by id: `LFControlOut.set_prop("status", "Ready")`.
##
## It is an `LFControl` (found by its `registry_id`) holding a Label. Instance
## `lf_control_out.tscn`, which wires `label` to a child Label that fills the control,
## then set `registry_id` in the Inspector.
class_name LFControlOut
extends LFControl

static var _log := LFLogger.new()

## The Label that receives the text written by `set_prop`. The packaged scene wires it to
## its child Label; null (or freed) makes `set_prop` warn and write nothing.
@export var label: Label


## Sets `label.text` to `text` on the LFControlOut registered under `prop_key` (the
## newest live one, found with `LFControl.by_id(prop_key, viewport)`). Does nothing, silently,
## when no control holds that id or the one found is not an LFControlOut; pushes a warning
## and does nothing when the LFControlOut has no `label`.
static func set_prop(prop_key: String, text: String, viewport: Viewport = null) -> void:
	var control: Control = LFControl.by_id(prop_key, viewport)
	if not control is LFControlOut:
		return
	var out: LFControlOut = control
	if not is_instance_valid(out.label):
		_log.warning("LFControlOut.set_prop: '%s' has no label; text not written" % prop_key)
		return
	out.label.text = text
