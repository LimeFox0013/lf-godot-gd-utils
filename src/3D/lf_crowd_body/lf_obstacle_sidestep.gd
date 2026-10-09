## Lets a walking 3D character step around a wall it bumps into head-on, instead of getting stuck.
##
## Steering for a CharacterBody3D that meets a wall nearly head-on. Sliding along a face
## met square-on leaves almost no speed, so a body pressing into one would stand still;
## instead it steps along the face at full speed for a moment — the way the slide already
## leans, or toward its destination when it hit dead centre, or the other way when
## `test_move` says that side is blocked too — and keeps the same side when it meets the
## same face again soon after, so it doesn't dither in front of it. One per body.
class_name LFObstacleSidestep
extends RefCounted

## Default `head_on_dot`, a cosine (0.9 = within about 26° of square-on).
const DEFAULT_HEAD_ON_DOT := 0.9
## Default `dead_center_slide`, a sideways lean (0..1).
const DEFAULT_DEAD_CENTER_SLIDE := 0.05
## Default `probe_distance`, in world units.
const DEFAULT_PROBE_DISTANCE := 0.5
## Default `hold_seconds`, how long a sidestep is held.
const DEFAULT_HOLD_SECONDS := 0.4
## Default `memory_seconds`, how long the last side is remembered.
const DEFAULT_MEMORY_SECONDS := 2.0

## The same face: the last sidestep runs nearly along the new wall (|dot| below this).
const _SAME_FACE_DOT := 0.3
## A wall normal shorter than this once flattened (world units) is a floor or ceiling,
## not a wall.
const _FLAT_NORMAL_EPSILON := 0.001
## How far off the face the free-side probe starts, as a fraction of `probe_distance`.
const _PROBE_OFF_FACE_FRACTION := 0.2

## How squarely a body must be heading into a wall before it steps along it instead of
## sliding: the cosine between the heading and the direction into the wall (1 = dead
## square, 0.9 = within about 26°).
var head_on_dot := DEFAULT_HEAD_ON_DOT
## Below this much sideways lean (0..1), a head-on bump counts as dead centre and the side
## is picked toward the destination.
var dead_center_slide := DEFAULT_DEAD_CENTER_SLIDE
## How far ahead (world units) a sidestep checks that its side is free.
var probe_distance := DEFAULT_PROBE_DISTANCE
## How long a sidestep is held, in seconds.
var hold_seconds := DEFAULT_HOLD_SECONDS
## How long (seconds) after a sidestep a body meeting the same face keeps the same side.
var memory_seconds := DEFAULT_MEMORY_SECONDS

var _side := Vector3.ZERO
var _left := 0.0
var _age := INF


## A sidestep steering; each argument sets the property of the same meaning: turn along
## a wall met within `square_dot` of square-on (`head_on_dot`), checking `distance` world
## units ahead (`probe_distance`), holding it `hold` seconds (`hold_seconds`), remembering
## the side for `remember` seconds (`memory_seconds`).
func _init(square_dot := DEFAULT_HEAD_ON_DOT, distance := DEFAULT_PROBE_DISTANCE, hold := DEFAULT_HOLD_SECONDS, remember := DEFAULT_MEMORY_SECONDS) -> void:
	head_on_dot = square_dot
	probe_distance = distance
	hold_seconds = hold
	memory_seconds = remember


## Returns the direction `body` should move this frame: `direction` (unchanged) unless
## the body is pressing into a wall nearly head-on (`body.is_on_wall()` from its last
## `move_and_slide()`), when it is a unit-length step along the wall, held for
## `hold_seconds`.
## `to_destination` (from the body to where it is going) picks the side at dead centre.
## Call once per physics frame, before `move_and_slide()`, with that frame's `delta`.
## The result has no speed: multiply it by yours.
func steer(body: CharacterBody3D, direction: Vector3, to_destination: Vector3, delta: float) -> Vector3:
	_age += delta
	if _left > 0.0:
		_left -= delta
		return _side
	if !body.is_on_wall():
		return direction
	var normal := body.get_wall_normal()
	normal.y = 0.0
	# A body whose `up_direction` is not world up can report a level surface as a wall.
	if normal.length() < _FLAT_NORMAL_EPSILON:
		return direction
	normal = normal.normalized()
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	if flat.dot(-normal) < head_on_dot:
		return direction
	var side := flat - normal * flat.dot(normal)
	if _age < memory_seconds and absf(_side.dot(normal)) < _SAME_FACE_DOT:
		side = _side
	elif side.length() > dead_center_slide:
		side = side.normalized()
	else:
		side = normal.cross(Vector3.UP)
		if side.dot(to_destination) < 0.0:
			side = -side
	# Probed from just off the face, which would otherwise count as in the way itself.
	var off_face := body.global_transform.translated(normal * probe_distance * _PROBE_OFF_FACE_FRACTION)
	if body.test_move(off_face, side * probe_distance):
		side = -side
	_side = side
	_left = hold_seconds
	_age = 0.0
	return side


## Returns whether a sidestep is being held right now.
func is_sidestepping() -> bool:
	return _left > 0.0


## Ends any sidestep and forgets the last side (after a teleport or a new destination).
func reset() -> void:
	_side = Vector3.ZERO
	_left = 0.0
	_age = INF
