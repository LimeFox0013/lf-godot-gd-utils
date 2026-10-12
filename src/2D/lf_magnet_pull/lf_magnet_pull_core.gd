## The math behind LFMagnetPull2D and LFMagnetPull3D, written once for both: a velocity
## pulled toward attractors, each with its own power. Create the 2D or 3D class instead;
## this one works on untyped vectors so a single tested core serves both.
##
## Every step the pull is `sum(direction_to_attractor * power) - velocity`, added to the
## velocity after scaling by `delta`. The `- velocity` term is drag: the speed settles
## where the summed powers balance it (for one attractor, at its `power`), so a body
## glides toward the attractor instead of accelerating forever. With no attractors left
## the velocity drops to zero at once.
class_name LFMagnetPullCore
extends RefCounted

static var _log := LFLogger.new()

## The current pulled velocity (a Vector2 or a Vector3, matching `zero`). Read it to move
## the body; `step` updates it.
var velocity: Variant

var _zero: Variant
var _attractors: Dictionary = {}


## `zero` is the zero vector of the space the core works in (`Vector2.ZERO` or `Vector3.ZERO`).
func _init(zero: Variant) -> void:
	_zero = zero
	velocity = zero


## Adds `attractor` with `power` (units per second the body settles at), or changes its
## power if it is already there; with `on = false` removes it, like `remove_attractor`.
## The attractor needs a `global_position` property (a Node2D or Node3D). A NaN power is
## rejected: reported through `LFLogger` as an error, and nothing changes.
func set_attractor(attractor: Node, power: float, on := true) -> void:
	if not on:
		remove_attractor(attractor)
		return
	if is_nan(power):
		_log.error("LFMagnetPullCore: a NaN power is rejected for %s" % attractor)
		return
	_attractors[attractor.get_instance_id()] = {"node": weakref(attractor), "power": power}


## Removes `attractor`; does nothing if it was not added.
func remove_attractor(attractor: Node) -> void:
	_attractors.erase(attractor.get_instance_id())


## Whether `attractor` is currently added.
func has_attractor(attractor: Node) -> bool:
	return _attractors.has(attractor.get_instance_id())


## Removes every attractor and zeroes the velocity.
func clear() -> void:
	_attractors.clear()
	velocity = _zero


## How many added attractors are still alive and in the scene tree.
func attractor_count() -> int:
	_prune()
	return _attractors.size()


## `sum(direction * power) - velocity` for a body at `position`, without changing anything.
## An attractor exactly at `position` has no direction and adds nothing. Freed attractors
## and ones outside the scene tree are skipped. With none left it is the zero vector.
func force_at(position: Variant) -> Variant:
	_prune()
	if _attractors.is_empty():
		return _zero
	var total: Variant = _zero
	for entry: Dictionary in _attractors.values():
		var node: Node = entry["node"].get_ref()
		var offset: Variant = node.get("global_position") - position
		var distance: float = offset.length()
		if distance == 0.0:
			continue
		total += offset / distance * float(entry["power"])
	return total - velocity


## Advances the velocity by one step of `delta` seconds for a body at `position` and
## returns it. With no live attractor the velocity becomes zero.
func step(position: Variant, delta: float) -> Variant:
	if attractor_count() == 0:
		velocity = _zero
		return velocity
	velocity += force_at(position) * delta
	return velocity


func _prune() -> void:
	for id: int in _attractors.keys():
		var node: Node = _attractors[id]["node"].get_ref()
		if node == null or not node.is_inside_tree():
			_attractors.erase(id)
