## Fills a MultiMeshInstance3D with many copies of its mesh, scattered at random over a flat area.
##
## Grass, pebbles, flowers, debris: give it a `MeshInstance3D` that marks the area (a plane), a
## density, and it places that many instances of the multimesh's mesh at random spots on it.
## Each instance gets a random layer number (in the custom data's red channel) so one shader can
## show several looks, and an optional random size. The same `random_seed` scatters the same way.
class_name LFMultiMeshScatter
extends MultiMeshInstance3D

## Instances per square unit of area when none is set.
const DEFAULT_DENSITY := 1.0
## How many looks (layers) there are when none is set: 1 means the layer is always 0.
const DEFAULT_LAYER_COUNT := 1
## The `random_seed` that means "different every run".
const UNSEEDED := 0

## Emitted after `scatter` placed `count` instances.
signal scattered(count: int)

## What `place` decides: one transform and one layer number per instance.
class Placement:
	extends RefCounted
	## Each instance's transform.
	var transforms: Array[Transform3D] = []
	## Each instance's layer number, `0` to `layers - 1`.
	var layers: PackedInt32Array = PackedInt32Array()


static var _log := LFLogger.new()

## The node whose mesh marks the area: a `PlaneMesh` is used by its size, any other mesh by the
## width and depth of its bounds. The area is taken in its own space, flat on its XZ plane.
@export var area: MeshInstance3D
## Instances per square unit of area (at least one instance is always placed).
@export var density := DEFAULT_DENSITY
## The smallest and largest size an instance gets (x is the minimum); equal values: no variation.
@export var scale_range := Vector2.ONE
## How far above (or below, when negative) the area's surface instances sit, in the area's units.
@export var shift_y := 0.0
## How many layers there are; each instance gets one at random, 0 to `layer_count - 1`.
@export var layer_count := DEFAULT_LAYER_COUNT:
	set(value):
		layer_count = maxi(value, 1)
## The seed for the placement; `UNSEEDED` (0) scatters differently each run.
@export var random_seed := UNSEEDED
## Scatter as soon as the node is ready. Turn it off to call `scatter()` yourself.
@export var scatter_on_ready := true


func _ready() -> void:
	if scatter_on_ready:
		scatter()


## Places the instances again (replacing any earlier ones) and returns how many. 0, with an
## error, when `area` is not set or has no mesh, or the multimesh or its mesh is missing.
## Each instance is a copy of the multimesh's mesh at a random spot, with this node's
## orientation, and layer `0..layer_count - 1` in its custom data's red channel. The multimesh
## must belong to this node alone (set it local to the scene): scattering rewrites it.
func scatter() -> int:
	if area == null:
		_log.error("LFMultiMeshScatter: no area is set")
		return 0
	if multimesh == null or multimesh.mesh == null:
		_log.error("LFMultiMeshScatter: the multimesh has no mesh")
		return 0
	var size := plane_size_xz(area)
	if size.x <= 0.0 or size.y <= 0.0:
		_log.error("LFMultiMeshScatter: the area has no size")
		return 0
	var count := maxi(roundi(size.x * size.y * density), 1)

	# Custom data can only be switched on while there are no instances.
	multimesh.instance_count = 0
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.instance_count = count
	multimesh.visible_instance_count = count

	var rng := RandomNumberGenerator.new()
	if random_seed == UNSEEDED:
		rng.randomize()
	else:
		rng.seed = random_seed
	var placement := place(size, count, rng, global_transform.affine_inverse() * area.global_transform, shift_y, scale_range, layer_count)
	for i in count:
		multimesh.set_instance_transform(i, placement.transforms[i])
		multimesh.set_instance_custom_data(i, Color(float(placement.layers[i]), 0.0, 0.0, 1.0))
	scattered.emit(count)
	return count


## Where `count` instances go, as plain data (what `scatter` writes into the multimesh). `size` is
## the area's width (x) and depth (y); `into_space` carries a point from the area's space into the
## space the transforms are given in; `rng` supplies every random number.
static func place(size: Vector2, count: int, rng: RandomNumberGenerator, into_space := Transform3D.IDENTITY, height := 0.0, size_range := Vector2.ONE, layer_total := DEFAULT_LAYER_COUNT) -> Placement:
	var result := Placement.new()
	var smallest := minf(size_range.x, size_range.y)
	var largest := maxf(size_range.x, size_range.y)
	for i in maxi(count, 0):
		var spot := Vector3(rng.randf_range(-size.x * 0.5, size.x * 0.5), height, rng.randf_range(-size.y * 0.5, size.y * 0.5))
		var instance_scale := rng.randf_range(smallest, largest)
		result.transforms.append(Transform3D(Basis.from_scale(Vector3.ONE * instance_scale), into_space * spot))
		result.layers.append(rng.randi_range(0, maxi(layer_total, 1) - 1))
	return result


## The width (x) and depth (y) of `mesh_instance`'s mesh in its own space: a `PlaneMesh`'s size,
## any other mesh's bounds on X and Z. Zero for no node or no mesh.
static func plane_size_xz(mesh_instance: MeshInstance3D) -> Vector2:
	if mesh_instance == null or mesh_instance.mesh == null:
		return Vector2.ZERO
	if mesh_instance.mesh is PlaneMesh:
		return (mesh_instance.mesh as PlaneMesh).size
	var bounds := mesh_instance.mesh.get_aabb()
	return Vector2(bounds.size.x, bounds.size.z)
