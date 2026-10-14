## An Area3D that flies in a straight line to a fixed aim point, ends on the first area it
## enters or on arriving, and goes back to its `LFFactory` pool (or frees itself).
##
## The aim point is a position, not a target, so a target that moves away is missed. A hit
## is any Area3D entering this one, so set the collision layer and mask to what it should
## touch. Extend it to decide which areas count (`_accepts_area`) and what a hit does
## (`_landed_on`); the base class only finishes the flight.
class_name LFProjectile3D
extends Area3D

## Distances at or below this have no direction to fly in.
const _MIN_DISTANCE := 0.001

## The pool this projectile was taken from; it goes back there when done. Without one it
## frees itself.
var pool: LFFactory = null

var _direction := Vector3.ZERO
var _speed := 0.0
var _aim_point := Vector3.ZERO
var _traveled := 0.0
var _max_distance := 0.0
var _launched := false


func _ready() -> void:
	area_entered.connect(_on_area_entered)


## Starts flying from `origin` toward `aim_point` at `speed` (units per second): call it
## once per shot, after adding the node or taking it from its pool. Switching `monitoring`
## and `monitorable` on is deferred, in order with `reset`'s, so a projectile reset inside
## a hit and launched again in the same frame ends up enabled.
func launch_to(origin: Vector3, aim_point: Vector3, speed: float) -> void:
	global_position = origin
	_aim_point = aim_point
	_speed = speed
	var to_aim := aim_point - origin
	_max_distance = to_aim.length()
	_direction = to_aim.normalized() if _max_distance > _MIN_DISTANCE else Vector3.ZERO
	_traveled = 0.0
	_launched = true
	visible = true
	set_physics_process(true)
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)


## Back to idle: not flying, hidden, and detecting and detectable by nothing (both deferred,
## because the engine refuses to change them inside an overlap callback). Called when it
## returns to its pool; override it to clear your own state and call `super()`.
func reset() -> void:
	_launched = false
	_direction = Vector3.ZERO
	_speed = 0.0
	_aim_point = Vector3.ZERO
	_traveled = 0.0
	_max_distance = 0.0
	visible = false
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)


## Whether it is in flight (launched and not yet finished).
func is_flying() -> bool:
	return _launched


## Override: whether `area` counts as a hit. Areas it returns false for are flown through.
func _accepts_area(_area: Area3D) -> bool:
	return true


## Override: called once with the first accepted `area`. The base ends the flight; an
## override that reads its own state should do so before calling `super()`, because ending
## the flight resets a pooled projectile.
func _landed_on(_area: Area3D) -> void:
	_finish()


## Ends the flight: back to `pool` (which should call `reset`), or freed without one.
func _finish() -> void:
	_launched = false
	if pool != null and pool.owns(self):
		pool.release(self)
	else:
		queue_free()


func _physics_process(delta: float) -> void:
	if not _launched:
		return
	var step := _speed * delta
	global_position += _direction * step
	_traveled += step
	if _traveled >= _max_distance:
		_finish()


func _on_area_entered(area: Area3D) -> void:
	if not _launched:
		return
	if not _accepts_area(area):
		return
	_landed_on(area)
