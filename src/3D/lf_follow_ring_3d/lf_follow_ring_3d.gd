## A pulsing ring on the ground that follows a Node3D and hides when there is none.
##
## Set `target` to the node to circle: the ring sits at its position, lifted by `lift`, and
## pulses its scale. It hides when `target` is null, freed or outside the tree, and only
## processes while visible. The ring is a flat torus seen from above.
class_name LFFollowRing3D
extends Node3D

## Default inner radius of the ring, in world units.
const DEFAULT_INNER_RADIUS := 1.1
## Default outer radius of the ring, in world units.
const DEFAULT_OUTER_RADIUS := 1.3
## Default colour of the ring (its alpha is the opacity).
const DEFAULT_COLOR := Color(0.95, 0.91, 0.86, 0.85)
## Default pulse speed, in radians per second.
const DEFAULT_PULSE_SPEED := 3.0
## Default pulse amount: the scale swings this far either side of 1.
const DEFAULT_PULSE_AMOUNT := 0.06
## Default height of the ring above the target, in world units.
const DEFAULT_LIFT := 0.05

## Pulse speed, in radians per second.
var pulse_speed := DEFAULT_PULSE_SPEED
## How far the scale swings either side of 1.
var pulse_amount := DEFAULT_PULSE_AMOUNT
## Height above the target's position, in world units.
var lift := DEFAULT_LIFT
## The node the ring sits under; null hides it.
var target: Node3D = null:
	set(value):
		target = value
		_follow()
		set_process(visible) # nothing to pulse or follow while hidden

var _time := 0.0


## The ring's shape and colour are fixed here; the pulse and `lift` can change later.
func _init(
	inner_radius := DEFAULT_INNER_RADIUS,
	outer_radius := DEFAULT_OUTER_RADIUS,
	color := DEFAULT_COLOR,
	initial_pulse_speed := DEFAULT_PULSE_SPEED,
	initial_pulse_amount := DEFAULT_PULSE_AMOUNT,
	initial_lift := DEFAULT_LIFT,
) -> void:
	pulse_speed = initial_pulse_speed
	pulse_amount = initial_pulse_amount
	lift = initial_lift
	# Seen from above only.
	add_child(LFUtils3D.flat_ring(inner_radius, outer_radius, LFUtils3D.translucent_material(color, BaseMaterial3D.CULL_BACK)))
	visible = false


func _ready() -> void:
	_follow() # a target set before the ring entered the tree
	set_process(visible) # Godot turns processing on for a ready node with _process


func _process(delta: float) -> void:
	_time += delta
	scale = Vector3.ONE * (1.0 + sin(_time * pulse_speed) * pulse_amount)
	_follow()
	if not visible:
		set_process(false) # the target went away


func _follow() -> void:
	var valid := target != null and is_instance_valid(target) and target.is_inside_tree()
	visible = valid
	if valid and is_inside_tree():
		global_position = target.global_position + Vector3(0, lift, 0)
