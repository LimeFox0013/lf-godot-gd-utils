## Tells every member of a crowd which way to walk to reach one goal, around walls and around each other.
##
## A flow field is a grid laid over the ground (`LFGrid2D` layout) that stores, for every
## cell, the direction a crowd member standing there should move. Computing it once
## serves any number of members: each just samples the direction at its own position. It
## touches no Node and keeps no state between calls (plain data in, a `Field` out), so it
## can run on a worker thread (`LFThread`); `LFFlowFieldService` does that for you and
## keeps fields up to date.
##
## The cost of a cell is the cheapest path from it to the goal (Dijkstra, 8 neighbors,
## diagonals √2), where every cell entered also costs its local crowd density
## (`positions`, blurred) — so paths bend around pile-ups instead of every member
## beelining for the same point. An optional `nav_grid` describes the ground:
##
## - `cols`, `rows` — must match the field's;
## - `blocked` — per cell, a wall (bool or 0/1);
## - `heights` — per cell, ground height;
## - `climbable` (optional) — per cell, a 9-bit mask of the neighbors one may walk to
##   (`LFGrid2D.neighbor_bit`);
## - `max_climb` (optional) — the largest rise between adjacent cells a path may take;
##   no limit when absent. It never limits stepping down.
##
## Arrays are row-major (`LFGrid2D.index_of`); plain Arrays and packed arrays both work.
## Paths never enter a blocked cell and never cut a diagonal past a blocked corner.
class_name LFFlowField

static var _log := LFLogger.new()


## Default for `compute`'s `density_weight`: how strongly crowding bends paths (0 ignores
## the crowd).
const DEFAULT_DENSITY_WEIGHT := 2.0

## Two costs (in cells) or distances closer than this count as equal.
const _TIE_EPSILON := 0.0001
## A climbable mask with all 9 neighbor bits set: every step allowed.
const _OPEN_MASK := 511
## How many neighbor directions a cell has (`_OFFSETS.size()`).
const _DIRECTIONS := 8
## The highest direction index; the opposite of direction `d` is `_LAST_DIRECTION - d`.
const _LAST_DIRECTION := 7
## The step length along a line checked for climbing, as a fraction of the lattice spacing.
const _LINE_STEP_FRACTION := 0.5
## The length of a diagonal step, in cells.
const _DIAGONAL_STEP := sqrt(2.0)
## Scale applied to the smallest allowed step rise, a margin for float rounding.
const _RISE_MARGIN_SCALE := 0.99
## Absolute margin taken off the smallest allowed step rise, in world units.
const _RISE_MARGIN := 1e-6
## Where a cell's centre lies along each axis, as a fraction of the cell's side.
const _CENTRE_FRACTION := 0.5
## The search starts from the open cells within this many cells of the goal (more only
## when none is open).
const _SEED_REACH := 1.0
## While searching, `should_stop` is polled when the settled count's low bits under this
## mask are all zero: once every `_STOP_POLL_MASK + 1` settled cells.
const _STOP_POLL_MASK := 255
## Below this length a direction counts as none (in cells or world units).
const _MIN_LENGTH := 0.001
## The angle between adjacent neighbor directions, in radians.
const _OCTANT := PI / 4.0
## The neighbor offsets by direction index; the opposite of direction `d` is `7 - d`.
const _OFFSETS := LFGrid2D.NEIGHBORS_8
const _STEP_LENGTHS := LFGrid2D.NEIGHBOR_STEP_LENGTHS


## A computed field: one direction per cell, read with `sample`.
class Field extends RefCounted:
	## The goal this field leads to, as passed to `compute`.
	var goal: Vector3
	## Half the side of the square the field covers on X and Z.
	var half_extent: float
	## The side of one grid cell, in world units.
	var cell_size: float
	## Cells across on X (0 when the grid has no cells; `directions` is also empty for a
	## rejected goal or a computation that was stopped).
	var cols: int
	## Cells across on Z (always equal to `cols`: the grid is square).
	var rows: int
	## Row-major, one per cell: the unit XZ direction to move in, or zero when the cell's
	## centre is exactly on the goal.
	var directions: PackedVector3Array

	## The direction at `position`, clamped into the grid so an off-field position still
	## reads its nearest edge cell. Zero for an empty field.
	func sample(position: Vector3) -> Vector3:
		if directions.is_empty():
			return Vector3.ZERO
		return directions[LFGrid2D.index_of(LFGrid2D.cell_of(position, half_extent, cell_size, cols, rows), cols)]


## What a compute needs from the ground alone — which cells are walls, which steps are
## allowed, how deep each wall cell lies — prepared once by `prepare_ground` and passed to
## every `compute` over that ground, instead of being worked out again each time. Nothing
## in the library changes it after it is made; leave it unchanged too, and computes on
## several threads may share one.
class Ground extends RefCounted:
	## Cells across on X (and Z) this ground was prepared for.
	var cols: int
	## Per cell, 1 for a wall.
	var blocked: PackedByteArray
	## Per cell, bit `d` set when a step along neighbor direction `d` is allowed.
	var allowed: PackedByteArray
	## Per wall cell, how many steps it lies from the nearest open cell; 0 for open cells.
	var escape: PackedInt32Array


## The ground `compute` would read from `nav_grid` for a field over
## `[-half_extent, half_extent]` in cells of `cell_size`, ready to pass to every compute
## over it. A `nav_grid` that doesn't fit is reported and the ground treated as open (as
## `compute` does); a non-positive `cell_size` or non-finite `half_extent` gives a ground of no cells.
static func prepare_ground(half_extent: float, cell_size: float, nav_grid: Dictionary = {}) -> Ground:
	var ground := Ground.new()
	var cols := LFGrid2D.cells_across(half_extent, cell_size)
	ground.cols = cols
	if cols == 0:
		return ground
	var read := _read_ground(nav_grid, cols, cols)
	ground.blocked = read.blocked
	ground.allowed = _allowed_moves(cols, cols, read)
	ground.escape = _escape_depths(cols, cols, ground.blocked)
	return ground


## Builds the field toward `goal` over the square `[-half_extent, half_extent]` on X/Z.
## `positions` (an Array or PackedVector3Array of Vector3) is the crowd whose density
## paths avoid. Each direction is a grid step (one of the 8 neighbor directions, or the
## even blend of tied ones):
##
## - a cell that cannot reach the goal points straight at it;
## - a blocked cell (a body inside a wall's cell) points toward the nearest open cell;
## - a blocked goal cell routes to the nearest open cells around it instead;
## - a goal off the grid routes to the edge cells nearest it.
##
## A `nav_grid` that doesn't fit the field is reported and routing treats the ground as
## open; a non-positive `cell_size`, a non-finite `half_extent` or a non-finite `goal` is
## reported and gives an empty field. A negative or non-finite `density_weight` counts as 0. `should_stop`,
## when given, is polled while computing; once it answers true the result is an empty
## field (a worker can be told the field is no longer wanted). `ground`, when given (from
## `prepare_ground` with the same `half_extent` and `cell_size`), is used instead of
## reading `nav_grid`, which is then ignored; one prepared for another grid size is
## reported and `nav_grid` read instead.
static func compute(goal: Vector3, half_extent: float, cell_size: float, positions: Variant = [], density_weight := DEFAULT_DENSITY_WEIGHT, nav_grid: Dictionary = {}, should_stop := Callable(), ground: Ground = null) -> Field:
	var field := Field.new()
	field.goal = goal
	field.half_extent = half_extent
	field.cell_size = cell_size
	var cols := LFGrid2D.cells_across(half_extent, cell_size)
	var rows := cols
	field.cols = cols
	field.rows = rows
	var count := cols * rows
	if count == 0:
		return field
	if !goal.is_finite():
		_log.error("LFFlowField.compute: goal must be finite, got %s" % goal)
		return field

	if ground != null and ground.cols != cols:
		_log.error("LFFlowField.compute: the prepared ground has %d cells across, the field %d; reading nav_grid instead" % [ground.cols, cols])
		ground = null
	if ground == null:
		ground = prepare_ground(half_extent, cell_size, nav_grid)
	var blocked := ground.blocked
	var allowed := ground.allowed
	var density := _blur(_occupancy(positions, half_extent, cell_size, cols, rows), cols, rows)
	var cost := _integrate(goal, half_extent, cell_size, cols, rows, blocked, allowed, density, (density_weight if is_finite(density_weight) and density_weight > 0.0 else 0.0) / cell_size, should_stop)
	if should_stop.is_valid() and should_stop.call():
		return field
	var escape := ground.escape

	var directions := PackedVector3Array()
	directions.resize(count)
	for cz in rows:
		for cx in cols:
			var index := cz * cols + cx
			if blocked[index]:
				directions[index] = _escape_direction(cx, cz, cols, rows, cost, escape, goal, half_extent, cell_size)
			else:
				directions[index] = _descent_direction(cx, cz, cols, cost, allowed[index], goal, half_extent, cell_size)
	field.directions = directions
	return field


## The `climbable` entry of a nav grid, from the ground's heights: per cell (row-major),
## the `LFGrid2D.neighbor_bit` of every neighbor reached from the cell's centre without
## climbing a face steeper than `max_slope_deg`. `lattice` is a square grid of heights
## covering `[-half_extent, half_extent]` on X/Z, one sample every `lattice_spacing`
## (`round(2 * half_extent / lattice_spacing) + 1` per side), read as a bilinear surface;
## steps along each line are half a sample apart. Going down is always allowed. A lattice
## of the wrong size is reported and every step is allowed.
static func climbable_masks(lattice: PackedFloat32Array, lattice_spacing: float, half_extent: float, cell_size: float, max_slope_deg: float) -> PackedInt32Array:
	var cols := LFGrid2D.cells_across(half_extent, cell_size)
	var masks := PackedInt32Array()
	masks.resize(cols * cols)
	var all := 0
	for offset in _OFFSETS:
		all |= 1 << LFGrid2D.neighbor_bit(offset)
	masks.fill(all)
	var samples := int(round(2.0 * half_extent / lattice_spacing)) + 1 if lattice_spacing > 0.0 else 0
	if samples < 2 or lattice.size() != samples * samples:
		_log.error("LFFlowField.climbable_masks: the lattice needs %d x %d samples, got %d; every step allowed" % [samples, samples, lattice.size()])
		return masks
	# A line from a cell's centre to a neighbor's reads only the lattice around the
	# cell; when those heights vary less than the smallest allowed rise per step, no step
	# out of the cell can be too steep.
	var spans := _lattice_spans(lattice, samples, cols, half_extent, cell_size, lattice_spacing)
	var flat_rise := _smallest_step_rise(cell_size, lattice_spacing, max_slope_deg)
	for cz in cols:
		for cx in cols:
			var index := cz * cols + cx
			if spans[index] < flat_rise:
				continue
			var center := LFGrid2D.cell_center(cx, cz, half_extent, cell_size)
			var from := Vector2(center.x, center.z)
			var mask := 0
			for offset in _OFFSETS:
				if _line_climbable(lattice, samples, from, from + Vector2(offset) * cell_size, half_extent, lattice_spacing, max_slope_deg):
					mask |= 1 << LFGrid2D.neighbor_bit(offset)
			masks[index] = mask
	return masks


## A ready-made nav grid (`cols`, `rows`, `heights`, `blocked`, `climbable`) over the same cells as the
## field: `height_at(x, z)` read at each cell centre, every cell a rect of `wall_rects` overlaps
## blocked (a rect that only touches a cell's edge leaves it open), and `climbable` from `lattice`
## (`climbable_masks`); an empty `lattice` means flat ground, every step allowed. Add `max_climb` yourself.
static func build_nav_grid(half_extent: float, cell_size: float, height_at: Callable, wall_rects: Array[Rect2], lattice: PackedFloat32Array, lattice_spacing: float, max_slope_deg: float) -> Dictionary:
	var cols := LFGrid2D.cells_across(half_extent, cell_size)
	var rows := cols
	var heights: Array[float] = []
	var blocked: Array[bool] = []
	var climbable: Array[int] = []
	heights.resize(cols * rows)
	blocked.resize(cols * rows)
	climbable.resize(cols * rows)
	for cz in rows:
		for cx in cols:
			var center := LFGrid2D.cell_center(cx, cz, half_extent, cell_size)
			heights[LFGrid2D.index_of(Vector2i(cx, cz), cols)] = height_at.call(center.x, center.z)
	for rect in wall_rects:
		for cell in LFGrid2D.cells_overlapping(rect, half_extent, cell_size):
			blocked[LFGrid2D.index_of(cell, cols)] = true
	if lattice.is_empty():
		var all_neighbors := 0
		for offset in _OFFSETS:
			all_neighbors |= 1 << LFGrid2D.neighbor_bit(offset)
		climbable.fill(all_neighbors)
	else:
		climbable.assign(climbable_masks(lattice, lattice_spacing, half_extent, cell_size, max_slope_deg))
	return { 'cols': cols, 'rows': rows, 'heights': heights, 'blocked': blocked, 'climbable': climbable }


## The smallest rise `_line_climbable` allows per step on a line from a cell's centre to
## a neighbor's, less a margin for float rounding.
static func _smallest_step_rise(cell_size: float, spacing: float, max_slope_deg: float) -> float:
	var step_length := spacing * _LINE_STEP_FRACTION
	var smallest := INF
	for length: float in [cell_size, cell_size * _DIAGONAL_STEP]:
		var steps := maxi(1, int(ceil(length / step_length)))
		smallest = minf(smallest, tan(deg_to_rad(max_slope_deg)) * length / steps)
	return smallest * _RISE_MARGIN_SCALE - _RISE_MARGIN


## Per cell (row-major), the highest minus the lowest lattice height over every sample
## `_surface_height` can read for a point within one cell of the cell's centre on either
## axis — rows first, then columns.
static func _lattice_spans(lattice: PackedFloat32Array, samples: int, cols: int, half_extent: float, cell_size: float, spacing: float) -> PackedFloat32Array:
	var first := PackedInt32Array()
	var last := PackedInt32Array()
	first.resize(cols)
	last.resize(cols)
	for c in cols:
		var center := -half_extent + (c + _CENTRE_FRACTION) * cell_size
		first[c] = clampi(floori((center - cell_size + half_extent) / spacing) - 1, 0, samples - 1)
		last[c] = clampi(ceili((center + cell_size + half_extent) / spacing) + 1, 0, samples - 1)
	var row_low := PackedFloat32Array()
	var row_high := PackedFloat32Array()
	row_low.resize(samples * cols)
	row_high.resize(samples * cols)
	for iz in samples:
		for cx in cols:
			var lowest := INF
			var highest := -INF
			for ix in range(first[cx], last[cx] + 1):
				var height := lattice[iz * samples + ix]
				lowest = minf(lowest, height)
				highest = maxf(highest, height)
			row_low[iz * cols + cx] = lowest
			row_high[iz * cols + cx] = highest
	var spans := PackedFloat32Array()
	spans.resize(cols * cols)
	for cz in cols:
		for cx in cols:
			var lowest := INF
			var highest := -INF
			for iz in range(first[cz], last[cz] + 1):
				lowest = minf(lowest, row_low[iz * cols + cx])
				highest = maxf(highest, row_high[iz * cols + cx])
			spans[cz * cols + cx] = highest - lowest
	return spans


## Bilinear height of the lattice surface at (x, z), clamped to the lattice.
static func _surface_height(lattice: PackedFloat32Array, samples: int, x: float, z: float, half_extent: float, spacing: float) -> float:
	var fx := clampf((x + half_extent) / spacing, 0.0, samples - 1.0)
	var fz := clampf((z + half_extent) / spacing, 0.0, samples - 1.0)
	var ix := mini(int(fx), samples - 2)
	var iz := mini(int(fz), samples - 2)
	var tx := fx - ix
	var tz := fz - iz
	var top := lerpf(lattice[iz * samples + ix], lattice[iz * samples + ix + 1], tx)
	var bottom := lerpf(lattice[(iz + 1) * samples + ix], lattice[(iz + 1) * samples + ix + 1], tx)
	return lerpf(top, bottom, tz)


## Whether walking the straight line `from`→`to` never climbs steeper than
## `max_slope_deg`; going down is always fine.
static func _line_climbable(lattice: PackedFloat32Array, samples: int, from: Vector2, to: Vector2, half_extent: float, spacing: float, max_slope_deg: float) -> bool:
	var step_length := spacing * _LINE_STEP_FRACTION
	var steps := maxi(1, int(ceil(from.distance_to(to) / step_length)))
	var max_rise := tan(deg_to_rad(max_slope_deg)) * from.distance_to(to) / steps
	var previous := _surface_height(lattice, samples, from.x, from.y, half_extent, spacing)
	for i in range(1, steps + 1):
		var point := from.lerp(to, float(i) / steps)
		var height := _surface_height(lattice, samples, point.x, point.y, half_extent, spacing)
		if height - previous > max_rise:
			return false
		previous = height
	return true


## `field.sample(position)`; zero for a null field ("none ready yet").
static func sample_direction(field: Field, position: Vector3) -> Vector3:
	if field == null:
		return Vector3.ZERO
	return field.sample(position)


## The ground as packed arrays; open, flat ground when `nav_grid` is empty or invalid.
static func _read_ground(nav_grid: Dictionary, cols: int, rows: int) -> Dictionary:
	var count := cols * rows
	var ground := {
		'blocked': PackedByteArray(),
		'heights': PackedFloat32Array(),
		'climbable': PackedInt32Array(),
		'max_climb': INF,
	}
	ground.blocked.resize(count)
	ground.heights.resize(count)
	if nav_grid.is_empty():
		return ground

	var problem := ''
	if nav_grid.get('cols', -1) != cols or nav_grid.get('rows', -1) != rows:
		problem = 'its size %sx%s does not match the field\'s %sx%s cells' % [nav_grid.get('cols', '?'), nav_grid.get('rows', '?'), cols, rows]
	elif _length(nav_grid.get('blocked')) != count or _length(nav_grid.get('heights')) != count:
		problem = '`blocked` and `heights` need %s entries each' % count
	elif nav_grid.has('climbable') and _length(nav_grid.climbable) != count:
		problem = '`climbable` needs %s entries' % count
	if problem != '':
		_log.error('LFFlowField: nav_grid ignored, routing over open ground: %s.' % problem)
		return ground

	var source_blocked: Variant = nav_grid.blocked
	var source_heights: Variant = nav_grid.heights
	for i in count:
		ground.blocked[i] = 1 if source_blocked[i] else 0
		ground.heights[i] = source_heights[i]
	if nav_grid.has('climbable'):
		var source_climbable: Variant = nav_grid.climbable
		var climbable := PackedInt32Array()
		climbable.resize(count)
		for i in count:
			climbable[i] = int(source_climbable[i])
		ground.climbable = climbable
	if nav_grid.has('max_climb'):
		ground.max_climb = float(nav_grid.max_climb)
	return ground


static func _length(values: Variant) -> int:
	match typeof(values):
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			return values.size()
	return -1


## Per cell, bit `d` set when a step from it along `_OFFSETS[d]` is allowed: inside the
## grid, into an open cell, not past a blocked corner, within the climb limit and the
## climbable mask. Blocked cells allow nothing.
static func _allowed_moves(cols: int, rows: int, ground: Dictionary) -> PackedByteArray:
	var blocked: PackedByteArray = ground.blocked
	var heights: PackedFloat32Array = ground.heights
	var climbable: PackedInt32Array = ground.climbable
	var max_climb: float = ground.max_climb
	var allowed := PackedByteArray()
	allowed.resize(cols * rows)
	for cz in rows:
		for cx in cols:
			var from := cz * cols + cx
			if blocked[from]:
				continue
			var mask := 0
			var climb_mask: int = climbable[from] if !climbable.is_empty() else _OPEN_MASK
			for d in _DIRECTIONS:
				var offset: Vector2i = _OFFSETS[d]
				var nx := cx + offset.x
				var nz := cz + offset.y
				if nx < 0 or nx >= cols or nz < 0 or nz >= rows:
					continue
				var to := nz * cols + nx
				if blocked[to]:
					continue
				if heights[to] - heights[from] > max_climb:
					continue
				if !(climb_mask & (1 << LFGrid2D.neighbor_bit(offset))):
					continue
				if offset.x != 0 and offset.y != 0 and (blocked[cz * cols + nx] or blocked[nz * cols + cx]):
					continue
				mask |= 1 << d
			allowed[from] = mask
	return allowed


static func _occupancy(positions: Variant, half_extent: float, cell_size: float, cols: int, rows: int) -> PackedFloat64Array:
	var occupancy := PackedFloat64Array()
	occupancy.resize(cols * rows)
	for position: Vector3 in positions:
		occupancy[LFGrid2D.index_of(LFGrid2D.cell_of(position, half_extent, cell_size, cols, rows), cols)] += 1.0
	return occupancy


## A 3x3 box blur (the mean over the cell and its in-grid neighbors), in two passes, so
## the density term doesn't jump sharply from one cell to the next.
static func _blur(values: PackedFloat64Array, cols: int, rows: int) -> PackedFloat64Array:
	var across := PackedFloat64Array()
	across.resize(values.size())
	for cz in rows:
		var row := cz * cols
		for cx in cols:
			var sum := values[row + cx]
			if cx > 0:
				sum += values[row + cx - 1]
			if cx < cols - 1:
				sum += values[row + cx + 1]
			across[row + cx] = sum
	var blurred := PackedFloat64Array()
	blurred.resize(values.size())
	for cz in rows:
		var tall := 1 + int(cz > 0) + int(cz < rows - 1)
		for cx in cols:
			var wide := 1 + int(cx > 0) + int(cx < cols - 1)
			var index := cz * cols + cx
			var sum := across[index]
			if cz > 0:
				sum += across[index - cols]
			if cz < rows - 1:
				sum += across[index + cols]
			blurred[index] = sum / float(wide * tall)
	return blurred


## Dijkstra outward from the goal (or, when the goal cell is blocked, from the nearest
## open cells around it): a cell's cost is its cheapest allowed path to the goal. Relaxing
## neighbor A of settled cell B happens exactly when the real move A→B is allowed.
## Unreachable and blocked cells stay INF.
static func _integrate(goal: Vector3, half_extent: float, cell_size: float, cols: int, rows: int, blocked: PackedByteArray, allowed: PackedByteArray, density: PackedFloat64Array, density_scale: float, should_stop: Callable) -> PackedFloat64Array:
	var count := cols * rows
	var cost := PackedFloat64Array()
	cost.resize(count)
	cost.fill(INF)

	# A binary heap of (cost, cell) in two packed arrays; a cell is pushed once as a seed
	# and once per improvement, at most `_DIRECTIONS` times (once per settled neighbor).
	var seeds := _seeds(goal, half_extent, cell_size, cols, rows, blocked)
	var heap_cost := PackedFloat64Array()
	var heap_cell := PackedInt32Array()
	heap_cost.resize(count * _DIRECTIONS + seeds.size())
	heap_cell.resize(count * _DIRECTIONS + seeds.size())
	var heap_size := 0
	for start: Vector3 in seeds:
		var cell := int(start.x)
		cost[cell] = start.y
		heap_size = _heap_push(heap_cost, heap_cell, heap_size, start.y, cell)

	var neighbor_delta := PackedInt32Array()
	for d in _DIRECTIONS:
		neighbor_delta.append(_OFFSETS[d].y * cols + _OFFSETS[d].x)
	var settled := PackedByteArray()
	settled.resize(count)
	var checks := should_stop.is_valid()
	var settled_count := 0
	while heap_size > 0:
		if checks and (settled_count & _STOP_POLL_MASK) == 0 and should_stop.call():
			return cost
		settled_count += 1
		var into := heap_cell[0]
		heap_size = _heap_pop(heap_cost, heap_cell, heap_size)
		if settled[into]:
			continue
		settled[into] = 1
		@warning_ignore("integer_division")
		var bz := into / cols  # the row: truncation intended
		var bx := into - bz * cols
		var base := cost[into] + density_scale * density[into]
		for d in _DIRECTIONS:
			var ax := bx + _OFFSETS[d].x
			var az := bz + _OFFSETS[d].y
			if ax < 0 or ax >= cols or az < 0 or az >= rows:
				continue
			var from := into + neighbor_delta[d]
			if !(allowed[from] & (1 << (_LAST_DIRECTION - d))):
				continue
			var candidate := base + _STEP_LENGTHS[d]
			if candidate < cost[from]:
				cost[from] = candidate
				heap_size = _heap_push(heap_cost, heap_cell, heap_size, candidate, from)
	return cost


## Where the search starts, as Vector3(cell, cost, 0): every open cell whose centre lies
## within one cell of the goal point, at that distance (in cells) — so the costs, and the
## field, are symmetric about the goal itself, not about its cell's centre. When none is
## open (a goal inside a wall), the reach grows a cell at a time until some are: the seeds
## are the open cells within the smallest whole number of cells of the goal that holds
## any. A goal off the grid is measured from the grid's edge point nearest it.
static func _seeds(goal: Vector3, half_extent: float, cell_size: float, cols: int, rows: int, blocked: PackedByteArray) -> Array[Vector3]:
	goal.x = clampf(goal.x, -half_extent, -half_extent + cols * cell_size)
	goal.z = clampf(goal.z, -half_extent, -half_extent + rows * cell_size)
	var goal_cell := LFGrid2D.cell_of(goal, half_extent, cell_size, cols, rows)
	# The common case: open cells within one cell of the goal, found among its neighbors.
	var seeds := _seeds_within(_SEED_REACH, goal, half_extent, cell_size, cols, rows, blocked, goal_cell - Vector2i.ONE, goal_cell + Vector2i.ONE)
	if !seeds.is_empty():
		return seeds
	# Otherwise one pass finds the nearest open cell, and so the reach that first holds it.
	var nearest := INF
	for cz in rows:
		for cx in cols:
			if !blocked[cz * cols + cx]:
				nearest = minf(nearest, _cells_from_goal(Vector2i(cx, cz), goal, half_extent, cell_size))
	if nearest == INF:
		return seeds
	var reach := maxf(_SEED_REACH, ceilf(nearest - _TIE_EPSILON))
	return _seeds_within(reach, goal, half_extent, cell_size, cols, rows, blocked, Vector2i.ZERO, Vector2i(cols - 1, rows - 1))


## The open cells between `first` and `last` (clamped to the grid) whose centre lies
## within `reach` cells of `goal`, as `_seeds` returns them.
static func _seeds_within(reach: float, goal: Vector3, half_extent: float, cell_size: float, cols: int, rows: int, blocked: PackedByteArray, first: Vector2i, last: Vector2i) -> Array[Vector3]:
	var seeds: Array[Vector3] = []
	for cz in range(maxi(first.y, 0), mini(last.y, rows - 1) + 1):
		for cx in range(maxi(first.x, 0), mini(last.x, cols - 1) + 1):
			var index := cz * cols + cx
			if blocked[index]:
				continue
			var distance := _cells_from_goal(Vector2i(cx, cz), goal, half_extent, cell_size)
			if distance <= reach + _TIE_EPSILON:
				seeds.append(Vector3(index, distance, 0.0))
	return seeds


## How many cells lie between `cell`'s centre and `goal` on the XZ plane.
static func _cells_from_goal(cell: Vector2i, goal: Vector3, half_extent: float, cell_size: float) -> float:
	var center := LFGrid2D.cell_center(cell.x, cell.y, half_extent, cell_size)
	return Vector2(center.x - goal.x, center.z - goal.z).length() / cell_size


static func _heap_push(keys: PackedFloat64Array, cells: PackedInt32Array, size: int, key: float, cell: int) -> int:
	var at := size
	while at > 0:
		var parent := (at - 1) >> 1
		if keys[parent] <= key:
			break
		keys[at] = keys[parent]
		cells[at] = cells[parent]
		at = parent
	keys[at] = key
	cells[at] = cell
	return size + 1


static func _heap_pop(keys: PackedFloat64Array, cells: PackedInt32Array, size: int) -> int:
	size -= 1
	if size == 0:
		return 0
	var key := keys[size]
	var cell := cells[size]
	var at := 0
	while true:
		var child := 2 * at + 1
		if child >= size:
			break
		if child + 1 < size and keys[child + 1] < keys[child]:
			child += 1
		if keys[child] >= key:
			break
		keys[at] = keys[child]
		cells[at] = cells[child]
		at = child
	keys[at] = key
	cells[at] = cell
	return size


## For every blocked cell, how many steps (8 neighbors) it lies from the nearest open
## cell; 0 for open cells.
static func _escape_depths(cols: int, rows: int, blocked: PackedByteArray) -> PackedInt32Array:
	var depth := PackedInt32Array()
	depth.resize(cols * rows)
	if !blocked.has(1):
		return depth # open ground: every cell is 0 deep
	var frontier := PackedInt32Array()
	for i in cols * rows:
		if blocked[i]:
			depth[i] = -1
		else:
			frontier.append(i)
	var level := 0
	while !frontier.is_empty():
		level += 1
		var next := PackedInt32Array()
		for cell in frontier:
			@warning_ignore("integer_division")
			var cz := cell / cols  # the row: truncation intended
			var cx := cell - cz * cols
			for offset in _OFFSETS:
				var nx := cx + offset.x
				var nz := cz + offset.y
				if nx < 0 or nx >= cols or nz < 0 or nz >= rows:
					continue
				var neighbor := nz * cols + nx
				if depth[neighbor] == -1:
					depth[neighbor] = level
					next.append(neighbor)
		frontier = next
	return depth


## From a blocked cell: the step toward the neighbor one escape step closer to open
## ground, the cheapest such one; straight at the goal when the grid has no open cell.
static func _escape_direction(cx: int, cz: int, cols: int, rows: int, cost: PackedFloat64Array, escape: PackedInt32Array, goal: Vector3, half_extent: float, cell_size: float) -> Vector3:
	var own := escape[cz * cols + cx]
	var best := -1
	var best_cost := INF
	for d in _DIRECTIONS:
		var nx := cx + _OFFSETS[d].x
		var nz := cz + _OFFSETS[d].y
		if nx < 0 or nx >= cols or nz < 0 or nz >= rows:
			continue
		var neighbor := nz * cols + nx
		if escape[neighbor] != own - 1:
			continue
		if best == -1 or cost[neighbor] < best_cost:
			best = d
			best_cost = cost[neighbor]
	if best == -1:
		return _toward_goal(cx, cz, goal, half_extent, cell_size)
	return Vector3(_OFFSETS[best].x, 0.0, _OFFSETS[best].y).normalized()


## From an open cell: the step toward its cheapest allowed neighbor. Neighbors tied for
## cheapest are blended evenly, so the field stays mirror-symmetric — as long as the
## blend heads for one of them. When it doesn't (two ways round an obstacle or a crowd,
## whose blend points into it), the tied step nearest the bearing to the goal wins,
## breaking an exact tie toward the same side every time. Straight at the goal when no
## neighbor is cheaper (the goal's cells, an unreachable cell); zero when the cell's
## centre is on the goal.
static func _descent_direction(cx: int, cz: int, cols: int, cost: PackedFloat64Array, allowed: int, goal: Vector3, half_extent: float, cell_size: float) -> Vector3:
	var best := cost[cz * cols + cx]
	var tied := 0
	for d in _DIRECTIONS:
		if !(allowed & (1 << d)):
			continue
		var neighbor_cost := cost[(cz + _OFFSETS[d].y) * cols + cx + _OFFSETS[d].x]
		if neighbor_cost < best - _TIE_EPSILON:
			best = neighbor_cost
			tied = 1 << d
		elif tied != 0 and absf(neighbor_cost - best) <= _TIE_EPSILON:
			tied |= 1 << d
	if tied == 0:
		return _toward_goal(cx, cz, goal, half_extent, cell_size)

	var blend := Vector3.ZERO
	for d in _DIRECTIONS:
		if tied & (1 << d):
			blend += Vector3(_OFFSETS[d].x, 0.0, _OFFSETS[d].y).normalized()
	if blend.length() > _MIN_LENGTH:
		var heading := roundi(atan2(blend.z, blend.x) / _OCTANT)
		var step := Vector2i(roundi(cos(heading * _OCTANT)), roundi(sin(heading * _OCTANT)))
		if tied & (1 << _OFFSETS.find(step)):
			return blend.normalized()

	var bearing := _toward_goal(cx, cz, goal, half_extent, cell_size)
	var chosen := -1
	var chosen_dot := -INF
	var chosen_side := -INF
	for d in _DIRECTIONS:
		if !(tied & (1 << d)):
			continue
		var direction := Vector3(_OFFSETS[d].x, 0.0, _OFFSETS[d].y).normalized()
		var dot := direction.dot(bearing)
		var side := bearing.z * direction.x - bearing.x * direction.z
		if dot > chosen_dot + _TIE_EPSILON or (absf(dot - chosen_dot) <= _TIE_EPSILON and side > chosen_side):
			chosen = d
			chosen_dot = dot
			chosen_side = side
	return Vector3(_OFFSETS[chosen].x, 0.0, _OFFSETS[chosen].y).normalized()


static func _toward_goal(cx: int, cz: int, goal: Vector3, half_extent: float, cell_size: float) -> Vector3:
	var center := LFGrid2D.cell_center(cx, cz, half_extent, cell_size)
	var toward := Vector3(goal.x - center.x, 0.0, goal.z - center.z)
	if toward.length() < _MIN_LENGTH:
		return Vector3.ZERO
	return toward.normalized()
