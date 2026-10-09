## Fills an OptionButton (a drop-down list) from your data and reads the choice back as a value.
##
## Each item stores its value as item metadata, so you select, read and listen by value
## (a record id, a mode name) instead of keeping a separate array of ids beside the
## drop-down. Static: call the functions on the class, never `.new()` it.
class_name LFOptionPicker

static var _log := LFLogger.new()


## Replaces `picker`'s items with one per `items` entry, labelled `label.call(item)` and
## carrying `value.call(item)` (the item itself when `value` is empty). Then selects the
## first item carrying `selected`; when no item carries it, nothing is selected rather
## than the first item standing in for it. With `selected` null (the default) the first
## item is selected. Returns whether an item is selected afterwards. Never emits
## `item_selected`. With `icon`, each item also shows `icon.call(item)` (a Texture2D; null
## shows none). An invalid `label` is reported and leaves the picker as it was.
static func fill(picker: OptionButton, items: Array, label: Callable, value := Callable(), selected: Variant = null, icon := Callable()) -> bool:
	if not label.is_valid():
		_log.error('LFOptionPicker.fill needs a valid label callable')
		return false
	picker.clear()
	for i in items.size():
		picker.add_item(str(label.call(items[i])), i)
		picker.set_item_metadata(i, value.call(items[i]) if value.is_valid() else items[i])
		if icon.is_valid():
			var texture: Variant = icon.call(items[i])
			if texture is Texture2D:
				picker.set_item_icon(i, texture)
	if selected == null:
		return picker.selected >= 0
	if select_value(picker, selected):
		return true
	picker.select(-1)
	return false


## Selects the first item carrying `value` (`LFUtils.same_value`: an int matches a float
## of the same number, a String matches a StringName); false, selection unchanged, when
## none does.
static func select_value(picker: OptionButton, value: Variant) -> bool:
	for i in picker.item_count:
		if LFUtils.same_value(picker.get_item_metadata(i), value):
			picker.select(i)
			return true
	return false


## The selected item's value, or `fallback` when nothing is selected or the selected
## item carries no value (an item added by hand, a separator).
static func selected_value(picker: OptionButton, fallback: Variant = null) -> Variant:
	var index := picker.selected
	if index < 0:
		return fallback
	var item_value: Variant = picker.get_item_metadata(index)
	return fallback if item_value == null else item_value


## Connects `picker.item_selected` so `callback(value)` receives the chosen item's value
## (null for an item without one) instead of its index. Returns the connected callable,
## for `item_selected.disconnect`. An invalid `callback` is reported, nothing is connected
## and an empty Callable is returned.
static func value_selected(picker: OptionButton, callback: Callable) -> Callable:
	if not callback.is_valid():
		_log.error('LFOptionPicker.value_selected needs a valid callback')
		return Callable()
	var relay := func(index: int) -> void: callback.call(picker.get_item_metadata(index))
	picker.item_selected.connect(relay)
	return relay
