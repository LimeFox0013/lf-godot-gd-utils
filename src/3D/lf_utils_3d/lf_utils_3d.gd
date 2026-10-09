## Everyday 3D math helpers: screen projection and mouse picking, ground markers, and
## points and directions on the ground (XZ) plane.
##
## "XZ plane" means the flat ground in Godot's Y-up world: the helpers ending in `_xz`
## ignore height (Y). The random helpers take an optional RandomNumberGenerator (for
## example an LFRandom) so seeded code replays the same rolls; without one they use
## Godot's global generator. All functions are static: call them on the class
## (`LFUtils3D.distance_xz(a, b)`), never create an instance.
class_name LFUtils3D

## Default `epsilon` of `away_xz`, in world units: closer points count as coinciding.
const DEFAULT_EPSILON := 0.001
## Default `length` of `raycast_from_screen`, in world units from the camera.
const DEFAULT_RAY_LENGTH := 1000.0
## Default `flatten` of `flat_ring`: the ring's height as a fraction of the torus's.
const DEFAULT_RING_FLATTEN := 0.1

## Squared on-screen length (camera-space units squared) below which a direction counts as zero.
const _MIN_DIRECTION_LENGTH_SQUARED := 1e-12
## Starting best distance of `farthest_sample_xz`, below any real distance (world units).
const _NO_DISTANCE := -1.0

static var _log := LFLogger.new()


## True when `camera` is a live Camera3D inside the tree, the only state in which the
## screen functions below can read it. False for null, a freed camera, one not added to
## the tree, and anything that is not a Camera3D. The camera parameters of this class are
## untyped on purpose: GDScript reports an error when a freed object is passed to a typed
## parameter, so a typed one could not take the freed camera these functions answer.
## Anything else that is not a Camera3D (a live Node3D, a number...) is a mistake: it is
## reported as an error through `LFLogger`, by every function below that is given it.
static func camera_ready(camera: Variant) -> bool:
	if not is_instance_valid(camera):
		if typeof(camera) != TYPE_NIL and typeof(camera) != TYPE_OBJECT:
			_log.error('LFUtils3D: expected a Camera3D, got a %s' % type_string(typeof(camera)))
		return false
	if not camera is Camera3D:
		_log.error('LFUtils3D: expected a Camera3D, got a %s' % (camera as Object).get_class())
		return false
	return (camera as Camera3D).is_inside_tree()


## Where `world_position` appears on screen through `camera` (viewport pixels), or null
## unless `camera_ready(camera)` or when the point is behind it —
## `Camera3D.unproject_position` alone would mirror a point behind the camera onto the
## screen.
static func world_to_canvas_position(camera: Variant, world_position: Vector3) -> Variant:
	if not camera_ready(camera):
		return null
	var camera_3d := camera as Camera3D
	if camera_3d.is_position_behind(world_position):
		return null
	return camera_3d.unproject_position(world_position)


## A random point within `radius` of `center` on the XZ plane (Y unchanged from
## `center`), e.g. to scatter points around a centre. Points are spread evenly over the
## disk's *area* (the distance is sqrt-scaled; a plain `randf() * radius` would crowd
## them toward the centre). Rolls from `rng` when given (a seeded caller's own
## generator), else the global one. A zero radius returns `center`.
static func random_point_in_circle_xz(center: Vector3, radius: float, rng: RandomNumberGenerator = null) -> Vector3:
	var angle := rng.randf_range(0.0, TAU) if rng != null else randf_range(0.0, TAU)
	var distance := sqrt(rng.randf() if rng != null else randf()) * radius
	return center + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


## The point at `angle` (radians, from +X toward +Z) on the XZ circle of `radius` around
## `center`; Y unchanged from `center`.
static func point_on_circle_xz(center: Vector3, radius: float, angle: float) -> Vector3:
	return center + Vector3(cos(angle), 0.0, sin(angle)) * radius


## A uniformly random unit direction on the XZ plane — by angle, so it is never zero and
## never biased toward the diagonals the way a normalized random square vector is. Rolls
## from `rng` when given (a seeded caller's own generator), else the global one.
static func random_direction_xz(rng: RandomNumberGenerator = null) -> Vector3:
	var angle := rng.randf_range(0.0, TAU) if rng != null else randf_range(0.0, TAU)
	return Vector3(cos(angle), 0.0, sin(angle))


## The unit XZ direction from `origin` to `from` — "away from `origin`" — or a random one
## (from `rng` when given) when the two are within `epsilon` of each other on the XZ plane.
static func away_xz(from: Vector3, origin: Vector3, epsilon := DEFAULT_EPSILON, rng: RandomNumberGenerator = null) -> Vector3:
	var offset := Vector3(from.x - origin.x, 0.0, from.z - origin.z)
	if offset.length() > epsilon:
		var direction := offset.normalized()
		if direction != Vector3.ZERO: # too short to normalize, even with epsilon <= 0
			return direction
	return random_direction_xz(rng)


## The physics hit under `screen_pos` (viewport pixels, e.g. the mouse position): the
## first collider along the view ray, at most `length` units from the camera, on the
## collision layers in `mask` (a bitmask: 1 is layer 1, 2 is layer 2, 4 is layer 3, ...;
## combine with `|`). The dictionary is `PhysicsDirectSpaceState3D.intersect_ray`'s
## (`position`, `normal`, `collider`, ...); empty on a miss or unless
## `camera_ready(camera)`.
static func raycast_from_screen(camera: Variant, screen_pos: Vector2, mask: int, length := DEFAULT_RAY_LENGTH) -> Dictionary:
	if not camera_ready(camera):
		return {}
	var camera_3d := camera as Camera3D
	var from := camera_3d.project_ray_origin(screen_pos)
	var to := from + camera_3d.project_ray_normal(screen_pos) * length
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return camera_3d.get_world_3d().direct_space_state.intersect_ray(query)


## Where the view ray under `screen_pos` meets `plane` (for example
## `Plane(Vector3.UP, ground_height)`), as a Vector3; null when the ray misses it or
## unless `camera_ready(camera)`.
static func screen_to_plane(camera: Variant, screen_pos: Vector2, plane: Plane) -> Variant:
	if not camera_ready(camera):
		return null
	var camera_3d := camera as Camera3D
	return plane.intersects_ray(camera_3d.project_ray_origin(screen_pos), camera_3d.project_ray_normal(screen_pos))


## On-screen distance in pixels from `screen_pos` to the projection of the world segment
## `a`–`b` — for picking a thin upright (a pole, a post) by tapping near it. INF when
## either end is behind the camera or unless `camera_ready(camera)`.
static func screen_distance_to_segment(camera: Variant, screen_pos: Vector2, a: Vector3, b: Vector3) -> float:
	if not camera_ready(camera):
		return INF
	var camera_3d := camera as Camera3D
	if camera_3d.is_position_behind(a) or camera_3d.is_position_behind(b):
		return INF
	var closest := Geometry2D.get_closest_point_to_segment(screen_pos, camera_3d.unproject_position(a), camera_3d.unproject_position(b))
	return screen_pos.distance_to(closest)


## Unit direction on screen (x right, y down) from the screen centre toward
## `world_position`, read from the point's position in the camera's own space, so it is
## the target's true side whether it is in front of, beside or behind the camera.
## `Vector2.DOWN` when the point is on the camera's view axis (straight ahead, straight
## behind, or at the camera's position), or unless `camera_ready(camera)`.
static func screen_direction(camera: Variant, world_position: Vector3) -> Vector2:
	if not camera_ready(camera):
		return Vector2.DOWN
	var local: Vector3 = (camera as Camera3D).global_transform.affine_inverse() * world_position
	var direction := Vector2(local.x, -local.y)
	if direction.length_squared() < _MIN_DIRECTION_LENGTH_SQUARED:
		return Vector2.DOWN
	return direction.normalized()


## A see-through, unlit material in `color` (its alpha is the opacity), two-sided by
## default — for ground markers, outlines and see-through previews.
static func translucent_material(color: Color, cull := BaseMaterial3D.CULL_DISABLED) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = cull
	return material


## A thin flat ring lying on the XZ plane between `inner` and `outer` radius: a torus
## squashed to `flatten` of its height, drawn with `material`. Reuse the returned node's
## `mesh` across rings of the same size.
static func flat_ring(inner: float, outer: float, material: Material, flatten := DEFAULT_RING_FLATTEN) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.scale.y = flatten
	ring.material_override = material
	return ring


## How far `point` is from the nearest of `points` (3D distance); INF when `points` is
## empty.
static func nearest_distance(point: Vector3, points: Array[Vector3]) -> float:
	var nearest := INF
	for other in points:
		nearest = minf(nearest, point.distance_to(other))
	return nearest


## Best-of-N max-min sampling: of `samples` uniform random points in the XZ square
## [-half_extent, half_extent]² (Y = 0), the one `accept` takes (a `func(point: Vector3)
## -> bool`; an invalid Callable accepts all) that lies farthest from its nearest point
## in `away_from`. Null when no sample was accepted; with `away_from` empty, the first
## accepted sample. Rolls x then z per sample from `rng` when given (a seeded caller's own
## generator), else the global one.
static func farthest_sample_xz(half_extent: float, samples: int, away_from: Array[Vector3], accept: Callable = Callable(), rng: RandomNumberGenerator = null) -> Variant:
	var best: Variant = null
	var best_distance := _NO_DISTANCE
	for i in samples:
		var x := rng.randf_range(-half_extent, half_extent) if rng != null else randf_range(-half_extent, half_extent)
		var z := rng.randf_range(-half_extent, half_extent) if rng != null else randf_range(-half_extent, half_extent)
		var point := Vector3(x, 0.0, z)
		if accept.is_valid() and not accept.call(point):
			continue
		var distance := nearest_distance(point, away_from)
		if distance > best_distance:
			best_distance = distance
			best = point
	return best


## `v` flattened onto the XZ plane: `Vector2(v.x, v.z)`.
static func to_xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## The distance between `a` and `b` on the XZ plane, ignoring height.
static func distance_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
