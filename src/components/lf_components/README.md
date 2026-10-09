# LFComponents

> Static factory that instantiates an LF component's packed scene from its short name by naming convention.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_components.gd` |
| **Tests** | `tests/test_lf_components.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` (reports an unknown component name) |

## When to use it

Use it when data names the component to create: a debug console command
`spawn layout_control`, or a UI config file listing which helper controls to add. It
finds the scene relative to wherever LF is installed and reports a bad name instead of
failing on a `null` resource. When you know the component while writing code, just use
`preload()` on the scene file, or `LFLayoutControl.new()` for the script-only ones.

## Step by step

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock. Save it.
2. Right-click the root node, choose **Attach Script**, press *Create*, and replace the
   script's contents with:

   ```gdscript
   extends Control


   func _ready() -> void:   # runs once when the scene starts
   	# Make an LFControlOut (a text display) from its short name and add it to this node.
   	# The name is the folder name without "lf_": "control_out".
   	var readout := LFComponents.create_component("control_out", self) as LFControlOut
   	# Give it an id, so any script can find it...
   	readout.registry_id = "score"
   	# ...and write text into it by that id.
   	LFControlOut.set_prop("score", "Score: 0")
   ```
3. The short names that work are `control`, `control_2d`, `control_out` and
   `layout_control` (the components that ship a scene file).
4. Press **F6** (*Run Current Scene*). You should see `Score: 0` in the top-left corner of
   the window. A wrong name prints an error in the **Output** panel and returns `null`.

## API

Everything the class offers; you only need the rows used above to get started.

### Methods

| Member | Signature | Description |
|---|---|---|
| `components_dir` | `static components_dir() -> String` | The folder holding the component folders, derived from this script's own location (the parent of `lf_components/`), with a trailing slash. Cached. |
| `init_component` | `static init_component(component_name: String) -> Node` | Loads `<components_dir>lf_<name>/lf_<name>.tscn` and returns `instantiate()` (not added to the tree). Returns `null` with an error when the name is not a plain identifier or that scene doesn't exist. |
| `create_component` | `static create_component(component_name: String, parent_node: Node) -> Node` | `init_component`, then `parent_node.add_child(...)`; returns the instance, or `null` with an error when `parent_node` is null (nothing is instantiated then) or there is no scene. Synchronous. |

## Usage

```gdscript
# hud.gd, on any Control in the tree.
extends Control


func _ready() -> void:
	# Created and added as a child of this node: its _ready() has already run.
	var region := LFComponents.create_component("layout_control", self)
	region.name = "DropZone"

	# Created but not added anywhere yet: add it yourself (or free it).
	var score_label := LFComponents.init_component("control_out")
	add_child(score_label)
```

## Notes

- The name is prefixed with `lf_` and resolved to exactly one path; there is no fallback lookup. Only folders that ship a same-named `.tscn` work: `control`, `control_2d`, `control_out`, `layout_control`. For any other name both methods return `null`.
- The name must be a plain identifier (ASCII letters, digits and `_`, not starting with a digit), so it cannot reach outside the components folder.
- The component's `_ready()` (the function Godot calls when a node enters the scene) has run when `create_component` returns only if `parent_node` is inside the tree; otherwise it runs when the parent enters the tree. If you need Container layout to settle, await a frame yourself.
- The base path follows the script, so the library works wherever it is installed.
