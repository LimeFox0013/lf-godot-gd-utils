## An endless, gentle drift of a Control or Node2D around its base position, for floating
## bubbles, hovering pickups and idle icons.
##
## `LFIdleDrift.start(node)` adds a child to the node that moves it along a Lissajous-style
## curve (the x and y swings have different speeds, so the path does not repeat quickly)
## every frame. It lives and pauses with the node and is freed with it. Set `paused` to hold
## the node where it is (for example while it is hovered) and clear it to carry on.
## 2D only (Control and Node2D).
class_name LFIdleDrift
extends Node

## `start` default: the largest distance from the base position along each axis, in
## pixels.
const DEFAULT_AMPLITUDE := Vector2(6.0, 8.0)
## `start` default: full swings per second along x.
const DEFAULT_SPEED := 0.25
## The y swing's speed as a multiple of the x swing's, so the two drift out of step.
const Y_SPEED_RATIO := 0.73

## The node being moved.
var target: Variant
## The point the node drifts around. Move the node by setting this, not its `position`.
var base_position := Vector2.ZERO
## The largest distance from `base_position` along each axis, in pixels.
var amplitude := DEFAULT_AMPLITUDE
## Full swings per second along x (y swings at `Y_SPEED_RATIO` times this).
var speed := DEFAULT_SPEED
## Where the y swing is in its cycle at time zero, in radians. `start` draws it at random;
## it is why two nodes started together do not move in step.
var phase := 0.0
## While true the node stays where it is and the drift's clock stands still.
var paused := false
## Seconds of drift played so far (excluding time spent paused).
var elapsed := 0.0


## Starts a drift on `node` (a Control or Node2D) around its current position and returns
## it; `null` if `node` is not a Control/Node2D. `rng` draws the starting `phase` (without
## one, Godot's global generator does). Note that the first frame can move the node up to
## `amplitude.y` from its base position. Two drifts on one node fight; `stop` the first.
static func start(
	node: Variant,
	drift_amplitude := DEFAULT_AMPLITUDE,
	drift_speed := DEFAULT_SPEED,
	rng: RandomNumberGenerator = null,
) -> LFIdleDrift:
	if node == null or not is_instance_valid(node) or not (node is Control or node is Node2D):
		return null
	var drift := LFIdleDrift.new()
	drift.target = node
	drift.base_position = node.position
	drift.amplitude = drift_amplitude
	drift.speed = drift_speed
	drift.phase = (rng.randf() if rng != null else randf()) * TAU
	node.add_child(drift)
	return drift


## Stops the drift and frees it. With `restore`, the node goes back to `base_position`.
func stop(restore := true) -> void:
	paused = true # it is freed at the end of the frame; until then it must not move the node
	if restore and is_instance_valid(target):
		target.position = base_position
	queue_free()


## Advances the drift by `delta` seconds (unless `paused`) and moves the node. Called every
## frame; call it yourself to step a drift by hand.
func step(delta: float) -> void:
	if paused or not is_instance_valid(target):
		return
	elapsed += delta
	target.position = base_position + offset_at(elapsed)


## The offset from `base_position` after `seconds` of drift.
func offset_at(seconds: float) -> Vector2:
	var angle := seconds * TAU * speed
	return Vector2(sin(angle) * amplitude.x, sin(angle * Y_SPEED_RATIO + phase) * amplitude.y)


func _process(delta: float) -> void:
	step(delta)
