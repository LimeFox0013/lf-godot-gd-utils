## Ground height, walls, cover and walkability from a list of plain-data terrain features.
##
## Elevation features (platform, ramp, hill) combine into one height function; walls block
## movement and sight, foliage blocks sight only. Everything is analytic and Node-free, so
## it can feed a heightmap collider, a flow field's walkability grid and a line-of-sight
## check without any raycast. Feature dictionaries (rects are XZ `Rect2`, heights in world units):
## - `{ type = 'platform', rect, height }`: flat raised area with vertical sides.
## - `{ type = 'ramp', rect, height, low_edge }`: rises linearly from 0 at `low_edge`
##   ('x-', 'x+', 'z-' or 'z+': the side of the rect that is the bottom) to `height` opposite.
## - `{ type = 'hill', center: Vector2, radius, height }`: a smooth cosine mound.
## - `{ type = 'wall', rect, height }`: solid, impassable, opaque.
## - `{ type = 'foliage', rect }`: walkable, opaque.
class_name LFTerrainFeatures extends RefCounted

## Default `max_slope_deg`.
const DEFAULT_MAX_SLOPE_DEG := 30.0
## Default `sight_step`: world units between the samples of a segment test.
const DEFAULT_SIGHT_STEP := 0.5
## Default `footprint_grow`: how far an elevation feature's rect is widened for lattice sampling.
const DEFAULT_FOOTPRINT_GROW := 0.001

const _ELEVATION_TYPES: Array[String] = ['platform', 'ramp', 'hill']

## The features. Assigning sorts them out again.
var features: Array[Dictionary]:
	set(value):
		features = value
		_sort_features()
## Steepest face `is_walkable_between` and `nav_grid` let a walker climb, in degrees.
var max_slope_deg := DEFAULT_MAX_SLOPE_DEG
## Longest step of the samples `blocks_sight_between` and `is_walkable_between` take along a segment.
var sight_step := DEFAULT_SIGHT_STEP
## Widens each elevation feature's rect when sampling a lattice, so float rounding at a rim never drops a point.
var footprint_grow := DEFAULT_FOOTPRINT_GROW

var _walls: Array[Dictionary] = []
var _wall_rects: Array[Rect2] = []
var _foliage: Array[Dictionary] = []
var _opaque_rects: Array[Rect2] = []
var _elevation_features: Array[Dictionary] = []
var _elevation_bounds: Array[Rect2] = []


func _init(initial_features: Array[Dictionary] = [], initial_max_slope_deg := DEFAULT_MAX_SLOPE_DEG, initial_sight_step := DEFAULT_SIGHT_STEP, initial_footprint_grow := DEFAULT_FOOTPRINT_GROW) -> void:
	max_slope_deg = initial_max_slope_deg
	sight_step = initial_sight_step
	footprint_grow = initial_footprint_grow
	features = initial_features


## Whether any feature raises the ground (a platform, ramp or hill).
func has_elevation() -> bool:
	return not _elevation_features.is_empty()


## The wall features, in `features` order.
func walls() -> Array[Dictionary]:
	return _walls


## The foliage features, in `features` order.
func foliage() -> Array[Dictionary]:
	return _foliage


## Ground height at an XZ point: the highest elevation feature covering it, 0 elsewhere.
func height_at(x: float, z: float) -> float:
	var height := 0.0
	for i in _elevation_features.size():
		if _rect_has(_elevation_bounds[i], x, z):
			height = maxf(height, _feature_height(_elevation_features[i], x, z))
	return height


## `height_at` on a square lattice over [-half_extent, half_extent] (`LFHeightmap.lattice` layout),
## evaluated only where an elevation feature can reach; all zeros without one.
func height_lattice(half_extent: float, spacing: float) -> PackedFloat32Array:
	if _elevation_bounds.is_empty():
		var samples := LFHeightmap.samples_for(half_extent, spacing)
		var flat := PackedFloat32Array()
		flat.resize(samples * samples)
		flat.fill(0.0)
		return flat
	return LFHeightmap.lattice(height_at, half_extent, spacing, _elevation_bounds)


## Whether a wall covers the XZ point, edges included.
func is_wall_at(x: float, z: float) -> bool:
	for wall in _walls:
		if _rect_has(wall['rect'], x, z):
			return true
	return false


## Whether a wall or foliage covers the XZ point, edges included.
func blocks_sight_at(x: float, z: float) -> bool:
	for rect in _opaque_rects:
		if _rect_has(rect, x, z):
			return true
	return false


## Whether anything opaque lies on the XZ segment between the points, sampled every `sight_step`
## or less with both ends included (so a point inside foliage is hidden from outside, both ways).
func blocks_sight_between(from: Vector3, to: Vector3) -> bool:
	if _opaque_rects.is_empty():
		return false
	var a := LFUtils3D.to_xz(from)
	var b := LFUtils3D.to_xz(to)
	var steps := _segment_steps(a, b)
	for i in steps + 1:
		var point := a.lerp(b, float(i) / steps)
		if blocks_sight_at(point.x, point.y):
			return true
	return false


## Whether walking straight between the points never climbs a face steeper than `max_slope_deg`
## (sampled like `blocks_sight_between`); dropping down is always fine.
func is_walkable_between(from: Vector3, to: Vector3) -> bool:
	if not has_elevation():
		return true
	var a := LFUtils3D.to_xz(from)
	var b := LFUtils3D.to_xz(to)
	var steps := _segment_steps(a, b)
	var max_rise := tan(deg_to_rad(max_slope_deg)) * a.distance_to(b) / steps
	var previous := height_at(a.x, a.y)
	for i in range(1, steps + 1):
		var point := a.lerp(b, float(i) / steps)
		var height := height_at(point.x, point.y)
		if height - previous > max_rise:
			return false
		previous = height
	return true


## The `LFFlowField` nav grid over these features: heights, wall cells, and `climbable` from a
## lattice at `lattice_spacing` and `max_slope_deg` (every step allowed without elevation).
func nav_grid(half_extent: float, cell_size: float, lattice_spacing: float) -> Dictionary:
	var lattice := height_lattice(half_extent, lattice_spacing) if has_elevation() else PackedFloat32Array()
	return LFFlowField.build_nav_grid(half_extent, cell_size, height_at, _wall_rects, lattice, lattice_spacing, max_slope_deg)


func _sort_features() -> void:
	_walls = []
	_wall_rects = []
	_foliage = []
	_opaque_rects = []
	_elevation_features = []
	_elevation_bounds = []
	for feature in features:
		var type: String = feature['type']
		if type == 'wall':
			_walls.append(feature)
			_wall_rects.append(feature['rect'])
		elif type == 'foliage':
			_foliage.append(feature)
	for feature in _walls + _foliage:
		_opaque_rects.append(feature['rect'])
	for feature in features:
		if feature['type'] in _ELEVATION_TYPES:
			_elevation_features.append(feature)
			_elevation_bounds.append(_footprint(feature))


func _segment_steps(a: Vector2, b: Vector2) -> int:
	return maxi(int(ceil(a.distance_to(b) / sight_step)), 1)


func _footprint(feature: Dictionary) -> Rect2:
	var rect: Rect2
	if feature['type'] == 'hill':
		var radius: float = feature['radius']
		rect = Rect2(feature['center'] - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	else:
		rect = feature['rect']
	return rect.grow(footprint_grow)


static func _rect_has(rect: Rect2, x: float, z: float) -> bool:
	return x >= rect.position.x and x <= rect.end.x and z >= rect.position.y and z <= rect.end.y


static func _ramp_height(feature: Dictionary, x: float, z: float) -> float:
	var rect: Rect2 = feature['rect']
	var t := 0.0
	match feature['low_edge']:
		'x-': t = (x - rect.position.x) / rect.size.x
		'x+': t = (rect.end.x - x) / rect.size.x
		'z-': t = (z - rect.position.y) / rect.size.y
		'z+': t = (rect.end.y - z) / rect.size.y
	return clampf(t, 0.0, 1.0) * feature['height']


static func _feature_height(feature: Dictionary, x: float, z: float) -> float:
	match feature['type']:
		'platform':
			if _rect_has(feature['rect'], x, z):
				return feature['height']
		'ramp':
			if _rect_has(feature['rect'], x, z):
				return _ramp_height(feature, x, z)
		'hill':
			var center: Vector2 = feature['center']
			var distance := Vector2(x, z).distance_to(center)
			if distance < feature['radius']:
				return feature['height'] * 0.5 * (1.0 + cos(PI * distance / feature['radius']))
	return 0.0
