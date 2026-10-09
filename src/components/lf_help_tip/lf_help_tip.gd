## Gives any Control a rich hover tooltip: a panel you build, instead of plain text.
##
## `LFHelpTip.attach(control, content)` adds a tip node to the control. On hover it shows a
## panel built from `content` in a tooltip window styled and timed by Godot's tooltip
## theme and settings (the `TooltipPanel` theme type, `gui/timers/tooltip_delay_sec`). Like
## Godot's own tooltip, the window opens at the mouse plus
## `display/mouse_cursor/tooltip_position_offset`, in the coordinates of whatever holds it
## (the viewport it is embedded in, also for a target inside a SubViewport or an embedded
## Window; the screen when it is a native window), scaled with the target's viewport. Where
## it would leave that viewport's visible rect (or the screen's usable rect) it is flipped
## to the other side of the mouse, and pushed back inside where that fails too (Godot
## 4.7's own tooltip is pushed back along the edge without flipping). The tip node
## takes no part in mouse picking (it is `top_level`, has no size and `mouse_filter =
## IGNORE`) and never accepts an event, so clicks, the wheel and gestures go where they
## would go without it. `LFHelpBrowser` finds every visible tip to tour them without a mouse.
##
## How the target counts as hovered depends on its own `mouse_filter`, which the tip
## leaves as it is:
## - `PASS` or `STOP`: where Godot's picking hovers it, through its `mouse_entered`,
##   `mouse_exited` and `gui_input` signals: over the target, or over a child whose events
##   reach it (a child that stops the mouse, such as a Button, does not count). Where the
##   mouse is over a child with its own tooltip (or its own tip) that shows instead.
## - `IGNORE` (a Label's default): Godot never hovers it, so the tip checks each mouse
##   motion in its viewport (`_input`): the target counts as hovered where the mouse is
##   inside its rect, not clipped away by an ancestor, and the control Godot hovers there
##   is not drawn over it (it is an ancestor, a control drawn under it, or a child whose
##   events reach it). Clicks there go to whatever Godot picks, so a Label laid over a
##   Button keeps the button clickable. Godot's own tooltip lookup starts from the control
##   it hovers, so where that control (or one of its parents) has tooltip text, its plain
##   tooltip opens next to the help; give the target `mouse_filter = PASS` to make it the
##   hovered control instead (it then takes the clicks over whatever is drawn under it and
##   passes them on to its parents).
##
## A `PASS` or `STOP` target with an empty `tooltip_text` gets a single space while the tip
## is on it (put back to empty when the tip leaves it, if it is still a space; set again on
## hover if it was emptied in between): Godot shows no tooltip for blank text, but its tooltip lookup stops at a
## control with any text, so a parent's plain tooltip (a Button's description around a
## tipped Label) does not open over the help. A screen reader reads that blank text as the
## target's tooltip. A target with tooltip text of its own shows that plain tooltip as
## well as the help.
##
## What `content` is (a String, a Resource, a Dictionary...) is up to the caller; a
## builder `func(content) -> Control` turns it into the panel. Plain text needs no builder.
class_name LFHelpTip
extends Control

## Width in pixels the built-in text panel wraps at.
const TEXT_WIDTH := 280.0
## Node name a tip gets on its target.
const _NODE_NAME := 'HelpTip'
## Dictionary key `hover_text_of` reads the title from.
const _TITLE_KEY := 'title'
## Property `hover_text_of` reads the title from.
const _TITLE_PROPERTY := &"title"
## Project setting holding how long, in seconds, the mouse rests before a tooltip shows.
const _DELAY_SETTING := 'gui/timers/tooltip_delay_sec'
## Godot's default for `_DELAY_SETTING`, in seconds.
const _DEFAULT_DELAY_SEC := 0.5
## Project setting holding the tooltip's offset from the mouse, in pixels.
const _OFFSET_SETTING := 'display/mouse_cursor/tooltip_position_offset'
## Godot's default for `_OFFSET_SETTING`, in pixels.
const _DEFAULT_OFFSET := Vector2(10, 10)
## Tooltip text given to a target that has none: Godot's tooltip lookup stops at a control
## with any tooltip text, and shows nothing for a blank one, so an ancestor's plain tooltip
## does not open over the help.
const _BLANK_TOOLTIP := ' '
## Theme type of the tooltip window, as Godot's own tooltips use.
const _PANEL_TYPE := &"TooltipPanel"
## Theme type of the plain-text label shown when the builder gives no panel.
const _LABEL_TYPE := &"TooltipLabel"
## Group every tip is in, so tips can find each other and `LFHelpBrowser` can close them.
const _TIPS_GROUP := &"_lf_help_tips"
## Group an open `LFHelpBrowser` is in: while any node is, no tip shows its hover help.
const _BROWSING_GROUP := &"_lf_help_browsing"
## Theme constants of an embedded window's title bar and resize border, in pixels: Godot
## counts the mouse over the window there too.
const _TITLE_HEIGHT := &"title_height"
const _RESIZE_MARGIN := &"resize_margin"

static var _log := LFLogger.new()
static var _clear_on_quit_armed := false

## `func(content) -> Control` used by tips that have no `builder` of their own: set it once
## to give every tip in the app the same panel. Process-wide. It is emptied when the scene
## tree starts to quit (a lambda kept in a static variable otherwise aborts the engine at
## exit), provided the main loop exists when it is set.
static var default_builder: Callable:
	set(value):
		default_builder = value
		_clear_on_quit()

## What this tip explains; handed to the builder.
var content: Variant
## `func(content) -> Control` building this tip's panel; unset uses `default_builder`, and
## without that a wrapped Label of `str(content)` (none when that text is blank).
var builder: Callable

## The Control this tip listens to (its parent), or null.
var _target: Control = null
## Whether the mouse is over the target: for a `PASS` / `STOP` target, between its
## `mouse_entered` and `mouse_exited`; for an `IGNORE` target, as of the last mouse motion.
var _hovered := false
## Where the mouse was last seen over the target, in its viewport's pixels.
var _mouse_at := Vector2.ZERO
## Counts the tooltip delay down; made on first use.
var _delay: Timer = null
## The tooltip window while it shows.
var _popup: PopupPanel = null
## Whether the mouse is over the tooltip window (between its `mouse_entered` and
## `mouse_exited`).
var _mouse_in_popup := false
## Whether the tooltip window opened under the mouse (too big to fit beside it).
var _opened_under_mouse := false
## Whether this tip gave the target its blank tooltip (and puts it back when it leaves).
var _blanked_tooltip := false


func _init() -> void:
	add_to_group(_TIPS_GROUP)
	# An IGNORE target is followed through `_input`, which must also run while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Empties `default_builder` when the scene tree starts to quit. A lambda kept in a static
## variable outlives the script that made it, and the engine then aborts while exiting.
static func _clear_on_quit() -> void:
	if _clear_on_quit_armed:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_clear_on_quit_armed = true
	tree.root.tree_exiting.connect(func() -> void:
		default_builder = Callable()
		_clear_on_quit_armed = false, CONNECT_ONE_SHOT)


## Adds a help tip to `target` showing `tip_content`, replacing any tip already there, and
## returns it. Null `tip_content` adds nothing and returns null; a null `target` is
## reported as an error and returns null. `tip_builder` (`func(content) -> Control`)
## builds this tip's panel; unset uses `default_builder`. `hover_text` becomes the tip's
## `tooltip_text`, shown as plain text when the builder gives no panel; when empty it is
## `hover_text_of(tip_content)`.
static func attach(target: Control, tip_content: Variant, tip_builder := Callable(), hover_text := '') -> LFHelpTip:
	if target == null:
		_log.error('LFHelpTip.attach: the target is null')
		return null
	if tip_content == null:
		return null
	var tip := LFHelpTip.new()
	tip.content = tip_content
	tip.builder = tip_builder
	return attach_tip(target, tip, hover_text)


## Adds the ready-made `tip` (for instance of a subclass) to `target`, removing any other
## tip there, and returns it. `hover_text` works as in `attach`. The tip is made
## `top_level` with no size and `mouse_filter = IGNORE`, so a Container target does not lay
## it out and it is never picked. The target's `mouse_filter` is left as it is; a `PASS` or
## `STOP` target with no `tooltip_text` gets a single space while the tip is on it (see the
## class description). A null `target` or `tip` is reported as an error and returns null
## (`tip` is left as it was).
static func attach_tip(target: Control, tip: LFHelpTip, hover_text := '') -> LFHelpTip:
	if target == null or tip == null:
		_log.error('LFHelpTip.attach_tip: the %s is null' % ('target' if target == null else 'tip'))
		return null
	LFUtils.free_children(target, func(child: Node) -> bool: return child is LFHelpTip and child != tip)
	tip.name = _NODE_NAME
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.tooltip_text = hover_text if hover_text != '' else hover_text_of(tip.content)
	tip.top_level = true
	tip.rotation = 0.0
	tip.scale = Vector2.ONE
	tip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	tip.position = Vector2.ZERO
	tip.size = Vector2.ZERO
	if tip.get_parent() != target:
		if tip.get_parent() != null:
			tip.get_parent().remove_child(tip)
		target.add_child(tip)
	return tip


## The help tip on `target`, or null when it has none.
static func of(target: Control) -> LFHelpTip:
	for child in target.get_children():
		if child is LFHelpTip and not child.is_queued_for_deletion():
			return child
	return null


## The hover text `attach` gives `tip_content` when none is passed: its `title` (property
## or Dictionary key), or the String itself; empty for anything else (also for a freed
## object).
static func hover_text_of(tip_content: Variant) -> String:
	if tip_content is String or tip_content is StringName:
		return str(tip_content)
	if tip_content is Dictionary and tip_content.has(_TITLE_KEY):
		return str(tip_content[_TITLE_KEY])
	if typeof(tip_content) == TYPE_OBJECT:
		# `is` on a freed object is a script error, so validity is checked before anything else.
		if is_instance_valid(tip_content) and _TITLE_PROPERTY in tip_content:
			return str(tip_content.get(_TITLE_PROPERTY))
	return ''


## Where the help window of `tooltip_size` goes for the mouse at `mouse` inside `screen`
## (all in the pixels of what holds the popup), following Godot's tooltip code: at
## `mouse + offset`; flipped to the other side of the mouse on an axis where it would
## leave `screen`, and pushed back onto `screen` where that fails too.
static func _tooltip_rect(mouse: Vector2, tooltip_size: Vector2, screen: Rect2, offset := _DEFAULT_OFFSET) -> Rect2:
	var rect := Rect2(mouse + offset, tooltip_size)
	for axis in 2:
		if rect.end[axis] > screen.end[axis]:
			rect.position[axis] = mouse[axis] - tooltip_size[axis] - offset[axis]
			if rect.position[axis] < screen.position[axis]:
				rect.position[axis] = screen.end[axis] - tooltip_size[axis]
		elif rect.position[axis] < screen.position[axis]:
			rect.position[axis] = screen.position[axis]
	return rect


## The Control Godot's picking treats as the root of `item`'s branch: the topmost Control
## reached going up through canvas items, stopping at a `top_level` one.
static func _gui_root(item: CanvasItem) -> Control:
	var root := item as Control
	var node := item
	while not node.top_level:
		node = node.get_parent() as CanvasItem
		if node == null:
			break
		if node is Control:
			root = node
	return root


## Whether Godot's picking reaches `a` before `b` (so `a` is drawn over `b` and takes the
## mouse there first): branches are ordered by canvas layer, then tree order; inside a
## branch, later in the tree is on top.
static func _drawn_over(a: Control, b: Control) -> bool:
	var root_a := _gui_root(a)
	var root_b := _gui_root(b)
	if root_a != root_b:
		var layer_a := root_a.get_canvas_layer_node()
		var layer_b := root_b.get_canvas_layer_node()
		var index_a := layer_a.layer if layer_a != null else 0
		var index_b := layer_b.layer if layer_b != null else 0
		if index_a != index_b:
			return index_a > index_b
		return root_a.is_greater_than(root_b)
	return a.is_greater_than(b)


## Whether `at` (viewport pixels) is inside `control`'s rect.
static func _contains(control: Control, at: Vector2) -> bool:
	return Rect2(Vector2.ZERO, control.size).has_point(control.get_global_transform_with_canvas().affine_inverse() * at)


## A new panel for this tip's content: from `builder`, else `default_builder`, else a
## Label of `str(content)` wrapping at `TEXT_WIDTH`. Null when there is no content, or the
## built-in label would be blank.
func build_panel() -> Control:
	if content == null:
		return null
	if builder.is_valid():
		return builder.call(content)
	if default_builder.is_valid():
		return default_builder.call(content)
	var text := str(content)
	if text.strip_edges() == '':
		return null
	return LFBuild.wrap(LFBuild.label(null, text), TEXT_WIDTH)


## The on-screen rect of what this tip explains, in its viewport's pixels: its target's
## `LFControl.get_canvas_rect`. The tip itself has no size, so measure this instead of the
## tip. Empty when the tip has no Control parent.
func get_help_rect() -> Rect2:
	var target := get_parent() as Control
	return Rect2() if target == null else LFControl.get_canvas_rect(target)


## The tooltip window while the help shows, else null. It holds the built panel (or, when
## the builder gives none, a `TooltipLabel` of `tooltip_text`).
func get_popup() -> PopupPanel:
	return _popup


## Shows the help at the last mouse position seen over the target, placed as Godot places
## its tooltips. Shows nothing when neither a panel nor a non-blank `tooltip_text` is
## there, and, like Godot's tooltips, nothing while another native popup is open.
func _show_help() -> void:
	_hide_popup()
	if not is_inside_tree():
		return
	var window := _visible_window()
	var active_popup := DisplayServer.window_get_active_popup()
	if window == null or (active_popup != DisplayServer.INVALID_WINDOW_ID and active_popup != window.get_window_id()):
		return
	var panel := build_panel()
	if panel == null:
		if tooltip_text.strip_edges() == '':
			return
		var label := Label.new()
		label.theme_type_variation = _LABEL_TYPE
		label.text = tooltip_text
		panel = label
	_popup = PopupPanel.new()
	_popup.theme_type_variation = _PANEL_TYPE
	_popup.transient = true
	_popup.unfocusable = true
	_popup.mouse_passthrough = true
	_popup.popup_window = false
	_popup.wrap_controls = true
	_popup.process_mode = Node.PROCESS_MODE_ALWAYS
	_popup.add_child(panel)
	_popup.mouse_entered.connect(_on_popup_mouse_entered)
	_popup.mouse_exited.connect(_on_popup_mouse_exited)
	_popup.popup_hide.connect(_on_popup_hidden)
	add_child(_popup, false, Node.INTERNAL_MODE_BACK)
	_popup.popup(Rect2i(_popup_rect(window)))


## Where the tooltip window goes, in the coordinates `Window.popup` takes: the pixels of the
## viewport embedding it, or screen pixels for a native window. Follows Godot's tooltip
## code: the mouse is mapped there through this viewport's popup base transform
## (`get_screen_transform` without the canvas transform), the offset and the window's size
## are scaled by that transform's smaller scale, and `_tooltip_rect` keeps it inside the
## embedding viewport's visible rect or the screen's usable rect (left to the window
## manager where the display server places windows itself).
func _popup_rect(window: Window) -> Rect2:
	var base := get_screen_transform() * get_global_transform_with_canvas().affine_inverse()
	var base_scale := base.get_scale()
	var popup_scale := minf(base_scale.x, base_scale.y)
	var mouse := base * _mouse_at
	var offset: Vector2 = ProjectSettings.get_setting(_OFFSET_SETTING, _DEFAULT_OFFSET)
	offset *= popup_scale
	_popup.content_scale_factor = popup_scale
	var popup_size := (_popup.get_contents_minimum_size() * popup_scale).ceil()
	var max_size := Vector2(_popup.max_size)
	if max_size.x > 0.0 and max_size.y > 0.0:
		popup_size = popup_size.min(max_size)
	var embedder := _embedder()
	var rect := Rect2(mouse + offset, popup_size)
	if embedder != null or not DisplayServer.has_feature(DisplayServer.FEATURE_SELF_FITTING_WINDOWS):
		var bounds := embedder.get_visible_rect() if embedder != null \
				else Rect2(DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(window.get_window_id())))
		rect = _tooltip_rect(mouse, popup_size, bounds, offset)
	_opened_under_mouse = rect.has_point(mouse)
	return rect


## The viewport the tooltip window is embedded in (the first one up from this tip's that
## embeds subwindows, as `Window.is_embedded` finds it), or null when it is a native window.
func _embedder() -> Viewport:
	var viewport := get_viewport()
	while viewport != null:
		if viewport.gui_embed_subwindows:
			return viewport
		viewport = viewport.get_parent().get_viewport() if viewport.get_parent() != null else null
	return null


## The first visible Window up from this tip's viewport: the one the tooltip belongs to.
func _visible_window() -> Window:
	var viewport := get_viewport()
	while viewport != null:
		var window := viewport as Window
		if window != null and window.visible:
			return window
		viewport = viewport.get_parent().get_viewport() if viewport.get_parent() != null else null
	return null


## Hides the help and stops a running hover delay.
func _hide_help() -> void:
	if _delay != null:
		_delay.stop()
	_hide_popup()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PARENTED:
			_listen_to(get_parent() as Control)
		NOTIFICATION_UNPARENTED:
			_listen_to(null)
		NOTIFICATION_EXIT_TREE:
			_hovered = false
			_hide_help()
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				_hide_help()


## Moves the target's signal connections to `target` (null: none), putting back the blank
## tooltip this tip gave the one it leaves.
func _listen_to(target: Control) -> void:
	if _target != null and is_instance_valid(_target):
		LFUtils.disconnect_all(_target.mouse_entered, self)
		LFUtils.disconnect_all(_target.mouse_exited, self)
		LFUtils.disconnect_all(_target.gui_input, self)
		if _blanked_tooltip and _target.tooltip_text == _BLANK_TOOLTIP:
			_target.tooltip_text = ''
	_blanked_tooltip = false
	_target = target
	_hovered = false
	_hide_help()
	if target != null:
		target.mouse_entered.connect(_on_target_mouse_entered)
		target.mouse_exited.connect(_on_target_mouse_exited)
		target.gui_input.connect(_on_target_gui_input)
		_blank_tooltip()


## Gives a `PASS` / `STOP` target with no tooltip text the blank one (see the class
## description).
func _blank_tooltip() -> void:
	if _target.mouse_filter != Control.MOUSE_FILTER_IGNORE and _target.tooltip_text == '':
		_target.tooltip_text = _BLANK_TOOLTIP
		_blanked_tooltip = true


func _on_target_mouse_entered() -> void:
	_hovered = true
	_blank_tooltip()
	# Godot sends `gui_input` right after this when it is not paused; this is the fallback.
	_mouse_at = get_viewport().get_mouse_position()
	if _popup == null:
		_restart_delay()


## Godot reports the target's exit before the tooltip window's entry, so the help closes at
## the end of the frame, unless the mouse is back on the target or on a window that opened
## under it (too big to fit beside the mouse): that window takes the hover from the target
## without the mouse moving, and closing it would reopen it in a loop.
func _on_target_mouse_exited() -> void:
	_hovered = false
	_close_unless_hovered.call_deferred()


## A motion over the target follows the mouse; a mouse button press hides the help.
func _on_target_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			_hide_help()
		return
	if not event is InputEventMouseMotion or not _hovered:
		return
	_mouse_at = _target.get_global_transform_with_canvas() * (event as InputEventMouseMotion).position
	_on_motion_while_hovered()


## Follows an `IGNORE` target, which Godot never hovers, through every mouse event in its
## viewport (see the class description). Other targets are followed through their signals.
func _input(event: InputEvent) -> void:
	if _target == null or not is_instance_valid(_target) or _target.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return
	if event is InputEventMouseButton:
		if event.pressed and _hovered:
			_hide_help()
		return
	if not event is InputEventMouseMotion:
		return
	var at := (event as InputEventMouseMotion).position
	if not _shows_through_at(at):
		if _hovered:
			_hovered = false
			_close_unless_hovered()
		return
	_mouse_at = at
	if _hovered:
		_on_motion_while_hovered()
	else:
		_hovered = true
		_restart_delay()


## While the help is not up, a motion restarts the delay (as Godot's tooltips do until one
## shows); a window something else hid is dropped first, so the help comes back. While it
## is up, the help closes once another control or tip takes over the tooltip (checked at
## the end of the frame, when every tip has seen the motion).
func _on_motion_while_hovered() -> void:
	if _popup != null and not _popup.visible:
		_hide_popup()
	if _popup == null:
		_restart_delay()
	else:
		_close_unless_shown_here.call_deferred()


func _restart_delay() -> void:
	if not is_inside_tree():
		return
	var delay_sec: float = ProjectSettings.get_setting(_DELAY_SETTING, _DEFAULT_DELAY_SEC)
	if delay_sec <= 0.0:
		_on_delay_timeout()
		return
	if _delay == null:
		_delay = Timer.new()
		_delay.one_shot = true
		_delay.ignore_time_scale = true
		_delay.process_mode = Node.PROCESS_MODE_ALWAYS
		_delay.timeout.connect(_on_delay_timeout)
		add_child(_delay, false, Node.INTERNAL_MODE_FRONT)
	_delay.start(delay_sec)


func _on_delay_timeout() -> void:
	if _popup == null and _shows_here():
		_show_help()


## Whether this tip's help is the tooltip to show now: the target is hovered and visible,
## the tip is visible, no `LFHelpBrowser` is open, Godot's tooltip lookup reaches the
## target (for a `PASS` / `STOP` target), and no hovered tip on an `IGNORE` target is drawn
## over it (for a `PASS` / `STOP` target, any such tip is: it is not covered by the
## control Godot hovers, which is this target or inside it).
func _shows_here() -> bool:
	if not _hovered or not is_visible_in_tree() or _target == null or not is_instance_valid(_target) \
			or not _target.is_visible_in_tree() or get_tree().get_first_node_in_group(_BROWSING_GROUP) != null:
		return false
	var ignoring := _target.mouse_filter == Control.MOUSE_FILTER_IGNORE
	if not ignoring and not _tooltip_reaches_target(get_viewport().gui_get_hovered_control(), _mouse_at):
		return false
	for node in get_tree().get_nodes_in_group(_TIPS_GROUP):
		var other := node as LFHelpTip
		if other == self or not other._hovered or other.get_viewport() != get_viewport() \
				or other._target == null or not is_instance_valid(other._target) \
				or other._target.mouse_filter != Control.MOUSE_FILTER_IGNORE or not other.is_visible_in_tree():
			continue
		if not ignoring or _drawn_over(other._target, _target):
			return false
	return true


## Whether an `IGNORE` target counts as hovered with the mouse at `at` (its viewport's
## pixels): visible, inside its rect, not clipped away by an ancestor, and not covered by
## the control Godot hovers there or by an embedded window (see the class description).
func _shows_through_at(at: Vector2) -> bool:
	if not _target.is_visible_in_tree() or not _contains(_target, at) or _clipped_away(at):
		return false
	var over := get_viewport().gui_get_hovered_control()
	if over == null:
		return not _under_embedded_window(at)
	if _target.is_ancestor_of(over):
		return _tooltip_reaches_target(over, at)
	return not _drawn_over(over, _target)


## Whether an ancestor that clips its contents leaves `at` outside, as Godot's picking does
## (up to the target's branch root).
func _clipped_away(at: Vector2) -> bool:
	var item: CanvasItem = _target
	while not item.top_level:
		item = item.get_parent() as CanvasItem
		if item == null:
			return false
		var control := item as Control
		if control != null and control.clip_contents and not _contains(control, at):
			return true
	return false


## Whether a window embedded in this tip's viewport is under `at`, its title bar and
## resize border included, as Godot counts them. The help's own window does not count when
## it opened under the mouse (see `_on_target_mouse_exited`).
func _under_embedded_window(at: Vector2) -> bool:
	var viewport := get_viewport()
	if not viewport.gui_embed_subwindows:
		return false
	for window: Window in viewport.get_embedded_subwindows():
		if window == _popup and _opened_under_mouse:
			continue
		var rect := Rect2(window.position, window.size)
		if not window.borderless:
			var title := float(window.get_theme_constant(_TITLE_HEIGHT))
			var margin := float(window.get_theme_constant(_RESIZE_MARGIN))
			rect = rect.grow_individual(margin, title + margin, margin, margin)
		if rect.has_point(at):
			return true
	return false


## Whether Godot's own tooltip lookup, from `from` (the control under the mouse at `at`,
## viewport pixels) up through its parents, reaches the target before a
## control with its own tooltip (which then shows instead).
func _tooltip_reaches_target(from: Control, at: Vector2) -> bool:
	var control := from
	while control != null and control != _target:
		if control.get_tooltip(control.get_global_transform_with_canvas().affine_inverse() * at) != '':
			return false
		if control.mouse_filter == Control.MOUSE_FILTER_STOP or control.top_level:
			return false
		control = control.get_parent_control()
	return control != null


## Hides the help unless the mouse is on the target or on a help window that opened under it.
func _close_unless_hovered() -> void:
	if not _hovered and not (_mouse_in_popup and _opened_under_mouse):
		_hide_help()


## Hides the help when it is up and no longer this tip's to show.
func _close_unless_shown_here() -> void:
	if _popup != null and not _shows_here():
		_hide_help()


func _on_popup_mouse_entered() -> void:
	_mouse_in_popup = true


func _on_popup_mouse_exited() -> void:
	_mouse_in_popup = false
	_close_unless_hovered.call_deferred()


## Something other than the tip hid the window: drop it, so the next motion over the
## target starts the delay again.
func _on_popup_hidden() -> void:
	if _popup != null and not _popup.visible:
		_hide_popup()


## Hides the tooltip window and frees it at the end of the frame.
func _hide_popup() -> void:
	if _popup == null:
		return
	var popup := _popup
	_popup = null
	_mouse_in_popup = false
	if is_instance_valid(popup):
		popup.hide()
		popup.queue_free()
