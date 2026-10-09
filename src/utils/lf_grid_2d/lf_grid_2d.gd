## Converts between world positions and the cells of a square grid laid flat on the ground.
##
## The grid lies on the XZ plane, centred on the origin, covering
## [-half_extent, half_extent] on both axes in square cells of `cell_size`. Cell (cx, cz)
## is stored at index `cz * cols + cx` ("row-major": row by row). It is the shared cell
## layout of `LFFlowField`, a navigation grid, or any per-cell array of your own.
class_name LFGrid2D

static var _log := LFLogger.new()


## The 8 neighbor offsets of a cell (x, z), row by row.
const NEIGHBORS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## The length, in cells, of a step to each of `NEIGHBORS_8` (same order): √2 diagonally,
## 1 straight.
const NEIGHBOR_STEP_LENGTHS: Array[float] = [1.41421356, 1.0, 1.41421356, 1.0, 1.0, 1.41421356, 1.0, 1.41421356]


## Tolerance for float division landing a hair above a whole number of cells.
const _SPAN_EPSILON := 1e-6
## Where a cell's centre lies along each axis, as a fraction of the cell's side.
const _CENTRE_FRACTION := 0.5
## Cells per side of a cell's 3 x 3 neighborhood, the row stride of `neighbor_bit`.
const _NEIGHBORHOOD_SIDE := 3


## How many cells span the grid along one axis; a partial cell counts, except a sliver
## under a millionth of a cell (so float rounding on an exact fit adds none). 0 for a
## negative extent, and 0 (with an error) for a non-positive `cell_size` or a non-finite
## `half_extent`. The count is not capped: a tiny `cell_size` over a large extent names
## more cells than any array holds.
static func cells_across(half_extent: float, cell_size: float) -> int:
	if !(cell_size > 0.0):
		_log.error("LFGrid2D.cells_across: cell_size must be positive, got %s" % cell_size)
		return 0
	if !is_finite(half_extent):
		_log.error("LFGrid2D.cells_across: half_extent must be finite, got %s" % half_extent)
		return 0
	return maxi(0, ceili(2.0 * half_extent / cell_size - _SPAN_EPSILON))


## The world-space centre of cell (cx, cz), at height 0.
static func cell_center(cx: int, cz: int, half_extent: float, cell_size: float) -> Vector3:
	return Vector3(-half_extent + (cx + _CENTRE_FRACTION) * cell_size, 0.0, -half_extent + (cz + _CENTRE_FRACTION) * cell_size)


## The row-major index of `cell` in a grid `cols` wide.
static func index_of(cell: Vector2i, cols: int) -> int:
	return cell.y * cols + cell.x


## Whether `cell` lies inside a grid of `cols` × `rows`.
static func in_bounds(cell: Vector2i, cols: int, rows: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows


## The cell holding `position`, clamped into the grid so an off-grid position still
## names its nearest edge cell. Preconditions, unchecked because this runs in hot loops:
## `position` is finite, `cell_size` is positive and `cols`, `rows` are at least 1 —
## otherwise the result is meaningless.
static func cell_of(position: Vector3, half_extent: float, cell_size: float, cols: int, rows: int) -> Vector2i:
	var cx := floori((position.x + half_extent) / cell_size)
	var cz := floori((position.z + half_extent) / cell_size)
	return Vector2i(clampi(cx, 0, cols - 1), clampi(cz, 0, rows - 1))


## The bit (0–8, 4 being the cell itself) a neighbor `offset` (each component -1..1)
## takes in a per-cell 9-bit mask — independent of any neighbor iteration order.
static func neighbor_bit(offset: Vector2i) -> int:
	return (offset.y + 1) * _NEIGHBORHOOD_SIDE + (offset.x + 1)


## Every cell whose area overlaps `rect` (on the XZ plane: `rect.position.x` is X,
## `rect.position.y` is Z), row by row. A shared edge alone does not count, and cells
## outside the grid are never returned. A negative-size rect is read as its `abs()`.
## Empty for a rect off the grid, and for a non-positive `cell_size` or a non-finite
## `half_extent` (reported).
static func cells_overlapping(rect: Rect2, half_extent: float, cell_size: float) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var cols := cells_across(half_extent, cell_size)
	if cols == 0:
		return cells
	rect = rect.abs()
	var first := cell_of(Vector3(rect.position.x, 0.0, rect.position.y), half_extent, cell_size, cols, cols)
	var last := cell_of(Vector3(rect.end.x, 0.0, rect.end.y), half_extent, cell_size, cols, cols)
	for cz in range(first.y, last.y + 1):
		var cell_z := -half_extent + cz * cell_size
		if !(cell_z < rect.end.y and cell_z + cell_size > rect.position.y):
			continue
		for cx in range(first.x, last.x + 1):
			var cell_x := -half_extent + cx * cell_size
			if cell_x < rect.end.x and cell_x + cell_size > rect.position.x:
				cells.append(Vector2i(cx, cz))
	return cells
