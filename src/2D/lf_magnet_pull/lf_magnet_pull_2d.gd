## Pulls a 2D body toward the attractors around it, each with its own power: pickups drawn
## to nearby points, orbs sliding toward a magnet.
##
## Keep one per pulled body. Your own code decides who is in range (an `Area2D`'s
## `body_entered` / `body_exited` is the usual way): call `set_attractor(node, power)` on
## enter and `remove_attractor(node)` on exit. Each physics frame call `step(position,
## delta)` and move the body with the result. The pull is `sum(direction * power) - velocity`
## added to the velocity every step (see `LFMagnetPullCore`): the body settles at the
## attractors' power and stops the moment none is left. Attractors that were freed or left
## the scene tree are skipped.
class_name LFMagnetPull2D
extends RefCounted

var _core := LFMagnetPullCore.new(Vector2.ZERO)

## The current pulled velocity, in units per second.
var velocity: Vector2:
	get:
		return _core.velocity


## Adds `attractor` with `power` (the speed in units per second a lone attractor settles
## the body at) or changes its power; `on = false` removes it. A NaN power is rejected:
## reported through `LFLogger` as an error, and nothing changes.
func set_attractor(attractor: Node2D, power: float, on := true) -> void:
	_core.set_attractor(attractor, power, on)


## Removes `attractor`; does nothing if it was not added.
func remove_attractor(attractor: Node2D) -> void:
	_core.remove_attractor(attractor)


## Whether `attractor` is currently added.
func has_attractor(attractor: Node2D) -> bool:
	return _core.has_attractor(attractor)


## How many added attractors are still alive and in the scene tree.
func attractor_count() -> int:
	return _core.attractor_count()


## Removes every attractor and zeroes the velocity.
func clear() -> void:
	_core.clear()


## `sum(direction * power) - velocity` for a body at `position` (global), without changing
## anything.
func force_at(position: Vector2) -> Vector2:
	return _core.force_at(position)


## Advances the velocity by `delta` seconds for a body at `position` (global) and returns
## it; zero when no live attractor is left.
func step(position: Vector2, delta: float) -> Vector2:
	return _core.step(position, delta)
