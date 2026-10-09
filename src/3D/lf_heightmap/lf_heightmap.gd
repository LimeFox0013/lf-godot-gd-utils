## Builds hilly 3D terrain (a coloured mesh plus a matching collider) from a height function.
##
## A static helper: never instantiate it, call its functions on the class name.
## Work starts with a "lattice": a square grid of heights. Sample a height function onto
## the lattice with `lattice`, then turn it into a slope-shaded mesh with `build_mesh`
## (flat colour on level ground, steep colour on cliffs, one material) or straight into a
## ready-to-add StaticBody3D with a matching HeightMapShape3D collider with `build_body`.
## A lattice starts at -half_extent on X and Z, `spacing` units apart, stored row by row
## (the height at column `ix`, row `iz` is `data[iz * samples + ix]`), the same layout
## `LFFlowField.climbable_masks` reads. It ends exactly at +half_extent when
## `2 * half_extent` is a whole multiple of `spacing`; otherwise the last sample lands up
## to half a `spacing` short of or past it.
## `spacing` must be finite and above 0 and `half_extent` finite and not negative (otherwise
## `samples_for` reports it and gives 0). `build_mesh` and `build_body` report a lattice they
## cannot read (fewer than 2 samples per side, `data` not holding `samples * samples`
## heights, or a `steep_slope` that is not finite and above 0) and build nothing;
## `slope_at` does not check its arguments. The sample count is not capped.
class_name LFHeightmap

static var _log := LFLogger.new()

## The slope (rise over run) at which a vertex takes the full steep colour.
const DEFAULT_STEEP_SLOPE := 1.2
## Default `collision_layer` of `build_body`: a physics layer bitmask (layer 1).
const DEFAULT_COLLISION_LAYER := 1
## The name of `build_body`'s CollisionShape3D child.
const COLLISION_NODE_NAME := "Collision"
## The name of `build_body`'s MeshInstance3D child.
const MESH_NODE_NAME := "Mesh"


## Returns how many samples one side of a lattice has when it spans
## [-half_extent, half_extent] with samples `spacing` apart:
## `round(2 * half_extent / spacing) + 1` (both edges included). A `spacing` that is not
## finite and above 0, or a `half_extent` that is negative or not finite, is reported and gives 0.
static func samples_for(half_extent: float, spacing: float) -> int:
	if !(spacing > 0.0 and is_finite(spacing)):
		_log.error("LFHeightmap: spacing must be finite and greater than zero, got %s" % spacing)
		return 0
	if !(half_extent >= 0.0 and is_finite(half_extent)):
		_log.error("LFHeightmap: half_extent must be finite and not negative, got %s" % half_extent)
		return 0
	return int(round(2.0 * half_extent / spacing)) + 1


## Returns a lattice: `height_fn.call(x, z) -> float` evaluated at every sample over
## [-half_extent, half_extent] on both axes, `spacing` apart, stored row by row.
## With `bounds` (rects on the ground plane: the rect's x is world X, its y is world Z),
## only the samples within some rect (widened to the enclosing samples) are evaluated
## and the rest stay 0 — a speed-up for terrain that is flat outside a few features.
## Rects outside the lattice evaluate nothing. Empty when `samples_for` gives 0.
static func lattice(height_fn: Callable, half_extent: float, spacing: float, bounds: Array[Rect2] = []) -> PackedFloat32Array:
	var samples := samples_for(half_extent, spacing)
	var data := PackedFloat32Array()
	data.resize(samples * samples)
	data.fill(0.0)
	if bounds.is_empty():
		for iz in samples:
			var z := -half_extent + iz * spacing
			for ix in samples:
				data[iz * samples + ix] = height_fn.call(-half_extent + ix * spacing, z)
		return data
	for rect in bounds:
		var ix_from := maxi(floori((rect.position.x + half_extent) / spacing), 0)
		var ix_to := mini(ceili((rect.end.x + half_extent) / spacing), samples - 1)
		var iz_from := maxi(floori((rect.position.y + half_extent) / spacing), 0)
		var iz_to := mini(ceili((rect.end.y + half_extent) / spacing), samples - 1)
		for iz in range(iz_from, iz_to + 1):
			var z := -half_extent + iz * spacing
			for ix in range(ix_from, ix_to + 1):
				data[iz * samples + ix] = height_fn.call(-half_extent + ix * spacing, z)
	return data


## Returns the steepness at lattice point (`ix`, `iz`) as rise over run (1.0 = 45°),
## from the heights of its neighbors on each side (one side only at the lattice edges;
## 0 along an axis with a single sample). `ix` and `iz` must be in 0..samples-1.
static func slope_at(data: PackedFloat32Array, samples: int, spacing: float, ix: int, iz: int) -> float:
	var ix0 := maxi(ix - 1, 0)
	var ix1 := mini(ix + 1, samples - 1)
	var iz0 := maxi(iz - 1, 0)
	var iz1 := mini(iz + 1, samples - 1)
	var rise_x := (data[iz * samples + ix1] - data[iz * samples + ix0]) / ((ix1 - ix0) * spacing) if ix1 > ix0 else 0.0
	var rise_z := (data[iz1 * samples + ix] - data[iz0 * samples + ix]) / ((iz1 - iz0) * spacing) if iz1 > iz0 else 0.0
	return Vector2(rise_x, rise_z).length()


## Returns a mesh of the lattice with one quad per cell, its vertices coloured from
## `flat_color` (level) to `steep_color` (at `steep_slope` rise over run and steeper).
## It faces up, its first vertex at (-half_extent, -half_extent). It needs a material that uses vertex colour
## as albedo (`StandardMaterial3D.vertex_color_use_as_albedo`); `build_body` sets one.
## A lattice it cannot read is reported and gives an empty mesh.
static func build_mesh(data: PackedFloat32Array, samples: int, spacing: float, half_extent: float, flat_color: Color, steep_color: Color, steep_slope := DEFAULT_STEEP_SLOPE) -> ArrayMesh:
	if !_is_readable(data, samples, spacing, half_extent, steep_slope):
		return ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in samples:
		for ix in samples:
			var slope := slope_at(data, samples, spacing, ix, iz)
			surface.set_color(flat_color.lerp(steep_color, clampf(slope / steep_slope, 0.0, 1.0)))
			surface.add_vertex(Vector3(-half_extent + ix * spacing, data[iz * samples + ix], -half_extent + iz * spacing))
	for iz in samples - 1:
		for ix in samples - 1:
			var a := iz * samples + ix
			var b := a + 1
			var c := a + samples
			var d := c + 1
			# Clockwise seen from above, Godot's front-face winding, so the surface faces up.
			surface.add_index(a)
			surface.add_index(b)
			surface.add_index(c)
			surface.add_index(b)
			surface.add_index(d)
			surface.add_index(c)
	surface.generate_normals()
	return surface.commit()


## Returns a new StaticBody3D, ready to `add_child`: on `collision_layer` (mask 0), with
## a `COLLISION_NODE_NAME` CollisionShape3D holding a HeightMapShape3D of the lattice (scaled by
## `spacing` on X and Z) and a `MESH_NODE_NAME` MeshInstance3D of `build_mesh` with a vertex-colour
## material. Laid out like the lattice: the first sample at (-half_extent, -half_extent),
## so centred on its origin when the lattice ends at +half_extent. The collider's samples
## sit on the mesh's vertices; inside a cell, the physics engine may split the square
## along the other diagonal than the mesh does, so on a cell that is not planar the two
## can differ between vertices. The caller owns it (free it if it is never added to the tree).
## A lattice it cannot read is reported and gives a bare body with no children.
static func build_body(data: PackedFloat32Array, samples: int, spacing: float, half_extent: float, flat_color: Color, steep_color: Color, collision_layer := DEFAULT_COLLISION_LAYER, steep_slope := DEFAULT_STEEP_SLOPE) -> StaticBody3D:
	var body := StaticBody3D.new()
	if !_is_readable(data, samples, spacing, half_extent, steep_slope):
		return body
	body.collision_layer = collision_layer
	body.collision_mask = 0

	var shape := HeightMapShape3D.new()
	shape.map_width = samples
	shape.map_depth = samples
	shape.map_data = data
	var collision := CollisionShape3D.new()
	collision.name = COLLISION_NODE_NAME
	collision.shape = shape
	if not is_equal_approx(spacing, 1.0):
		collision.scale = Vector3(spacing, 1.0, spacing)
	# A HeightMapShape3D is centred on its own origin; move it over the lattice's middle.
	var middle := -half_extent + (samples - 1) * spacing * 0.5
	if not is_zero_approx(middle):
		collision.position = Vector3(middle, 0.0, middle)
	body.add_child(collision)

	var mesh := MeshInstance3D.new()
	mesh.name = MESH_NODE_NAME
	mesh.mesh = build_mesh(data, samples, spacing, half_extent, flat_color, steep_color, steep_slope)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	mesh.material_override = material
	body.add_child(mesh)
	return body


# Whether `build_mesh` and `build_body` can read the lattice; reports why not.
static func _is_readable(data: PackedFloat32Array, samples: int, spacing: float, half_extent: float, steep_slope: float) -> bool:
	if samples < 2:
		_log.error("LFHeightmap: a lattice needs at least 2 samples per side, got %d" % samples)
		return false
	if data.size() != samples * samples:
		_log.error("LFHeightmap: %d samples per side needs %d heights, got %d" % [samples, samples * samples, data.size()])
		return false
	if !(spacing > 0.0 and is_finite(spacing) and is_finite(half_extent)):
		_log.error("LFHeightmap: spacing must be finite and greater than zero and half_extent finite, got %s and %s" % [spacing, half_extent])
		return false
	if !(steep_slope > 0.0 and is_finite(steep_slope)):
		_log.error("LFHeightmap: steep_slope must be finite and greater than zero, got %s" % steep_slope)
		return false
	return true
