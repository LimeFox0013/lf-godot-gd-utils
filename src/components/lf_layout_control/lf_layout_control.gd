## A Control for layout only: clicks pass through it and it takes no keyboard focus.
##
## Every time it enters the tree it sets `mouse_filter` to `MOUSE_FILTER_IGNORE` and
## `focus_mode` to `FOCUS_NONE`, whatever the Inspector or a subclass says; a change made
## while it is in the tree lasts until the next entry. Like any `LFControl` it can be
## found by its `registry_id`.
class_name LFLayoutControl
extends LFControl


## Applied on the tree-entry notification rather than in `_enter_tree`, so a subclass
## overriding `_enter_tree` without `super()` is still click-through.
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
