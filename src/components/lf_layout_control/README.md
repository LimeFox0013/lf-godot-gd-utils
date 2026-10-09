# LFLayoutControl

> A click-through `LFControl` for layout only: it lets mouse input through to the controls behind it and takes no keyboard focus (both set again every time it enters the tree).

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_layout_control.gd`, `lf_layout_control.tscn` |
| **Tests** | `tests/test_lf_layout_control.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFControl` |

## When to use it

Use it for an invisible region that only marks a place on screen: a drop zone, the area
where a boss health bar will appear, or an anchor other code positions things against. It
lets clicks through to the buttons behind it even if someone edits `mouse_filter` in the
Inspector or a subclass changes it, because the settings are re-applied on every tree
entry (a change made from code while it is in the tree lasts until the next entry). A plain `Control` with `mouse_filter = Ignore` does the same while nobody touches
it; use `LFLayoutControl` when you also want it findable by `registry_id`.

## Step by step

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock. Save it.
2. Add a button to click: **+ Add Child Node**, type `Button`, press *Create*, rename it
   `StartButton` (select it and press F2), and set its *Text* to `Start` in the Inspector.
3. Add the invisible region **on top of it** (lower in the Scene dock list means drawn
   on top): click the root node, then the **Instantiate Child Scene** button (the chain-link
   icon) and pick `lf_layout_control.tscn` from the library's folder
   (`src/components/lf_layout_control/`). It covers the whole window. Set its *Registry Id* to
   `drop_zone` in the Inspector.
4. Right-click the root node, choose **Attach Script**, press *Create*, and replace the
   script's contents with:

   ```gdscript
   extends Control


   func _ready() -> void:   # runs once when the scene starts
   	$StartButton.pressed.connect(func(): print("Start clicked"))
   	# Find the region by its id and show how it treats the mouse.
   	var region := LFControl.by_id("drop_zone")
   	print("Mouse filter: ", region.mouse_filter)   # 2 means Ignore: clicks pass through
   ```
5. Press **F6** (*Run Current Scene*) and click Start. The **Output** panel shows
   `Mouse filter: 2` and, when you click, `Start clicked`, even though the region covers
   the button. (A plain `Control` on top would swallow the click.)

## API

Everything the class offers; you only need the rows used above to get started.

No members of its own. On every tree entry it forces:

| Member | Value |
|---|---|
| `mouse_filter` | `Control.MOUSE_FILTER_IGNORE` |
| `focus_mode` | `Control.FOCUS_NONE` |

Inherited: `registry_id` and the static helpers `by_id()`, `get_center_pos()`, `get_center_pos_on_viewport()`, `get_canvas_rect()`, `sort_reading_order()`, `place_beside()` (see `LFControl`). Subclassed by `LFControl2D`.

## Usage

```gdscript
# hud.gd, on a full-screen Control.
extends Control


func _ready() -> void:
	var region := LFLayoutControl.new()
	region.registry_id = "drop_zone"
	region.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(region)   # click-through from now on

	# Clicks pass through, but the region is still a positioning reference:
	var center := LFControl.get_center_pos_on_viewport(LFControl.by_id("drop_zone"))
	print("Drop zone centre: ", center)
```

## Notes

- The settings are applied on the tree-entry notification, so a subclass overriding `_enter_tree()` without `super()` is still click-through.
- A change made from code while the node is in the tree lasts until the node next enters the tree (Godot offers no hook on native property writes).
- Children are not affected; set their `mouse_filter` separately.
- Instantiable by name through `LFComponents.create_component("layout_control", parent)`.
