# LFAnimate

> Ready-made tweens for UI and effects: a property tween that replaces the previous one on the same property, a scale punch, an animate-then-free one-shot, and canned "comic pop in", "fall out" and "paper fall" animations on Control/Node2D.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_animate.gd` |
| **Tests** | `tests/test_lf_animate.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils` (`tree_root`) |

## When to use it

Use it for the small animations every game has: fade a panel in, punch the score label
each time it changes, make a damage number rise, fade and free itself, pop a speech
bubble in and drop it out. A bare `create_tween().tween_property()` lets two tweens on
the same property fight, with the older, longer one winning; `control`, `punch_scale`
and the pops replace the previous tween on the same property, remember the true rest
scale and position so overlapping punches and pops don't ratchet (grow or drift a bit
more each time), centre a Control's pivot, and their coroutines return (with `false`)
when their tween is killed elsewhere, instead of waiting forever.
For multi-step or keyframed animation, use Godot's `Tween` chains or an
`AnimationPlayer` directly.

## Step by step

A *tween* is Godot's way of changing a value smoothly over time. `LFAnimate` wraps
common tweens so that two of its tweens on the same property don't fight (the newer one
replaces the older).

1. In the editor choose *Scene → New Scene*, then in the Scene dock click *User
   Interface* (this creates a `Control` root).
2. Select the root, click the *+ Add Child Node* button (top of the Scene dock), type
   `Label`, and press *Create*. In the Inspector set the Label's *Text* to `Score: 0`.
3. Right-click the root node, choose *Attach Script*, keep the defaults, press *Create*,
   and replace the script with:

```gdscript
extends Control

@onready var label: Label = $Label   # the Label you added in step 2
var score := 0

func _ready() -> void:
	label.position = Vector2(100, 100)   # where it sits, in pixels
	label.modulate.a = 0.0               # start fully see-through (0 = invisible, 1 = solid)
	# Fade to solid over 1.0 second, then wait for the tween to finish.
	var tween := LFAnimate.control(label, "modulate:a", 1.0, 1.0)
	await tween.finished

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):   # Space or Enter
		score += 1
		label.text = "Score: %d" % score
		LFAnimate.punch_scale(label)           # grow a little, then settle back
```
4. Press *Ctrl+S* (*Cmd+S* on macOS) and save the scene, then *F6* (*Run Current Scene*).
5. You should see "Score: 0" fade in over one second. Press *Space* or *Enter* in the
   running window: the number goes up and the label pops bigger, then eases back. Press
   it quickly several times; the label still settles back to its normal size.
6. To adapt it: in `control(node, property, target, seconds)` the property path is text
   such as `"position:x"` or `"modulate:a"`, and the duration is in seconds. In
   `punch_scale(node, peak, seconds)`, `peak` is how big it gets (`1.15` is 15 % bigger).

## API

Everything the class offers; you only need the rows used above to get started.

### Constants

| Member | Description |
|---|---|
| `POP_ORIGIN_META` | Node meta key (`&"lf_animate_pop_origin"`) holding the position a node had before its first pop-in. |
| `DEFAULT_DURATION` | `0.3` — `control`'s default tween length in seconds. |
| `DEFAULT_PUNCH_PEAK` | `1.15` — `punch_scale`'s default peak, × the rest scale. |
| `DEFAULT_PUNCH_DURATION` | `0.35` — `punch_scale`'s default ease-back time in seconds. |
| `DEFAULT_POP_DURATION` | `0.35` — `comics_pop_appear`'s default length in seconds. |
| `DEFAULT_POP_OVERSHOOT` | `1.2` — `comics_pop_appear`'s default peak, × the rest scale. |
| `DEFAULT_POP_DRIFT` | `60.0` — `comics_pop_appear`'s default upward drift in px. |
| `DEFAULT_POP_TILT_DEGREES` | `20.0` — `comics_pop_appear`'s default largest tilt either way, in degrees. |
| `DEFAULT_FALL_DURATION` | `0.55` — `comics_pop_disappear`'s default length in seconds. |
| `DEFAULT_FALL_DISTANCE` | `300.0` — `comics_pop_disappear`'s default drop in px. |
| `DEFAULT_PAPER_DURATION` | `2.0` — `fall_paper`'s default length in seconds. |
| `DEFAULT_PAPER_SWAY_AMPLITUDE` | `100.0` — `fall_paper`'s default sideways sway in px. |
| `DEFAULT_PAPER_ROTATION_AMPLITUDE` | `15.0` — `fall_paper`'s default wobble in degrees. |
| `DEFAULT_PAPER_EXTRA_VERTICAL_MARGIN` | `100.0` — `fall_paper`'s default screen px past the bottom of the visible area. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `control` | `static control(node: Node, prop: NodePath, value: Variant, duration := DEFAULT_DURATION, tween_trans := Tween.TRANS_LINEAR, tween_ease := Tween.EASE_IN_OUT, replace := true) -> Tween` (0.3) | Tweens `node`'s property path `prop` to `value` and returns the tween, bound to `node`. With `replace`, kills the tween these helpers last started on an overlapping property path of the same node (`position` and `position:x` overlap, and so do aliases such as `position`/`global_position`; see Notes). Tweens you create yourself are not tracked. With `duration <= 0`, or `node` outside the tree, sets the value at once and returns an empty tween that finishes next frame (null without a running SceneTree); a property the node lacks is reported by the engine and gives the same empty tween. Works on any Node. |
| `punch_scale` | `static punch_scale(node: Node, peak := DEFAULT_PUNCH_PEAK, duration := DEFAULT_PUNCH_DURATION, center_pivot := true) -> Tween` (1.15, 0.35) | Sets the scale to `peak` × rest, then eases back to rest (`TRANS_BACK`/`EASE_OUT`). A punch during a punch or a pop-in starts from that animation's rest scale (where it would settle), not the mid-animation one. Centres a Control's pivot. Control, Node2D or Node3D; `null` for any other node. |
| `one_shot` | `static one_shot(node: Node, to: Dictionary, duration: float, tween_trans := Tween.TRANS_LINEAR, tween_ease := Tween.EASE_IN_OUT) -> Tween` | Tweens every `path -> value` in `to` in parallel over `duration`, then `queue_free()`s `node` (a path the node lacks is reported by the engine and skipped; the rest still run). Paths may reach into resources (`"material_override:albedo_color:a"`). Returns the tween, bound to `node`. |
| `comics_pop_appear` | `static comics_pop_appear(node: Variant, duration := DEFAULT_POP_DURATION, overshoot := DEFAULT_POP_OVERSHOOT, drift := DEFAULT_POP_DRIFT, tilt_degrees := DEFAULT_POP_TILT_DEGREES, rng: RandomNumberGenerator = null, center_pivot := true) -> bool` (0.35, 1.2, 60.0, 20.0) | Coroutine. Scales from 0 to `overshoot` × rest while fading in to full opacity in the node's own tint, tilts by a random angle within ±`tilt_degrees` (from `rng` when given; without one, Godot's global generator, with no error, since the tilt is cosmetic), drifts `drift` px up from its pre-pop position, then settles to the rest scale. Replaces a pop still running on the node; a pop during a `punch_scale` settles at the punch's rest scale, not its peak. `true` once done; `false` if not a Control/Node2D in the tree, or cut short. |
| `comics_pop_disappear` | `static comics_pop_disappear(node: Variant, duration := DEFAULT_FALL_DURATION, fall_distance := DEFAULT_FALL_DISTANCE) -> bool` (0.55, 300.0) | Coroutine. Stops a running pop-in, drops `node` by `fall_distance` while fading its alpha to 0 (tint kept), then puts it back at its pre-pop position and rest scale. `true` once done; `false` if not a Control/Node2D in the tree, or cut short. |
| `fall_paper` | `static fall_paper(node: Variant, duration: float = DEFAULT_PAPER_DURATION, sway_amplitude: float = DEFAULT_PAPER_SWAY_AMPLITUDE, rotation_amplitude: float = DEFAULT_PAPER_ROTATION_AMPLITUDE, extra_vertical_margin: float = DEFAULT_PAPER_EXTRA_VERTICAL_MARGIN) -> bool` (2.0, 100.0, 15.0, 100.0) | Coroutine. A Control or Node2D falls to `extra_vertical_margin` screen px below the visible area with an x sway and a rotation wobble (−amplitude, then +amplitude), then is `queue_free()`d (`true`). `false` for a freed node, a node outside the tree, one that leaves the tree mid-fall, or one whose fall a later helper call replaced (its tweens are killed, it returns at once, and the node is not freed). Claims `global_position:y` (the fall), `global_position:x` (the sway) and `rotation_degrees` (the wobble). |

## Usage

```gdscript
# hud.gd — on the HUD's root Control
extends Control

@onready var panel: Control = $Panel
@onready var score_label: Label = $ScoreLabel
@onready var bubble: Label = $SpeechBubble   # a Control outside any Container

func show_panel() -> void:
	panel.modulate.a = 0.0
	var tween := LFAnimate.control(panel, "modulate:a", 1.0, 0.3)   # fade in over 0.3 s
	await tween.finished

func set_score(value: int) -> void:
	score_label.text = str(value)
	LFAnimate.punch_scale(score_label)   # every change; overlapping punches settle at the normal size

func say(text: String) -> void:
	bubble.text = text
	await LFAnimate.comics_pop_appear(bubble)              # calling it again while it runs replaces the running pop
	await get_tree().create_timer(1.5).timeout
	await LFAnimate.comics_pop_disappear(bubble, 0.4, 200.0)

func discard(card: Control) -> void:
	LFAnimate.fall_paper(card)   # sways down off the screen; the card is freed when it lands
```

```gdscript
# unit_3d.gd — a hit number that rises, fades and frees itself
extends Node3D

func show_damage(amount: int) -> void:
	var label := Label3D.new()
	label.text = "-%d" % amount
	add_child(label)
	# On a Label3D fade `transparency`, not `modulate:a`: it fades the outline too.
	LFAnimate.one_shot(label, {"position:y": label.position.y + 1.0, "transparency": 1.0}, 0.8)
```

## Notes
- Every tween that animates is bound to its node (the empty tween `control` returns when it sets a value at once is not): it pauses when the node isn't processing (pausing the game freezes a pop mid-way, and it finishes after unpausing), it follows `Engine.time_scale` (the game's speed setting), and it ends when the node is freed.
- The helpers need the node inside the SceneTree. `control` on a node outside the tree sets the value at once (as it does for `duration <= 0`). `punch_scale` and `one_shot` on a node outside the tree return a tween that doesn't run until the node enters it; awaiting its `finished` waits until then. The coroutines return `false` at once instead.
- Replacing works on overlapping property paths: a path replaces the same path and any path reaching into it or that it reaches into (`"modulate"` and `"modulate:a"`, `"position"` and `"position:x"`), and a property that sets the same value under another name: `position`/`global_position`, `rotation`/`rotation_degrees`/`global_rotation`/`global_rotation_degrees`, `scale`/`global_scale`, and `transform`/`global_transform` with any of those (and `skew`). Parts of two such names overlap too (`"global_position:x"` and `"position:y"`, since a rotated parent mixes them). Not replaced: a sibling part of the same property (`"position:x"` and `"position:y"` both run) or a different property sharing a prefix (`"modulate"` and `"self_modulate"`). The whole earlier tween is killed, even if it also animated other properties. A pop-in claims `scale`, `modulate`, `rotation` and `position`; a pop-out claims `position` and `modulate`; `punch_scale` claims `scale`; `fall_paper` claims `global_position:y`, `global_position:x` and `rotation_degrees`, so a later pop or position tween stops its fall. For the same reason a `punch_scale` (or a `control` on `scale`, `modulate`, `rotation` or `position`) that starts during a pop-in ends that pop where it stands: its coroutine returns `false` and the node keeps the drift, tilt and fade reached so far. `one_shot` claims nothing: leave its node's properties to it, since its node is freed only if its tween finishes.
- A pop or a punch sets a Control's `pivot_offset` (the point it grows and rotates around) to its centre and leaves it there. Pass `center_pivot = false` to keep yours.
- Pop-ins remember the node's position from before the first pop (node meta `POP_ORIGIN_META`), so repeated pop-ins drift up from the same place. A pop-out restores that position and clears the meta. If you move the node yourself between a pop-in and a pop-out, call `node.remove_meta(LFAnimate.POP_ORIGIN_META)` first.
- `comics_pop_appear` leaves the node `drift` px above its pre-pop position and tilted; scale and tint are kept, and alpha ends at 1. `comics_pop_disappear` leaves `modulate.a` at 0, with its RGB untouched.
- Leaving the tree cancels a coroutine helper, and so does `reparent()` (it leaves and re-enters): the animation stops where it is and the helper returns `false`. A tween killed from outside also ends it with `false`.
- A Control inside a Container (a box that arranges its children, such as a VBoxContainer) gets its position and size reset the next time the container re-arranges. Animate a Control that is not inside one, or the container itself.
- `fall_paper` works in canvas space: it ends past the bottom of the visible area whatever the parent's transform or a `Camera2D`'s scroll.
