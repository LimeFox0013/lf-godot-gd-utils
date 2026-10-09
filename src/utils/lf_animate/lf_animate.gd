## Ready-made tweens for UI and effects: fade or move a property, punch a scale, pop in and out.
##
## Call everything on the class. It offers a property tween that replaces the previous one
## these helpers started on the same property (so two of them don't fight), a scale punch,
## an animate-then-free one-shot for floating labels and bursts, and canned "comic pop in",
## "fall out" and "paper fall" animations for Control/Node2D nodes. Every tween that
## animates is created on its node: it pauses with it and dies with it.
class_name LFAnimate

## Node meta holding the position a node had before its first pop-in, so repeated pop-ins
## drift from the same place instead of ratcheting; a pop-out restores it and clears it.
const POP_ORIGIN_META := &"lf_animate_pop_origin"
## Node meta holding the scale a node had before a pop-in; cleared when a pop ends.
const _POP_SCALE_META := &"lf_animate_pop_scale"
## Node meta holding {"node", "tween", "rest"} of the running punch_scale ("node" is the
## owner's instance id: `Node.duplicate()` copies metas, and a copy must not reuse it).
const _PUNCH_META := &"lf_animate_punch"
## Node meta holding {"node", "tweens"}: the owner's instance id, and a map from a property
## path to the last tween these helpers started on it. A copy made by `Node.duplicate()`
## carries the original's meta; the id tells it the tweens are not its own.
const _TWEENS_META := &"lf_animate_tweens"

## `control` default: seconds the tween takes.
const DEFAULT_DURATION := 0.3
## `punch_scale` default: the scale the node jumps to, as a multiple of its rest scale.
const DEFAULT_PUNCH_PEAK := 1.15
## `punch_scale` default: seconds the node takes to ease back to its rest scale.
const DEFAULT_PUNCH_DURATION := 0.35
## `comics_pop_appear` default: seconds the whole pop-in takes.
const DEFAULT_POP_DURATION := 0.35
## `comics_pop_appear` default: the peak scale, as a multiple of the rest scale.
const DEFAULT_POP_OVERSHOOT := 1.2
## `comics_pop_appear` default: pixels the node drifts up.
const DEFAULT_POP_DRIFT := 60.0
## `comics_pop_appear` default: the largest tilt either way, in degrees.
const DEFAULT_POP_TILT_DEGREES := 20.0
## `comics_pop_disappear` default: seconds the fall takes.
const DEFAULT_FALL_DURATION := 0.55
## `comics_pop_disappear` default: pixels the node drops.
const DEFAULT_FALL_DISTANCE := 300.0
## `fall_paper` default: seconds the fall takes.
const DEFAULT_PAPER_DURATION := 2.0
## `fall_paper` default: pixels the node sways to each side.
const DEFAULT_PAPER_SWAY_AMPLITUDE := 100.0
## `fall_paper` default: degrees the node wobbles to each side.
const DEFAULT_PAPER_ROTATION_AMPLITUDE := 15.0
## `fall_paper` default: screen pixels past the bottom of the visible area the fall ends at.
const DEFAULT_PAPER_EXTRA_VERTICAL_MARGIN := 100.0

## Key of the owner's instance id in the punch and tween metas.
const _KEY_NODE := "node"
## Key of the running tween in the punch meta.
const _KEY_TWEEN := "tween"
## Key of the rest scale in the punch meta.
const _KEY_REST := "rest"
## Key of the property path -> tween map in the tweens meta.
const _KEY_TWEENS := "tweens"
## What a node without a tween record reads instead: never written to.
static var _no_record := {}
## Separator between the parts of a property path ("position:x").
const _PATH_SEPARATOR := ":"

## Animated property: scale.
const _PROP_SCALE := "scale"
## Animated property: modulate (tint and opacity).
const _PROP_MODULATE := "modulate"
## Animated property: rotation, in radians.
const _PROP_ROTATION := "rotation"
## Animated property: rotation, in degrees.
const _PROP_ROTATION_DEGREES := "rotation_degrees"
## Animated property: position.
const _PROP_POSITION := "position"
## Animated property path: the global x position.
const _PROP_GLOBAL_X := "global_position:x"
## Animated property path: the global y position.
const _PROP_GLOBAL_Y := "global_position:y"
## The properties a pop-in animates.
const _POP_IN_PROPERTIES: Array[String] = [_PROP_SCALE, _PROP_MODULATE, _PROP_ROTATION, _PROP_POSITION]
## The properties a pop-out animates.
const _POP_OUT_PROPERTIES: Array[String] = [_PROP_POSITION, _PROP_MODULATE]
## Animated property: the whole transform (position, rotation, scale and skew at once).
const _PROP_TRANSFORM := "transform"
## Properties that set the same value as another one, by the name `_paths_overlap` treats
## them as (a global and a local position move the same node, degrees and radians turn it).
const _PROPERTY_ALIASES := {
	"global_position": _PROP_POSITION,
	"rotation_degrees": _PROP_ROTATION,
	"global_rotation": _PROP_ROTATION,
	"global_rotation_degrees": _PROP_ROTATION,
	"global_scale": _PROP_SCALE,
	"global_transform": _PROP_TRANSFORM,
}
## The properties a whole transform sets, so they overlap a transform tween.
const _TRANSFORM_PARTS: Array[String] = [_PROP_POSITION, _PROP_ROTATION, _PROP_SCALE, "skew"]

## Share of a pop-in's time spent growing to the overshoot scale.
const _POP_GROW_SHARE := 0.6
## Share of a pop-in's time spent fading in.
const _POP_FADE_SHARE := 0.3
## Share of a pop-in's time spent tilting.
const _POP_TILT_SHARE := 0.5
## Share of a pop-in's time spent drifting up.
const _POP_DRIFT_SHARE := 0.5
## Share of a pop-in's time spent settling back to the rest scale (after the growth).
const _POP_SETTLE_SHARE := 0.4
## Share of a pop-out's time spent fading out.
const _FALL_FADE_SHARE := 0.9
## Share of a paper fall's time each sway or wobble swing takes (two swings per fall).
const _PAPER_SWING_SHARE := 0.5


## Wakes a coroutine when a tween finishes, when its node leaves the tree, or when the
## tween dies without finishing (killed elsewhere, or freed with its node).
class _Wait:
	extends RefCounted
	signal done
	## True when the tween emitted `finished`.
	var finished := false
	var _fired := false
	var _node: Node
	var _tween: Tween

	func _init(node: Node, tween: Tween) -> void:
		_node = node
		_tween = tween

	func on_finished() -> void:
		finished = true
		_fire()

	func on_exiting() -> void:
		_fire()

	func poll() -> void:
		if not is_instance_valid(_node) or not _tween.is_valid():
			_fire()

	func _fire() -> void:
		if not _fired:
			_fired = true
			done.emit()


## Tweens `node`'s property `prop` (a property path such as "modulate:a" or
## "material_override:albedo_color") to `value` over `duration` seconds and returns the
## tween. The tween is bound to `node`: it pauses with the node and dies with it. With
## `replace`, an earlier tween these helpers started on an overlapping property path of
## the same node is killed first, so the newest call has the last word among these helpers'
## tweens (tweens you create yourself are not tracked). Paths overlap when one reaches into
## the other ("position" and "position:x"), or when they name the same value another way:
## position/global_position, rotation/rotation_degrees/global_rotation(_degrees),
## scale/global_scale, and transform/global_transform with any of those (and skew). With `duration <= 0`, or `node` outside the tree, the value is
## set at once and the returned tween is an empty one that finishes on the next frame
## (null without a running SceneTree). A property `node` doesn't have is reported by the
## engine, nothing is animated, and the result is that same empty tween.
static func control(
	node: Node,
	prop: NodePath,
	value: Variant,
	duration := DEFAULT_DURATION,
	tween_trans := Tween.TRANS_LINEAR,
	tween_ease := Tween.EASE_IN_OUT,
	replace := true,
) -> Tween:
	if duration <= 0.0 or not node.is_inside_tree():
		if replace:
			_claim_path(node, String(prop), null)
		node.set_indexed(prop, value)
		return _finished_tween()
	var tween := node.create_tween()
	var step := tween.tween_property(node, prop, value, duration)
	if step == null: # the engine reported the missing property
		tween.kill()
		return _finished_tween()
	step.set_trans(tween_trans).set_ease(tween_ease)
	if replace:
		_claim_path(node, String(prop), tween)
	return tween


## Sets `node`'s scale to `peak` times its rest scale, then eases it back to rest over
## `duration` seconds with a slight overshoot, and returns the tween. A punch while another
## punch or a pop-in runs starts from that animation's rest scale (the one it would settle
## at), so overlapping punches and pops don't leave the node grown or shrunk. A Control is
## scaled about its centre (its pivot_offset is set to the middle). Works on Control,
## Node2D and Node3D; returns null for any other node.
static func punch_scale(node: Node, peak := DEFAULT_PUNCH_PEAK, duration := DEFAULT_PUNCH_DURATION, center_pivot := true) -> Tween:
	if not (node is Control or node is Node2D or node is Node3D):
		return null
	var rest: Variant = _running_punch_rest(node)
	if rest == null:
		# A pop-in still running on the node: its rest scale, not the mid-pop one.
		var pop_running := node.has_meta(_POP_SCALE_META) and _running_tween(node, _PROP_SCALE) != null
		rest = node.get_meta(_POP_SCALE_META) if pop_running else node.scale
	if center_pivot and node is Control:
		node.pivot_offset = node.size / 2.0
	node.scale = rest * peak
	var tween := node.create_tween()
	tween.tween_property(node, _PROP_SCALE, rest, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_claim_path(node, _PROP_SCALE, tween)
	node.set_meta(_PUNCH_META, {_KEY_NODE: node.get_instance_id(), _KEY_TWEEN: tween, _KEY_REST: rest})
	tween.finished.connect(node.remove_meta.bind(_PUNCH_META))
	return tween


## Tweens every property path in `to` (path -> target value) in parallel over `duration`
## seconds, then frees `node`; for transient effects such as floating labels and bursts.
## Returns the tween, bound to `node`. Paths may reach into resources, e.g.
## "material_override:albedo_color:a". The node is freed only if the tween finishes, so
## leave its properties to it.
static func one_shot(
	node: Node,
	to: Dictionary,
	duration: float,
	tween_trans := Tween.TRANS_LINEAR,
	tween_ease := Tween.EASE_IN_OUT,
) -> Tween:
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_interval(duration)
	for prop: Variant in to:
		var step := tween.tween_property(node, NodePath(str(prop)), to[prop], duration)
		if step != null: # a missing property was reported by the engine; the rest still run
			step.set_trans(tween_trans).set_ease(tween_ease)
	tween.finished.connect(node.queue_free)
	return tween


## Coroutine. Pops `node` in: scales from 0 to `overshoot` times its rest scale while fading
## in to full opacity (keeping its tint), tilts by a random angle within ±`tilt_degrees`
## (drawn from `rng` when given; without one, from Godot's global generator with no error,
## since the tilt is cosmetic) and drifts `drift` px up from the
## position it had before its first pop, then settles to its rest scale. A Control scales
## about its centre with `center_pivot` (its pivot_offset is left at the middle). A pop
## replaces any pop still running on the node, from the same rest scale; a pop during a
## punch_scale settles at the punch's rest scale, not its peak. Returns `true`
## once done; `false` if `node` is not a Control/Node2D inside the tree, or the pop was cut
## short (the node left the tree, or its tween was killed or replaced).
static func comics_pop_appear(
	node: Variant,
	duration := DEFAULT_POP_DURATION,
	overshoot := DEFAULT_POP_OVERSHOOT,
	drift := DEFAULT_POP_DRIFT,
	tilt_degrees := DEFAULT_POP_TILT_DEGREES,
	rng: RandomNumberGenerator = null,
	center_pivot := true,
) -> bool:
	if not _is_2d_in_tree(node):
		return false

	if not node.has_meta(_POP_SCALE_META):
		var punch_rest: Variant = _running_punch_rest(node)
		node.set_meta(_POP_SCALE_META, node.scale if punch_rest == null else punch_rest)
	var rest_scale: Vector2 = node.get_meta(_POP_SCALE_META)
	if not node.has_meta(POP_ORIGIN_META):
		node.set_meta(POP_ORIGIN_META, node.position)
	var origin: Vector2 = node.get_meta(POP_ORIGIN_META)
	var shown: Color = node.modulate
	shown.a = 1.0
	var hidden := shown
	hidden.a = 0.0
	if center_pivot and node is Control:
		node.pivot_offset = node.size / 2.0

	node.scale = Vector2.ZERO
	node.modulate = hidden
	node.rotation = 0.0
	node.position = origin

	var tween: Tween = node.create_tween()
	tween.set_parallel(true)

	tween.tween_property(node, _PROP_SCALE, rest_scale * overshoot, duration * _POP_GROW_SHARE)\
		.from(Vector2.ZERO)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

	tween.tween_property(node, _PROP_MODULATE, shown, duration * _POP_FADE_SHARE).from(hidden)

	var tilt := 0.0
	if tilt_degrees != 0.0:
		tilt = rng.randf_range(-tilt_degrees, tilt_degrees) if rng != null else randf_range(-tilt_degrees, tilt_degrees)
	tween.tween_property(node, _PROP_ROTATION, deg_to_rad(tilt), duration * _POP_TILT_SHARE).from(0.0)

	tween.tween_property(node, _PROP_POSITION, origin + Vector2(0, -drift), duration * _POP_DRIFT_SHARE)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)

	tween.set_parallel(false)

	tween.tween_property(node, _PROP_SCALE, rest_scale, duration * _POP_SETTLE_SHARE)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_IN_OUT)

	_claim(node, _POP_IN_PROPERTIES, tween)
	if not await _finished_or_gone(node, [tween]):
		return false
	node.remove_meta(_POP_SCALE_META)
	return true


## Coroutine. Drops `node` by `fall_distance` px while fading it out over `duration`
## seconds (keeping its tint), then puts it back where it was before its last pop-in (or
## where it started, if it never popped in), at its rest scale. A pop-out stops a pop-in
## still running. Returns `true` once done; `false` if `node` is not a Control/Node2D inside
## the tree, or the pop-out was cut short.
static func comics_pop_disappear(
	node: Variant,
	duration := DEFAULT_FALL_DURATION,
	fall_distance := DEFAULT_FALL_DISTANCE,
) -> bool:
	if not _is_2d_in_tree(node):
		return false

	var start_position: Vector2 = node.position
	var rest_position: Vector2 = node.get_meta(POP_ORIGIN_META, start_position)
	var hidden: Color = node.modulate
	hidden.a = 0.0

	var tween: Tween = node.create_tween()
	tween.set_parallel(true)

	tween.tween_property(node, _PROP_POSITION, start_position + Vector2(0, fall_distance), duration)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)

	tween.tween_property(node, _PROP_MODULATE, hidden, duration * _FALL_FADE_SHARE)

	_claim(node, _POP_OUT_PROPERTIES, tween)
	if not await _finished_or_gone(node, [tween]):
		return false
	node.position = rest_position
	if node.has_meta(_POP_SCALE_META):
		node.scale = node.get_meta(_POP_SCALE_META)
		node.remove_meta(_POP_SCALE_META)
	if node.has_meta(POP_ORIGIN_META):
		node.remove_meta(POP_ORIGIN_META)
	return true


## Coroutine. Drops `node` (Control or Node2D) to `extra_vertical_margin` screen px past the
## bottom of the visible area over `duration` seconds with a sideways sway and a rotation
## wobble, then frees it. The fall is in canvas space, so it ends past the bottom whatever
## the parent's transform or the camera's scroll. Returns `true` once it fell and was
## queued for freeing (`queue_free`); `false` if `node` was freed, not a Control/Node2D or
## outside the tree, or left the tree mid-fall (the helper then returns at once rather than
## waiting), or a later helper call replaced its fall (a `control` on a position path, a
## pop): the fall then stops where it is and the node is not freed.
## The sway and wobble are replaceable the same way, without stopping the fall.
static func fall_paper(
	node: Variant,
	duration: float = DEFAULT_PAPER_DURATION,
	sway_amplitude: float = DEFAULT_PAPER_SWAY_AMPLITUDE,
	rotation_amplitude: float = DEFAULT_PAPER_ROTATION_AMPLITUDE,
	extra_vertical_margin: float = DEFAULT_PAPER_EXTRA_VERTICAL_MARGIN,
) -> bool:
	if not _is_2d_in_tree(node):
		return false
	var item: CanvasItem = node

	# Canvas -> viewport; the visible rect is in viewport coordinates.
	var canvas_to_view := item.get_canvas_transform()
	var visible := item.get_viewport().get_visible_rect()
	var start: Vector2 = node.global_position
	var start_on_screen := canvas_to_view * start
	var end_on_screen := Vector2(start_on_screen.x, visible.end.y + extra_vertical_margin)
	var end_y := (canvas_to_view.affine_inverse() * end_on_screen).y

	var fall_tween := item.create_tween()
	fall_tween.tween_property(item, _PROP_GLOBAL_Y, end_y, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN)
	_claim_path(item, _PROP_GLOBAL_Y, fall_tween)

	var sway_tween := item.create_tween()
	sway_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway_tween.tween_property(item, _PROP_GLOBAL_X, start.x + sway_amplitude, duration * _PAPER_SWING_SHARE)
	sway_tween.tween_property(item, _PROP_GLOBAL_X, start.x - sway_amplitude, duration * _PAPER_SWING_SHARE)
	_claim_path(item, _PROP_GLOBAL_X, sway_tween)

	var base_rot: float = node.rotation_degrees
	var rot_tween := item.create_tween()
	rot_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	rot_tween.tween_property(item, _PROP_ROTATION_DEGREES, base_rot - rotation_amplitude, duration * _PAPER_SWING_SHARE)
	rot_tween.tween_property(item, _PROP_ROTATION_DEGREES, base_rot + rotation_amplitude, duration * _PAPER_SWING_SHARE)
	_claim_path(item, _PROP_ROTATION_DEGREES, rot_tween)

	# All tweens have the same total duration, so awaiting the fall is enough.
	if not await _finished_or_gone(item, [fall_tween, sway_tween, rot_tween]):
		return false

	item.queue_free()
	return true


static func _is_2d_in_tree(node: Variant) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return (node is Control or node is Node2D) and node.is_inside_tree()


## The rest scale of the punch_scale running on `node`, or null when none is.
static func _running_punch_rest(node: Node) -> Variant:
	var running: Dictionary = node.get_meta(_PUNCH_META, {})
	var running_tween: Tween = running.get(_KEY_TWEEN)
	if running.get(_KEY_NODE) == node.get_instance_id() and running_tween != null and running_tween.is_valid():
		return running[_KEY_REST]
	return null


## The tween these helpers last started on exactly `property` of `node` if it is still
## running, else null.
static func _running_tween(node: Node, property: String) -> Tween:
	var stored: Dictionary = node.get_meta(_TWEENS_META, _no_record)
	if stored.get(_KEY_NODE) != node.get_instance_id():
		return null
	var tween: Tween = (stored[_KEY_TWEENS] as Dictionary).get(property)
	return tween if tween != null and tween.is_valid() else null


## Kills the tweens these helpers last started on `properties` of `node`, or on a path
## overlapping one of them (other than `tween`), and records `tween` as the one running on
## each of them (a null `tween` records nothing). Dead entries are dropped on the way.
static func _claim(node: Node, properties: Array, tween: Tween) -> void:
	for key: String in properties:
		_claim_path(node, key, tween)


## `_claim` for one property path. The node's record is changed in place when it is its
## own (a duplicated node's copied record names the original and is replaced instead).
static func _claim_path(node: Node, key: String, tween: Tween) -> void:
	var stored: Dictionary = node.get_meta(_TWEENS_META, _no_record)
	var own: bool = stored.get(_KEY_NODE) == node.get_instance_id()
	var tweens: Dictionary = stored[_KEY_TWEENS] if own else {}
	var dropped: Variant = null # made only when something is dropped
	for other: String in tweens:
		var previous: Tween = tweens[other]
		if previous == tween:
			continue
		var dead := not previous.is_valid()
		if dead or _paths_overlap(key, other):
			if not dead:
				previous.kill()
			if dropped == null:
				dropped = []
			dropped.append(other)
	if dropped != null:
		for other: String in dropped:
			tweens.erase(other)
	if tween != null:
		tweens[key] = tween
	if tweens.is_empty():
		if node.has_meta(_TWEENS_META):
			node.remove_meta(_TWEENS_META)
	elif not own:
		node.set_meta(_TWEENS_META, {_KEY_NODE: node.get_instance_id(), _KEY_TWEENS: tweens})


## Whether two property paths animate some of the same value: equal, one reaching into
## the other ("position" and "position:x", "modulate" and "modulate:a"), or properties
## that set the same value another way (`_PROPERTY_ALIASES`: "global_position:x" and
## "position", "rotation" and "rotation_degrees", a transform and its parts). Two parts of
## one property ("position:x", "position:y") don't overlap; parts of two aliased properties
## ("global_position:x", "position:y") do, since a parent's rotation can mix them.
static func _paths_overlap(a: String, b: String) -> bool:
	if a == b or a.begins_with(b + _PATH_SEPARATOR) or b.begins_with(a + _PATH_SEPARATOR):
		return true
	var name_a := a.get_slice(_PATH_SEPARATOR, 0)
	var name_b := b.get_slice(_PATH_SEPARATOR, 0)
	if name_a == name_b:
		return false
	var value_a: String = _PROPERTY_ALIASES.get(name_a, name_a)
	var value_b: String = _PROPERTY_ALIASES.get(name_b, name_b)
	if value_a == value_b:
		return true
	if value_a == _PROP_TRANSFORM:
		return value_b in _TRANSFORM_PARTS
	if value_b == _PROP_TRANSFORM:
		return value_a in _TRANSFORM_PARTS
	return false


## An empty tween on the SceneTree that finishes on the next frame, for callers that
## await what `control` returns; null without a running SceneTree.
static func _finished_tween() -> Tween:
	var tree := LFUtils.tree_root
	if tree == null:
		return null
	var tween := tree.create_tween()
	tween.tween_interval(0.0)
	return tween


## Awaits the first tween's `finished`, `node` leaving the tree, or the first tween dying
## without finishing, whichever comes first. On an early exit every given tween is killed.
## Returns whether the tween finished with the node still valid.
static func _finished_or_gone(node: Node, tweens: Array) -> bool:
	var main: Tween = tweens[0]
	var tree := node.get_tree()
	var wait := _Wait.new(node, main)
	main.finished.connect(wait.on_finished)
	node.tree_exiting.connect(wait.on_exiting)
	tree.process_frame.connect(wait.poll)
	await wait.done

	tree.process_frame.disconnect(wait.poll)
	var valid := is_instance_valid(node)
	if valid and node.tree_exiting.is_connected(wait.on_exiting):
		node.tree_exiting.disconnect(wait.on_exiting)
	if wait.finished and valid:
		return true
	for tween: Tween in tweens:
		if tween.is_valid():
			tween.kill()
	return false
