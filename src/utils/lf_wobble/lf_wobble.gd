## A number that wobbles like a bobblehead's head: pushed by what its owner does, it lags, overshoots and settles.
##
## It is a damped spring simulated in code, not a physics body: it has no collider and never moves
## its owner. Each frame call `step(delta, drive)` with the push of that moment (for a head, the
## opposite of the body's acceleration) and read `value` (for a head, its tilt). It rests at 0.
class_name LFWobble
extends RefCounted

## Pull back to rest, per second squared, when none is given.
const DEFAULT_STIFFNESS := 160.0
## Slowdown, per second, when none is given. Below 2 times the square root of the stiffness it wobbles; at or above that it settles without overshooting.
const DEFAULT_DAMPING := 7.0
## The longest slice of time simulated in one go; a longer `delta` is cut into slices of this size so a slow frame cannot blow it up.
const MAX_SLICE := 1.0 / 120.0
## The most slices one `step` simulates; the rest of a very long `delta` is dropped.
const MAX_SLICES := 12

## How hard it is pulled back to 0 (per second squared). Higher is a stiffer, faster wobble.
var stiffness := DEFAULT_STIFFNESS
## How quickly the wobble dies out (per second). Higher settles sooner.
var damping := DEFAULT_DAMPING
## The value never goes beyond this in either direction (its speed is dropped there). `INF`: no limit.
var limit := INF
## Where it is now, away from rest.
var value := 0.0
## How fast it is moving now, in value units per second.
var velocity := 0.0


## A wobble with the given stiffness and damping; see `stiffness` and `damping`.
func _init(initial_stiffness := DEFAULT_STIFFNESS, initial_damping := DEFAULT_DAMPING) -> void:
	stiffness = initial_stiffness
	damping = initial_damping


## Moves on by `delta` seconds under `drive` (a steady push in value units per second squared) and returns `value`.
## Does nothing for a `delta` of 0 or less, or a NaN `delta` or `drive`.
func step(delta: float, drive := 0.0) -> float:
	if is_nan(delta) or is_nan(drive) or delta <= 0.0:
		return value
	var span := minf(delta, MAX_SLICE * MAX_SLICES)
	var slices := clampi(ceili(span / MAX_SLICE), 1, MAX_SLICES)
	var slice := span / slices
	for i in slices:
		velocity += (drive - stiffness * value - damping * velocity) * slice
		value += velocity * slice
		var cap := absf(limit)
		if absf(value) > cap:
			value = signf(value) * cap
			velocity = 0.0
	return value


## Adds `impulse` to the speed: a hit that shakes it.
func kick(impulse: float) -> void:
	if not is_nan(impulse):
		velocity += impulse


## Back to rest at once.
func reset() -> void:
	value = 0.0
	velocity = 0.0
