## A pool of flat rings on the ground that show at the points you give it.
##
## Call `display(points)`: one ring per point, reused between calls, the extras hidden. Every
## ring shares one mesh and one material. Each is a flattened torus, not a filled disc: a
## translucent disc's top and bottom caps z-fight into a spiky starburst.
class_name LFRingMarkers3D
extends Node3D

## Default outer radius of each ring, in world units.
const DEFAULT_RADIUS := 3.0
## Default width of each ring, in world units.
const DEFAULT_WIDTH := 0.18
## Default colour of the rings (its alpha is the opacity).
const DEFAULT_COLOR := Color(0.85, 0.2, 0.2, 0.55)
## Default height of the rings above the points, in world units.
const DEFAULT_LIFT := 0.06

var _radius: float
var _width: float
var _lift: float
var _material: StandardMaterial3D
## The torus every ring shares, taken from the first ring built.
var _mesh: Mesh = null
var _rings: Array[MeshInstance3D] = []


## The rings' size, colour and height are fixed here. The node starts hidden.
func _init(radius := DEFAULT_RADIUS, width := DEFAULT_WIDTH, color := DEFAULT_COLOR, lift := DEFAULT_LIFT) -> void:
	_radius = radius
	_width = width
	_lift = lift
	_material = LFUtils3D.translucent_material(color)
	visible = false


## Shows one ring around each of `positions` (ground points); extra rings hide. Shows the node.
func display(positions: Array) -> void:
	visible = true
	while _rings.size() < positions.size():
		var ring := LFUtils3D.flat_ring(_radius - _width, _radius, _material)
		if _mesh == null:
			_mesh = ring.mesh
		ring.mesh = _mesh
		add_child(ring)
		_rings.append(ring)
	var offset := Vector3.UP * _lift
	for i in _rings.size():
		var ring := _rings[i]
		ring.visible = i < positions.size()
		if ring.visible and ring.position != positions[i] + offset:
			ring.position = positions[i] + offset


## How many rings are showing right now.
func shown_count() -> int:
	return _rings.filter(func(ring: MeshInstance3D) -> bool: return ring.visible).size() if visible else 0
