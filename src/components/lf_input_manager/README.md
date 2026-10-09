# LFInputManager

> Decides who gets each key press: the open pause menu first, the game only if the menu does not want it.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_input_manager.gd` |
| **Tests** | `tests/test_lf_input_manager.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it when several things on one screen want the same keys: while the pause menu is
open, Escape and Enter should go to the menu and never reach the game below it. Each
mode registers a layer (a handler function with a priority), and a layer that returns
`true` consumes the event so lower layers never see it. Without it, one
`_unhandled_input` grows a hand-written `if` chain, and the order depends on where nodes
sit in the tree. For a screen with one simple input handler, Godot's own `_input` /
`_unhandled_input` and `set_input_as_handled()` are enough.

## Step by step

1. *Scene → New Scene*, then click **2D Scene**. Rename the root node to `Main` and save the scene (*Ctrl+S*, or *Cmd+S* on macOS) as `input_demo.tscn`.
2. Click **+ Add Child Node**, pick **ColorRect**, and rename it `PauseMenu`. In the Inspector set *Size* to something visible (for example `300` x `200` under *Layout → Transform*), pick a *Color*, untick **Visible** (under *CanvasItem → Visibility*) so it starts hidden, and set *Process → Mode* to **When Paused** so the menu runs only while the game is paused. You can add a `Label` child with the text "Paused".
3. Select `Main`, click **+ Add Child Node**, search `LFInputManager` and create it. Leave **Stage** on `Unhandled` (the manager gets input after buttons and other controls had their turn; `Input` gets it before them).
4. Right-click `Main`, choose **Attach Script**, click *Create*, and replace the contents with the code below. A **layer** is one function that receives each input event. The number after it is its priority: the highest number goes first. A layer that returns `true` says "I used this event", and no layer below it sees the event.

```gdscript
extends Node2D

@onready var input: LFInputManager = $LFInputManager
@onready var pause_menu: Control = $PauseMenu  # Process Mode: When Paused


func _ready() -> void:
	# Layers run from the highest number to the lowest.
	var toggle := input.add_layer(self, _on_pause_toggle, 30)
	# This script's node stops while the game is paused, and so would its layers;
	# the pause key must keep working then, or nothing could unpause.
	input.set_layer_always_active(toggle, true)
	# Owned by the menu, so it takes part only while the game is paused.
	input.add_layer(pause_menu, _on_menu_input, 20)
	# Owned by this pausable node, so it sits out the pause.
	input.add_layer(self, _on_game_input, 0)


func _on_pause_toggle(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):  # Escape
		get_tree().paused = not get_tree().paused
		pause_menu.visible = get_tree().paused
		print("paused: ", get_tree().paused)
		return true  # consumed: the layers below never see this event
	return false  # not ours: pass it down


func _on_menu_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):  # Enter or Space
		print("menu: accept pressed")
	return true  # an open menu swallows every event


func _on_game_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		print("game: accept pressed")
		return true
	return false
```

5. Press **F6** (*Run Current Scene*). Click the game window first, then press **Enter**: the Output panel prints "game: accept pressed". Press **Escape**: the game pauses and the menu appears. Press **Enter** again: it prints "menu: accept pressed" and the game line does not appear, because the menu consumed the key. Press **Escape** to unpause and close the menu; Enter reaches the game again.

To use your own key instead of Enter/Escape, replace `"ui_accept"` / `"ui_cancel"` with an action you made in *Project → Project Settings → Input Map* (an action is a named input such as "jump").

## API

Everything the class offers; you only need the rows used above to get started.

### Enum `Stage`

| Value | Where the manager picks events up |
|---|---|
| `UNHANDLED` | `_unhandled_input`, after GUI controls had their turn (the default). |
| `INPUT` | `_input`, before GUI controls, so a layer can take keys a focused control would use (arrows, Enter). |
| `MANUAL` | Nowhere: the caller passes events to `route` itself. |

### Constants

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_PRIORITY` | `const DEFAULT_PRIORITY := 0` | Default `priority` of `add_layer`. |

### Properties

| Member | Signature | Description |
|---|---|---|
| `stage` | `@export var stage := Stage.UNHANDLED` | Where events are picked up. An event a layer consumes there is marked handled in the viewport (`set_input_as_handled`). |

### Methods

| Member | Signature | Description |
|---|---|---|
| `add_layer` | `add_layer(owner_node: Node, handler: Callable, priority := DEFAULT_PRIORITY, enabled := Callable()) -> int` (`DEFAULT_PRIORITY` is 0) | Adds a layer and returns its id (ids are per manager). `handler(event)` returns `true` to consume; any other return value, or none, passes the event on. `enabled() -> bool`, when given, is asked each time an event reaches the layer. The layer is dropped when `owner_node` leaves the tree. Equal priorities run newest first. Returns `0` (and reports an error) for a null owner or an invalid handler. |
| `remove_layer` | `remove_layer(id: int) -> void` | Drops a layer. Unknown ids are ignored. |
| `clear` | `clear() -> void` | Drops every layer. |
| `has_layer` | `has_layer(id: int) -> bool` | Whether the layer is still registered. |
| `set_layer_enabled` | `set_layer_enabled(id: int, on: bool) -> void` | Switches a layer on or off, at once (even for the event being routed). Unknown ids are ignored. |
| `is_layer_enabled` | `is_layer_enabled(id: int) -> bool` | Whether the layer is switched on; `false` for an unknown id. Does not ask the `enabled` predicate. |
| `set_layer_always_active` | `set_layer_always_active(id: int, on: bool) -> void` | Lets a layer take part whatever its owner's processing state (a paused tree, the owner's `process_mode`). For the key that opens and closes a pause menu. The on/off switch, the `enabled` predicate and the owner being in the tree and not queued for deletion still apply. Unknown ids are ignored. |
| `is_layer_always_active` | `is_layer_always_active(id: int) -> bool` | Whether the layer was marked with `set_layer_always_active`; `false` for an unknown id. |
| `route` | `route(event: InputEvent) -> bool` | Hands `event` to the layers in order; `true` when one consumed it. Does not mark the event handled; the `INPUT`/`UNHANDLED` stages do that. |

A layer takes part in an event when it is switched on, its `enabled` predicate (if any)
returns `true`, and its owner is inside the tree, not itself queued for deletion and able to
process (`Node.can_process()`; skipped for a layer marked with `set_layer_always_active`).
Each check is made as the event reaches the layer.

## Usage

```gdscript
# level.gd: attach to your level's root node (a pausable node). $PauseMenu is a Control,
# hidden at start, with process_mode = PROCESS_MODE_WHEN_PAUSED.
extends Node

@onready var pause_menu: Control = $PauseMenu

var input := LFInputManager.new()
var world_layer := 0


func _ready() -> void:
	add_child(input)
	# Higher priority runs first. Escape pauses and unpauses from anywhere: always active,
	# because this node stops while paused and its layers would stop with it.
	input.set_layer_always_active(input.add_layer(self, _on_pause_key, 30), true)
	# Owned by the menu, so it takes part only while paused; it swallows every event then.
	input.add_layer(pause_menu, _on_menu_input, 20)
	# The game itself, lowest priority; owned by this pausable node, so it sits out the pause.
	world_layer = input.add_layer(self, _on_world_input, 0)


func _on_pause_key(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		get_tree().paused = not get_tree().paused
		pause_menu.visible = get_tree().paused
		return true  # consumed: no lower layer sees it
	return false


func _on_menu_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		print("menu entry picked")
	return true  # an open menu swallows everything, so the world never sees it


func _on_world_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		print("world: accept pressed")
		return true
	return false


func set_cutscene(playing: bool) -> void:
	input.set_layer_enabled(world_layer, not playing)  # mute the world during a cutscene
```

A menu that only shows and hides without pausing the tree needs no `set_layer_always_active`:
give its layer an `enabled` predicate such as `func() -> bool: return pause_menu.visible`.

## Notes

- The manager sets its own `process_mode` to `PROCESS_MODE_ALWAYS`, so it routes while the tree is paused. Each layer then follows its owner: a pausable owner's layers sit out the pause, unless marked with `set_layer_always_active`. A pause key owned by a pausable node and not marked that way can pause the game but never unpause it.
- Managers share nothing. Add one per scene, or one per overlay that needs a different `stage` (a help overlay that must see arrow keys before focused controls uses `INPUT`). Swapping screens in one frame (`queue_free` the old one, add the new one): layers whose owner is the node you queued stop at once, and the new manager starts routing at once. Only the queued node itself counts as queued for deletion; a layer owned by one of its children keeps receiving until the node is actually deleted at the end of the frame, so own the old screen's layers by the screen root (or remove them).
- A layer is dropped when its owner leaves the tree, including a reparent. Add the layer again after moving its owner.
- A layer whose owner was deleted without ever entering the scene, or whose handler or `enabled` function belongs to a deleted object, is dropped on the next event. The handler and predicate are checked to be valid as the event reaches their layer, before either is called.
- Handlers may add, remove or switch layers while an event is being routed. A layer added then waits for the next event; a layer removed or switched off then does not receive the current one.
- Among managers on the same stage, Godot's own order applies (reverse tree order for `_input`/`_unhandled_input`). A consumed event is marked handled, so a manager later in that order never sees it.
