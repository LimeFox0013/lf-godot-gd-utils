# LFHelpTip, LFHelpBrowser

> Hover help for any button or label, with a panel you design, plus a keyboard tour of all the help on screen.

| | |
|---|---|
| **Files** | `lf_help_tip.gd`, `lf_help_browser.gd` |
| **Tests** | `tests/test_lf_help_tip.gd`, `tests/test_lf_help_browser.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFInputManager`, `LFControl` (`get_canvas_rect`, `sort_reading_order`, `place_beside`), `LFStyle`, `LFBuild`, `LFUtils` (`free_children`, `disconnect_all`), `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFHelpTip` | Node: add it to a scene |
| `LFHelpBrowser` | Node: add it to a scene |

## When to use it

Use it when a control needs more help than one line of text: a stat label whose hover
panel shows a title, an explanation and an example, or an upgrade button whose panel
lists its cost and effect. `LFHelpTip.attach` adds that to any existing control without
subclassing it and without taking its hover or clicks (Godot's own `_make_custom_tooltip`
must be written on every control class). Add an `LFHelpBrowser` and the same help works
without a mouse: hold F1 (or a pad's Back button) and step through every tip with the
arrows or D-pad. For a single line of plain text, Godot's built-in `tooltip_text` is
enough.

## Step by step

1. *Scene → New Scene*, then click **User Interface** (a `Control` root). Rename it `Hud` and save (*Ctrl+S*, or *Cmd+S* on macOS) as `help_demo.tscn`.
2. Click **+ Add Child Node**, pick **Button**, rename it `BuyButton` and set its *Text* to `Buy`. Add a **Label**, rename it `GoldLabel` and set its *Text* to `Gold: 120`. Move them apart in the 2D view so they do not overlap.
3. Select `Hud`, click **+ Add Child Node**, search `LFHelpBrowser` and create it. This adds the keyboard tour (it needs no settings).
4. Right-click `Hud`, choose **Attach Script**, click *Create*, and use this code. A *Callable* is a function passed around as a value; here the second help panel is built by one.

```gdscript
extends Control

@onready var buy_button: Button = $BuyButton
@onready var gold_label: Label = $GoldLabel


func _ready() -> void:
	# Plain text help: hover the button to see it.
	LFHelpTip.attach(buy_button, "Buys one sword for 10 gold.")

	# Richer help: a function that turns the content into a panel (a Control).
	var make_gold_panel := func(entry: Variant) -> Control:
		var box := VBoxContainer.new()
		LFBuild.label(box, entry["title"], Color.GOLD, 0)
		LFBuild.wrap(LFBuild.label(box, entry["text"], null, 13), LFHelpTip.TEXT_WIDTH)
		return box
	LFHelpTip.attach(gold_label, {"title": "Gold", "text": "Spent at the merchant."}, make_gold_panel)
```

5. Press **F6** (*Run Current Scene*). Rest the mouse on the **Buy** button for about half a second (the project's tooltip delay): a tooltip with your sentence appears, and clicking the button still works. Hover `Gold: 120`: a panel with a gold title and a line of text appears.
6. Hold **F1** (on a Mac laptop, hold *fn+F1* unless function keys are set to standard) or a gamepad's Back button: a frame highlights one help target with its panel beside it. Press the arrow keys to move between them; let go of F1 to close.

Change the strings in the script to your own text. For a longer panel (an icon, a cost line), write your own function like `make_gold_panel` that returns any `Control`.

## API

Everything the class offers; you only need the rows used above to get started.

### LFHelpTip

| Member | Signature | Description |
|---|---|---|
| `TEXT_WIDTH` | `const TEXT_WIDTH := 280.0` | Wrap width of the built-in text panel. |
| `default_builder` | `static var default_builder: Callable` | `func(content) -> Control` for tips without their own builder. Process-wide; emptied when the scene tree starts to quit (a lambda in a static variable otherwise aborts the engine at exit), if the main loop existed when it was set. |
| `content` | `var content: Variant` | What the tip explains (a String, a Resource, a Dictionary…). |
| `builder` | `var builder: Callable` | `func(content) -> Control` for this tip's panel. |
| `attach` | `static attach(target: Control, tip_content: Variant, tip_builder := Callable(), hover_text := '') -> LFHelpTip` | Adds a tip to `target` showing `tip_content`, replacing any tip there, and returns it. The tip is `top_level`, has no size and `mouse_filter = IGNORE`; the target's `mouse_filter` is left as it is, and a `PASS` / `STOP` target with an empty `tooltip_text` gets `' '` while the tip is on it (see Notes). `tip_builder` builds its panel (unset: `default_builder`). Null `tip_content` adds nothing and returns null; a null `target` is reported through `LFLogger` and returns null. `hover_text` becomes the tip's `tooltip_text` (shown as plain text when the builder gives no panel); empty uses `hover_text_of(tip_content)`. |
| `attach_tip` | `static attach_tip(target: Control, tip: LFHelpTip, hover_text := '') -> LFHelpTip` | Installs a ready-made tip (e.g. of a subclass) the same way. A null `target` or `tip` is reported through `LFLogger` and returns null. |
| `get_help_rect` | `get_help_rect() -> Rect2` | On-screen rect of what the tip explains: its target's `LFControl.get_canvas_rect`. Measure this, not the tip (the tip has no size). Empty without a Control parent. |
| `get_popup` | `get_popup() -> PopupPanel` | The tooltip window while the help shows, else null. Its child is the built panel (or a `TooltipLabel` of `tooltip_text`). |
| `of` | `static of(target: Control) -> LFHelpTip` | The tip on `target`, or null when it has none. |
| `hover_text_of` | `static hover_text_of(tip_content: Variant) -> String` | The content's `title` (property or key), or a String itself; `''` for anything else (a freed object too). |
| `build_panel` | `build_panel() -> Control` | A new panel: `builder`, else `default_builder`, else a Label of `str(content)` wrapped at `TEXT_WIDTH`. Null without content, or when that label's text would be blank. |

### LFHelpBrowser

| Member | Signature | Description |
|---|---|---|
| `opened` | `signal opened` | The tour opened. |
| `closed` | `signal closed` | The tour closed. |
| `hold_key` | `@export var hold_key: Key = KEY_F1` | Held to tour; release closes. |
| `hold_button` | `@export var hold_button: JoyButton = JOY_BUTTON_BACK` | Pad equivalent of `hold_key` (any device). |
| `DEFAULT_SCOPE_GROUP` | `const DEFAULT_SCOPE_GROUP := &"lf_help_scope"` | Default `scope_group`. |
| `DEFAULT_ROW_TOLERANCE_PX` | `const DEFAULT_ROW_TOLERANCE_PX := 24.0` | Default `row_tolerance_px`, in pixels. |
| `DEFAULT_GAP_PX` | `const DEFAULT_GAP_PX := 12.0` | Default `gap_px`, in pixels. |
| `DEFAULT_FRAME_PAD_PX` | `const DEFAULT_FRAME_PAD_PX := 4.0` | Default `frame_pad_px`, in pixels. |
| `scope_group` | `@export var scope_group: StringName = DEFAULT_SCOPE_GROUP` (&"lf_help_scope") | Full-screen overlays in this group limit the tour to the tips inside the topmost visible one. |
| `row_tolerance_px` | `@export var row_tolerance_px := DEFAULT_ROW_TOLERANCE_PX` (24.0) | Targets whose tops are closer than this (px) count as one row in reading order. |
| `gap_px` | `@export var gap_px := DEFAULT_GAP_PX` (12.0) | Pixels between the target and its help card. |
| `frame_pad_px` | `@export var frame_pad_px := DEFAULT_FRAME_PAD_PX` (4.0) | Pixels the highlight frame stands out around the target. |
| `frame_style` | `var frame_style: StyleBox` | Highlight frame box (default: an outline). |
| `card_style` | `var card_style: StyleBox` | Card box (default: the project theme's `TooltipPanel`, else a dark rounded box). |
| `counter_text` | `var counter_text: Callable` | `func(index: int, total: int, held: bool) -> String`; `index` from 0. Default `"2 / 5   ←/→ next   release to close"` (or `"Help again to close"` when toggled open). |
| `frame`, `card`, `counter_label`, `current`, `input_layers` | members | The frame Panel, the card (its VBox holds the help panel at child 0 and the counter), the counter Label, the tip shown (null when closed), the `LFInputManager` (`Stage.INPUT`). |
| `open` / `close` / `toggle` | `() -> void` | Open on the first target (nothing to explain: stays closed), closing every tip's hover help, which stays closed while the tour is open; close; toggle (stays open through key releases). |
| `step` | `step(delta: int) -> void` | Moves through the reading order, wrapping; closes when no target is left. Does nothing while closed. |
| `is_open` / `is_held_open` | `() -> bool` | Showing; showing because the key/button is held. |
| `visible_targets` | `visible_targets() -> Array[LFHelpTip]` | Tips visible in the tree whose target has an area on screen (`LFHelpTip.get_help_rect`) and is in scope, in reading order of their targets. |
| `rect_on_layer` | `rect_on_layer(tip: Control) -> Rect2` | `tip`'s on-screen rect (an `LFHelpTip`'s `get_help_rect`) mapped onto the browser's own layer: where the frame is drawn. |
| `format_counter` | `format_counter(index: int, total: int, held: bool) -> String` | The counter line `counter_text` (or the default) gives. |

## Usage

```gdscript
# hud.gd: attach to the root Control of your HUD scene.
extends Control

@onready var gold_label: Label = $GoldLabel
@onready var map_button: Button = $MapButton

var browser := LFHelpBrowser.new()


func _ready() -> void:
	# Once, at startup: how every tip turns its content into a panel.
	LFHelpTip.default_builder = func(entry: Variant) -> Control:
		if entry is String:
			return LFBuild.wrap(LFBuild.label(null, entry), LFHelpTip.TEXT_WIDTH)
		var box := VBoxContainer.new()
		LFBuild.label(box, entry.title, Color.GOLD, 0)
		LFBuild.wrap(LFBuild.label(box, entry.text, null, 13), LFHelpTip.TEXT_WIDTH)
		return box

	# Hover help on existing controls. The button still presses normally.
	LFHelpTip.attach(gold_label, {"title": "Gold", "text": "Spent at the merchant."})
	LFHelpTip.attach(map_button, "Opens the map.")

	# Hold F1 (or a pad's Back button) to tour every tip; an on-screen button toggles it.
	add_child(browser)
	LFBuild.button(self, "Help [F1]", browser.toggle)
	browser.closed.connect(func() -> void: map_button.grab_focus())


func open_shop(shop_screen: Control) -> void:
	shop_screen.add_to_group(browser.scope_group)  # tour only the shop while it is up
```

## Notes

- A tip takes no part in mouse picking (it is `top_level`, has no size and `mouse_filter = IGNORE`) and never accepts an event, so clicks, the wheel and gestures go where they would go without it. It leaves its target's `mouse_filter` as it is, and follows the target in one of two ways, depending on that filter (read at every event, so it may change after attaching).
- A `PASS` or `STOP` target is followed through its `mouse_entered`, `mouse_exited` and `gui_input` signals, so it still gets its own signals and input, its children (a Button, a LineEdit...) keep their hover and clicks, and a control drawn over it keeps the mouse there. The help shows where Godot reports the mouse over the target: over the target itself or over a child whose events reach it (`PASS` or `IGNORE` children, gaps in a Container). Over a child with `mouse_filter = STOP` the target is not hovered, so no help shows there. Over a child with its own tooltip (Godot's tooltip lookup, from the hovered control up, finds that tooltip first; a child's own tip counts) that child's tooltip shows instead. Clipping (`clip_contents`, a ScrollContainer) is Godot's own, so a part scrolled out of view shows nothing.
- An `IGNORE` target (a Label's default) is never hovered by Godot, so its tip checks every mouse motion in its viewport (`_input`, a rect test and a walk up the tree). The target counts as hovered where the mouse is inside its rect (its `size`; a custom `_has_point` is not used), no ancestor that clips its contents cuts that point off, and the control Godot hovers there is not drawn over the target. Drawn over is decided as Godot's picking orders controls: by canvas layer, then tree order (later is on top). An ancestor, a control drawn under the target, or a child whose events reach the target (as above) leave the help showing; nothing under the mouse also does, unless a window embedded in the target's viewport is there. Clicks go to whatever Godot picks, so a Label laid over a Button keeps the button clickable, and a Label inside a Button leaves its clicks to the button. Godot's tooltip lookup starts from the control it hovers, so where that control or one of its parents has tooltip text (a Button's description around a tipped Label), its plain tooltip opens next to the help; set the target's `mouse_filter` to `PASS` to make it the hovered control instead (it then takes the clicks over anything drawn under it and passes them on to its parents).
- Where tips overlap, one help shows: a hovered `IGNORE` target's tip wins over a `PASS` / `STOP` target's, and of two hovered `IGNORE` targets the one drawn on top wins.
- What a tip changes on its target: a `PASS` or `STOP` target with an empty `tooltip_text` gets `' '`, and gets it again on hover if it was emptied later; when the tip is removed (moved, replaced or freed) and the text is still `' '`, it is put back to empty. Godot shows no tooltip for blank text, but its tooltip lookup stops at a control with any text, so a parent's plain tooltip (a Button's description around a tipped Label) does not open over the help. A screen reader reads that blank text as the target's tooltip. A target with tooltip text of its own shows that plain tooltip as well as the help, so leave it empty.
- Timing and look use Godot's tooltip settings and theme: the help opens once the mouse has rested on the target for `gui/timers/tooltip_delay_sec` (read at every hover, while Godot's own tooltips read it once at startup; a motion restarts the wait until the help shows), at the mouse plus `display/mouse_cursor/tooltip_position_offset`. As in Godot's tooltip code, the mouse and the window are mapped into what holds the window: the viewport it is embedded in (also for a target inside a SubViewport or an embedded Window, so the help opens where Godot's own tooltip does) or the screen for a native window, scaled with the target's viewport. Where it would leave that viewport's visible rect (or the screen's usable rect) it is flipped to the other side of the mouse, and pushed back inside where that fails too; Godot 4.7's own tooltip is pushed back along the edge without flipping. Like Godot's tooltip, nothing opens while another native popup is active. The window is a `PopupPanel` with the `TooltipPanel` theme type and mouse passthrough. It closes when the mouse leaves the target, on a mouse button press over the target, when the mouse moves onto a child with its own tooltip, when the target or the tip is hidden or leaves the tree, and when an `LFHelpBrowser` tour opens. Moving the mouse onto a window placed beside it counts as leaving the target, as with Godot's own tooltip; a window too big to fit beside the mouse opens under it and stays open while the mouse is on the target or on the window. A window hidden by something else is dropped, and the next motion over the target starts the delay again.
- No per-frame work: tips do no `_process`. While the delay runs, an internal `Timer` child (`PROCESS_MODE_ALWAYS`) counts it down. Every tip handles `_input` and returns at once unless its target is `IGNORE`; deciding which help shows walks every tip (on a show, and after a motion while one is up).
- The help also opens while the tree is paused: tips run with `PROCESS_MODE_ALWAYS` (set when created), Godot still sends `mouse_entered` / `mouse_exited` to paused controls, and the delay timer and the window run with `PROCESS_MODE_ALWAYS`. (Godot sends no `gui_input` to paused controls, so while paused the help of a `PASS` / `STOP` target opens at the position Godot reports for the mouse, and a click on it does not close it; leaving the target does. An `IGNORE` target is followed through `_input`, which runs while paused.)
- A builder that returns null shows the hover text (`tooltip_text`) in a `TooltipLabel`; with blank hover text nothing shows.
- The browser reads input at `Stage.INPUT`, before GUI controls, so while it is open neither the hold key (press, repeat or release) nor an arrow press reaches a focused control. While closed, only a press of the hold key is taken; arrows pass through untouched.
- An analog stick mapped to the `ui_*` actions steps once per push: the action is latched when the stick passes the action's deadzone and freed when it falls back below it. Keys and D-pad buttons step on every press, key repeats included.
- Targets are measured on screen (`get_global_transform_with_canvas`), so a tip in an offset or scaled `CanvasLayer` or under a `Camera2D` is framed where it is drawn, and culled only when it is off screen. Rotated targets get their bounding box.
- A browser that leaves the tree (removed or reparented) closes an open tour, emitting `closed`.
- The browser draws on canvas layer 90 (`CanvasLayer.layer`); set `layer` after creating it to stack it differently.
- `hold_button` matches every pad. The `ui_left/right/up/down` actions decide which keys and D-pad buttons step.
- A target that disappears (its screen was hidden) moves the tour to the first remaining target; with none left the tour closes.
- `default_builder` is process-wide state (shared by every scene); tests that set it should clear it after.
- The browser starts with `process_mode = PROCESS_MODE_ALWAYS`, so F1 works while the tree is paused (a pause menu's help). Set another `process_mode` after creating it to make it follow the pause.
