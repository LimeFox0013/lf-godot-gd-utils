## A one-way follower: a value that climbs smoothly after a target but only sinks slowly.
##
## The classic "camera that follows the player up a tower and never scrolls back down fast". Call
## `step(current, target, delta)` every frame with the follower's current value and the target's
## value; it returns the new value. Above the follower it eases after the target; below it, it
## drops at a fixed speed and stops at the target. It holds no state of its own, so it
## works on one axis of a camera, a Node2D or a Node3D, and on any number of followers.
class_name LFRatchetFollow
extends RefCounted

## How quickly a value catches up with a higher target, per second, when none is given.
const DEFAULT_FOLLOW_SPEED := 2.0

## How quickly the value catches up with a higher target. The gap shrinks by `1 - exp(-follow_speed * delta)`
## each step, so it behaves the same at any frame rate. 0 or less: never rises.
var follow_speed := DEFAULT_FOLLOW_SPEED
## How far the value drops per second towards a lower target, in value units. 0: never sinks.
var sink_speed := 0.0
## Added to the target before following (a camera that looks above or below the player).
var offset := 0.0
## The value never follows a target below this (the ground).
var min_value := -INF


## A follower with the given speeds; see `follow_speed` and `sink_speed`.
func _init(initial_follow_speed := DEFAULT_FOLLOW_SPEED, initial_sink_speed := 0.0) -> void:
	follow_speed = initial_follow_speed
	sink_speed = initial_sink_speed


## The value after `delta` seconds: eased up to `max(min_value, target + offset)` when that is
## above `current`, otherwise lowered by `sink_speed * delta` but never below it. `current` is
## returned unchanged for a `delta` of 0 or less, or a NaN `current`, `target` or `delta`.
func step(current: float, target: float, delta: float) -> float:
	if is_nan(current) or is_nan(target) or is_nan(delta) or delta <= 0.0:
		return current
	var desired := maxf(min_value, target + offset)
	if desired > current:
		return lerpf(current, desired, 1.0 - exp(-maxf(follow_speed, 0.0) * delta))
	return maxf(desired, current - maxf(sink_speed, 0.0) * delta)
