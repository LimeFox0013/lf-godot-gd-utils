# LFControl

> A `Control` any script can find by an id set in the Inspector, plus static helpers to place UI around controls; base class of the other control-registry components.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_control.gd`, `lf_control.tscn` |
| **Tests** | `tests/test_lf_control.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it when a script needs a UI element that lives elsewhere in the scene, without a
fragile node path: a tutorial arrow pointing at the "Build" button, or a quest tracker
flashing the minimap slot. Set `registry_id` in the Inspector and call
`LFControl.by_id("build_button")` from anywhere; it needs no `SceneTree` and returns at most
one control (the newest live holder, optionally in one viewport), or `null`. Use a Godot group
(`call_group`: call a function on every node in a named set) when you want every holder, and a scene-unique name (`%Name`) when the
caller is in the same scene.

## Step by step

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock (a full-window
   `Control` root). Save it with Ctrl+S.
2. Click **+ Add Child Node**, type `LFControl`, select it and press *Create*.
3. Select it. In the Inspector set *Registry Id* to `target_slot` (the name other scripts
   will use to find it). The scene fills its parent, so first choose **Layout → Anchor
   Preset → Top Left** in the toolbar above the viewport, then under *Layout → Transform*
   set *Size* to `120`, `60` and *Position* to `400`, `200` (pixels).
4. Right-click the root node, choose **Attach Script**, press *Create*, and replace the
   script's contents with:

   ```gdscript
   extends Control


   func _ready() -> void:   # runs once when the scene starts
   	# Find the control by its id; no node path needed. null means nothing has that id.
   	var slot := LFControl.by_id("target_slot")
   	if slot == null:
   		print("target_slot not found")
   		return
   	# Where the middle of that control is in the game window, in pixels.
   	print("Centre on screen: ", LFControl.get_center_pos_on_viewport(slot))
   ```
5. Press **F6** (*Run Current Scene*). The **Output** panel at the bottom of the editor
   shows `Centre on screen: (460.0, 230.0)`: the position plus half the size.
6. A plain `LFControl` still catches mouse clicks like any Control. If it should be
   invisible and let clicks through, use `LFLayoutControl` instead.

## API

Everything the class offers; you only need the rows used above to get started. Static functions (`static`) are called on the class name, like `LFControl.by_id(...)`.

### Exports

| Member | Signature | Description |
|---|---|---|
| `registry_id` | `@export var registry_id: String` | If non-empty, the control is registered under this exact key while it is in the tree. Setting it while in the tree moves the registration (`""` just unregisters). |

### Methods

| Member | Signature | Description |
|---|---|---|
| `by_id` | `static by_id(id: String, viewport: Viewport = null) -> Control` | The newest control registered under `id` that is alive and in the tree, or `null`. With `viewport`, only controls inside that viewport count. Never returns a freed control. |
| `get_center_pos` | `static get_center_pos(control_node: Control) -> Vector2` | Local (unscaled) center: `control_node.size * 0.5`. |
| `get_center_pos_on_viewport` | `static get_center_pos_on_viewport(control_node: Control) -> Vector2` | On-screen center in the control's viewport pixels: `get_global_transform_with_canvas() * (size * 0.5)`. Accounts for scale, rotation, a `CanvasLayer` and a `Camera2D`. |
| `get_canvas_rect` | `static get_canvas_rect(control_node: Control) -> Rect2` | On-screen rect in the control's viewport pixels: the bounding box of its rect through `get_global_transform_with_canvas()` (a `CanvasLayer`, a `Camera2D`, scale, rotation). Equals `get_global_rect()` for an unrotated control on the default canvas without a camera. |
| `sort_reading_order` | `static sort_reading_order(controls: Array, row_tolerance := 0.0) -> Array` | A new array of the live Controls in `controls`, row by row from the top, left to right within a row, by on-screen rect (`get_canvas_rect`). A row starts at its highest control and takes every control whose top is at most `row_tolerance` px below it. The input order does not matter, except among controls in one row with the same left edge (their order is unspecified). |
| `place_beside` | `static place_beside(anchor: Rect2, box_size: Vector2, bounds: Vector2, gap := 0.0) -> Vector2` | Top-left position for a `box_size` box `gap` px right of `anchor`, or left of it when the right has no room; top-aligned with `anchor` and moved inside `bounds` vertically when it is no taller than `bounds` (a taller box goes to y = 0), never left of 0: with no room on either side it goes to x = 0, where it may overlap `anchor` or overflow the right edge. For popups and callouts. |

Subclasses in this lib: `LFLayoutControl`, `LFControl2D` (via `LFLayoutControl`), `LFControlOut`.

## Usage

```gdscript
# hud.gd, on the HUD root. In the editor, one of its children is an LFControl
# (instance lf_control.tscn, or add a Control and attach lf_control.gd) with
# registry_id = "minimap_slot".
extends Control

@onready var callout: Label = $Callout


func _ready() -> void:
	# Any script can find the slot by its id; null when nothing holds it.
	var slot := LFControl.by_id("minimap_slot")
	if slot != null:
		print("Minimap centre on screen: ", LFControl.get_center_pos_on_viewport(slot))
		# Show the callout 12 px to the right of the slot (or to its left if there is no room).
		callout.position = LFControl.place_beside(slot.get_global_rect(), callout.size, get_viewport_rect().size, 12.0)


# Visit some markers in reading order: rows top to bottom, left to right in each row.
func ordered_markers(markers: Array) -> Array:
	return LFControl.sort_reading_order(markers, 24.0)
```

In a split-screen game the same id can live in each SubViewport; pass the viewport to pick
one: `LFControl.by_id("minimap_slot", $LeftView/SubViewport)`.

## Notes

- "Tree" means the scene tree, the nodes of the running scene. Registration runs on the tree-entry and tree-exit notifications, not in `_enter_tree()`/`_exit_tree()`, so a subclass may override those freely, with or without `super()`.
- Several controls may share an id. The newest holder wins; when it leaves the tree or is freed, the next-newest holder still in the tree is found again.
- The registry is one process-wide namespace across every viewport and window. Pass `viewport` to `by_id()` to pick the holder in one viewport; without it the newest holder anywhere wins.
- A control removed from the tree but kept alive (a pooled or detached panel) is not found until it is added back.
- `by_id("")` returns null, since empty ids are never registered.
- `sort_reading_order` groups controls into rows with a tolerance, so rows of slightly ragged controls read left to right; keep the tolerance below the gap between real rows. Each row is measured from its highest control, so a slope of controls each a little lower than the last does not merge into one endless row.
- A changed scene drops its controls' entries as they leave the tree; there is nothing to reset.
