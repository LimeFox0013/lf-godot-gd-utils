## Finds the objects near a point: "what is within this radius?" or "which one is nearest?".
##
## Register each object with its position and keep the position updated as it moves; the
## index sorts objects into a uniform grid of cells (a "spatial hash"), so a query only
## looks at the cells its radius touches instead of every object. Objects can be any
## value usable as a Dictionary key: Nodes, ids, Resources.
class_name LFSpatialIndex

static var _log := LFLogger.new()


## Default `cell_size`: edge length of each grid cell, in world units.
const DEFAULT_CELL_SIZE := 4.0

# Handed to the shared radius query by the plain one, which collects no positions.
static var _no_positions := PackedVector3Array()

## Edge length of each grid cell, finite and greater than 0. Changing it re-buckets every
## registered object, so queries stay correct; any other value is reported and ignored.
var cell_size: float = DEFAULT_CELL_SIZE:
	set(value):
		if !(value > 0.0 and is_finite(value)):
			_log.error("LFSpatialIndex: cell_size must be finite and positive, got %s" % value)
			return
		cell_size = value
		_inverse_cell_size = 1.0 / value
		_rebucket()
## Buckets by X and Z only — for a world where things spread over the ground, so a query
## looks at one layer of cells instead of every layer its radius spans in Y. Results are
## the same: distances are still measured in 3D. Changing it re-buckets every object.
var planar := false:
	set(value):
		if value == planar:
			return
		planar = value
		_rebucket()

var _inverse_cell_size := 1.0 / DEFAULT_CELL_SIZE
# Each cell keeps its objects and their positions side by side (same slot), so a query
# reads positions without a lookup per candidate.
var _cell_objects: Dictionary[Vector3i, Array] = {}
var _cell_positions: Dictionary[Vector3i, PackedVector3Array] = {}
var _object_cell: Dictionary[Variant, Vector3i] = {}
var _object_slot: Dictionary[Variant, int] = {}
## How many `query_nearest` calls are running (an `accept` can query again). Freed objects
## are forgotten only when this is 0, so a nested query never reshuffles the cells an
## outer one is walking.
var _nearest_depth := 0
# Freed objects queries met, forgotten by `_forget` (one array, reused).
var _freed: Array = []
# Cells the last query looked at: its box, or every occupied cell when that is fewer.
var _last_scanned_cells := 0
# A box holding every occupied cell, grown as cells are made. Cells emptying on its edge
# only mark it loose; a query that needs it tight shrinks it first (`_tighten_bounds`).
var _bounds_low := Vector3i.ZERO
var _bounds_high := Vector3i.ZERO
var _bounds_loose := false
# The cells the query being set up covers (see `_plan_scan`).
var _scan_low := Vector3.ZERO
var _scan_high := Vector3.ZERO

# How a query walks the cells: not at all, its box, or every occupied cell.
enum _Scan { NOTHING, BOX, OCCUPIED }


## An empty index bucketing by cells of `initial_cell_size` (a non-positive or non-finite one is
## reported and `DEFAULT_CELL_SIZE` kept), by X and Z only when `is_planar`.
func _init(initial_cell_size := DEFAULT_CELL_SIZE, is_planar := false) -> void:
	planar = is_planar
	cell_size = initial_cell_size


## Registers `object` at `position`, or moves it if already registered.
func register(object: Variant, position: Vector3) -> void:
	update_position(object, position)


## Updates `object`'s position, moving it between cells if needed. Registers `object` if it isn't tracked yet.
func update_position(object: Variant, position: Vector3) -> void:
	# One lookup, not has() then []: this runs for every moving object every frame.
	var previous: Variant = _object_cell.get(object)
	var cell := _cell_for(position)
	if previous == null:
		_add(object, cell, position)
	elif previous != cell:
		var old_cell: Vector3i = previous
		_take(object, old_cell)
		_add(object, cell, position)
	else:
		_cell_positions[cell][_object_slot[object]] = position


## Removes `object`, erasing it from the cell it occupied. A no-op if `object` was never registered.
func remove(object: Variant) -> void:
	var cell: Variant = _object_cell.get(object)
	if cell == null:
		return
	var occupied: Vector3i = cell
	_take(object, occupied)
	_object_cell.erase(object)
	_object_slot.erase(object)


## Whether `object` is registered.
func has(object: Variant) -> bool:
	return _object_cell.has(object)


## `object`'s registered position, or null when it isn't registered.
func position_of(object: Variant) -> Variant:
	var cell: Variant = _object_cell.get(object)
	if cell == null:
		return null
	return _cell_positions[cell][_object_slot[object]]


## Exactly the registered objects whose position lies within `radius` of `position`
## (boundary included), unordered, in a new array each call. A freed object is never
## returned: the query forgets it.
func query_radius(position: Vector3, radius: float) -> Array:
	return _query_radius(position, radius, _no_positions, false)


## `query_radius`, also filling `out_positions` with each returned object's registered
## position, in the same order (its previous content is replaced) — for a caller that
## would otherwise look every position up again.
func query_radius_positions(position: Vector3, radius: float, out_positions: PackedVector3Array) -> Array:
	out_positions.clear()
	return _query_radius(position, radius, out_positions, true)


## The registered object nearest `position` within `radius` (boundary included) that
## `accept` takes, or null. `exclude` is never returned (compared by value; a key of
## another type never matches). `accept` is optional; it is called only for a candidate
## nearer than the best accepted so far, so put costly tests there — with one argument it
## gets the object, with two the object and its registered position. Of equally near
## candidates the first one the scan meets wins (the visiting order differs between
## narrow and wide queries, so don't rely on which). Builds no array or object of its own (`accept` may);
## a freed object it meets is forgotten and never returned. `accept` may run other
## queries on this index, but must not register, move or remove objects in it.
func query_nearest(position: Vector3, radius: float, accept := Callable(), exclude: Variant = null) -> Variant:
	if !(radius >= 0.0):
		return null
	var scan := _plan_scan(position, radius)
	if scan == _Scan.NOTHING:
		return null
	var with_position := accept.is_valid() and accept.get_argument_count() >= 2
	_nearest_depth += 1
	var nearest: Variant
	if scan == _Scan.OCCUPIED:
		nearest = _nearest_over_occupied(position, radius * radius, accept, with_position, exclude)
	else:
		nearest = _nearest_over_box(position, radius * radius, accept, with_position, exclude)
	_nearest_depth -= 1
	_forget()
	return nearest


## `query_nearest` over the occupied cells inside the planned box. Walks the dictionary
## itself (no keys() copy). Returns the nearest object within `limit` (a squared distance),
## or null.
func _nearest_over_occupied(position: Vector3, limit: float, accept: Callable, with_position: bool, exclude: Variant) -> Variant:
	var low := _scan_low
	var high := _scan_high
	var nearest: Variant = null
	var nearest_distance := limit
	var exclude_type := typeof(exclude)
	var found := false
	for cell: Vector3i in _cell_objects:
		if _in_box(cell, low, high):
			var cell_positions: PackedVector3Array = _cell_positions[cell]
			var slot := _nearest_in(_cell_objects[cell], cell_positions, position, nearest_distance, found,
				accept, with_position, exclude, exclude_type)
			if slot >= 0:
				nearest = _cell_objects[cell][slot]
				nearest_distance = cell_positions[slot].distance_squared_to(position)
				found = true
	return nearest


## `query_nearest` over every cell of the planned box. The same work as `_nearest_in`, kept
## inline: a call per cell slows small queries. Returns the nearest object within `limit`
## (a squared distance), or null.
func _nearest_over_box(position: Vector3, limit: float, accept: Callable, with_position: bool, exclude: Variant) -> Variant:
	var low := _scan_low
	var high := _scan_high
	var nearest: Variant = null
	var nearest_distance := limit
	var filtered := accept.is_valid()
	var exclude_type := typeof(exclude)
	var found := false
	var cell := Vector3i()
	for x in range(int(low.x), int(high.x) + 1):
		cell.x = x
		for y in range(int(low.y), int(high.y) + 1):
			cell.y = y
			for z in range(int(low.z), int(high.z) + 1):
				cell.z = z
				var objects: Variant = _cell_objects.get(cell)
				if objects == null:
					continue
				var cell_positions: PackedVector3Array = _cell_positions[cell]
				for i in cell_positions.size():
					var distance := cell_positions[i].distance_squared_to(position)
					# Before the first hit the boundary counts; after, only strictly nearer.
					# Negated so a NaN distance (a NaN position) is never a candidate.
					if !(distance <= nearest_distance) or (found and distance == nearest_distance):
						continue
					var object: Variant = objects[i]
					if typeof(object) == TYPE_OBJECT and !is_instance_valid(object):
						_freed.append(object)
						continue
					if typeof(object) == exclude_type and object == exclude:
						continue
					if filtered and !(accept.call(object, cell_positions[i]) if with_position else accept.call(object)):
						continue
					nearest = object
					nearest_distance = distance
					found = true
	return nearest


## Every registered object's current position, in no particular order — a new array
## each call.
func positions() -> PackedVector3Array:
	var all := PackedVector3Array()
	for cell_positions: PackedVector3Array in _cell_positions.values():
		all.append_array(cell_positions)
	return all


## How many objects are registered.
func size() -> int:
	return _object_cell.size()


## How many cells hold at least one object.
func cell_count() -> int:
	return _cell_objects.size()


## Forgets every registered object.
func clear() -> void:
	_cell_objects.clear()
	_cell_positions.clear()
	_object_cell.clear()
	_object_slot.clear()


# Removes the freed objects queries met, unless a `query_nearest` is still walking the
# cells (the query ran from its `accept`): the outermost query forgets them when it ends.
func _forget() -> void:
	if _nearest_depth > 0 or _freed.is_empty():
		return
	for object: Variant in _freed:
		remove(object)
	_freed.clear()


# Both radius queries: the objects within `radius`, and their positions into
# `out_positions` when `with_positions`.
func _query_radius(position: Vector3, radius: float, out_positions: PackedVector3Array, with_positions: bool) -> Array:
	var result: Array = []
	if !(radius >= 0.0):
		return result
	var scan := _plan_scan(position, radius)
	var low := _scan_low
	var high := _scan_high
	var radius_squared := radius * radius

	if scan == _Scan.OCCUPIED:
		for cell: Vector3i in _cell_objects:
			if _in_box(cell, low, high):
				_gather(_cell_objects[cell], _cell_positions[cell], position, radius_squared, result, out_positions, with_positions)
	elif scan == _Scan.BOX:
		# The same work as _gather, kept inline: a call per cell slows small queries.
		var cell := Vector3i()
		for x in range(int(low.x), int(high.x) + 1):
			cell.x = x
			for y in range(int(low.y), int(high.y) + 1):
				cell.y = y
				for z in range(int(low.z), int(high.z) + 1):
					cell.z = z
					var objects: Variant = _cell_objects.get(cell)
					if objects == null:
						continue
					var cell_positions: PackedVector3Array = _cell_positions[cell]
					for i in cell_positions.size():
						# Negated so a NaN distance (a NaN position) never counts as within range.
						if !(cell_positions[i].distance_squared_to(position) <= radius_squared):
							continue
						var object: Variant = objects[i]
						if typeof(object) == TYPE_OBJECT and !is_instance_valid(object):
							_freed.append(object)
							continue
						result.append(object)
						if with_positions:
							out_positions.append(cell_positions[i])

	_forget()
	return result


# Appends the objects of one cell within range to `result` (and their positions to
# `out_positions` when `with_positions`); a freed one goes to `_freed` instead.
func _gather(objects: Array, cell_positions: PackedVector3Array, position: Vector3, radius_squared: float,
		result: Array, out_positions: PackedVector3Array, with_positions: bool) -> void:
	for i in cell_positions.size():
		if !(cell_positions[i].distance_squared_to(position) <= radius_squared):
			continue
		var object: Variant = objects[i]
		if typeof(object) == TYPE_OBJECT and !is_instance_valid(object):
			_freed.append(object)
			continue
		result.append(object)
		if with_positions:
			out_positions.append(cell_positions[i])


# The slot of the best candidate `query_nearest` finds in one cell, nearer than
# `best_distance` (or as near, before anything was `found`), or -1.
func _nearest_in(objects: Array, cell_positions: PackedVector3Array, position: Vector3, best_distance: float,
		found: bool, accept: Callable, with_position: bool, exclude: Variant, exclude_type: int) -> int:
	var filtered := accept.is_valid()
	var best := -1
	for i in cell_positions.size():
		var distance := cell_positions[i].distance_squared_to(position)
		if !(distance <= best_distance) or (found and distance == best_distance):
			continue
		var object: Variant = objects[i]
		if typeof(object) == TYPE_OBJECT and !is_instance_valid(object):
			_freed.append(object)
			continue
		if typeof(object) == exclude_type and object == exclude:
			continue
		if filtered and !(accept.call(object, cell_positions[i]) if with_position else accept.call(object)):
			continue
		best = i
		best_distance = distance
		found = true
	return best


func _add(object: Variant, cell: Vector3i, position: Vector3) -> void:
	var objects: Variant = _cell_objects.get(cell)
	if objects == null:
		objects = []
		_cell_objects[cell] = objects
		_cell_positions[cell] = PackedVector3Array()
		if _cell_objects.size() == 1:
			_bounds_low = cell
			_bounds_high = cell
			_bounds_loose = false
		else:
			_bounds_low = _bounds_low.min(cell)
			_bounds_high = _bounds_high.max(cell)
	_object_slot[object] = objects.size()
	objects.append(object)
	_cell_positions[cell].append(position)
	_object_cell[object] = cell


# Swap-removes `object` from `cell`: the cell's last entry takes its slot.
func _take(object: Variant, cell: Vector3i) -> void:
	var objects: Array = _cell_objects[cell]
	var cell_positions: PackedVector3Array = _cell_positions[cell]
	var slot: int = _object_slot[object]
	var last := objects.size() - 1
	if slot != last:
		var moved: Variant = objects[last]
		objects[slot] = moved
		cell_positions[slot] = cell_positions[last]
		_object_slot[moved] = slot
	objects.resize(last)
	cell_positions.resize(last)
	if last == 0:
		_cell_objects.erase(cell) # a long-running index must not accumulate empty cells
		_cell_positions.erase(cell)
		if cell.x == _bounds_low.x or cell.z == _bounds_low.z or cell.x == _bounds_high.x \
				or cell.z == _bounds_high.z or (!planar and (cell.y == _bounds_low.y or cell.y == _bounds_high.y)):
			_bounds_loose = true
	else:
		_cell_positions[cell] = cell_positions


func _rebucket() -> void:
	var old_objects := _cell_objects
	var old_positions := _cell_positions
	_cell_objects = {}
	_cell_positions = {}
	_object_cell.clear()
	_object_slot.clear()
	for cell in old_objects:
		var objects: Array = old_objects[cell]
		var cell_positions: PackedVector3Array = old_positions[cell]
		for i in objects.size():
			_add(objects[i], _cell_for(cell_positions[i]), cell_positions[i])


# Which cells a query of `radius` around `position` covers, left in `_scan_low` and
# `_scan_high` (inclusive cell coordinates, floored but kept as floats so an infinite
# corner never overflows an int): the box its radius spans, clamped to the occupied
# cells' bounds when it holds more cells than are occupied. The query walks that box, or
# every occupied cell (keeping those inside the box) when the box still holds more.
# Records how many cells that is.
func _plan_scan(position: Vector3, radius: float) -> _Scan:
	var reach := Vector3(radius, radius, radius)
	var low := ((position - reach) * _inverse_cell_size).floor()
	var high := ((position + reach) * _inverse_cell_size).floor()
	if planar:
		low.y = 0.0
		high.y = 0.0
	var occupied := _cell_objects.size()
	_last_scanned_cells = 0
	if occupied == 0 or is_nan(low.x) or is_nan(low.y) or is_nan(low.z) \
			or is_nan(high.x) or is_nan(high.y) or is_nan(high.z):
		return _Scan.NOTHING
	var box_cells := _box_cells(low, high)
	if box_cells > occupied:
		_tighten_bounds()
		low = low.max(Vector3(_bounds_low))
		high = high.min(Vector3(_bounds_high))
		box_cells = _box_cells(low, high)
		if box_cells == 0.0:
			return _Scan.NOTHING
	_scan_low = low
	_scan_high = high
	if box_cells <= occupied:
		_last_scanned_cells = int(box_cells)
		return _Scan.BOX
	_last_scanned_cells = occupied
	return _Scan.OCCUPIED


# How many cells the box from `low` to `high` holds; 0 when it is empty.
static func _box_cells(low: Vector3, high: Vector3) -> float:
	var span := high - low + Vector3.ONE
	if span.x <= 0.0 or span.y <= 0.0 or span.z <= 0.0:
		return 0.0
	return span.x * span.y * span.z


# Whether `cell` lies in the box from `low` to `high` (both inclusive).
static func _in_box(cell: Vector3i, low: Vector3, high: Vector3) -> bool:
	return cell.x >= low.x and cell.x <= high.x and cell.z >= low.z and cell.z <= high.z \
		and cell.y >= low.y and cell.y <= high.y


# Shrinks `_bounds_low`/`_bounds_high` back to the occupied cells after cells on their
# edge emptied: one pass over the occupied cells, only when one did.
func _tighten_bounds() -> void:
	if !_bounds_loose:
		return
	_bounds_loose = false
	var first := true
	for cell: Vector3i in _cell_objects:
		if first:
			_bounds_low = cell
			_bounds_high = cell
			first = false
		else:
			_bounds_low = _bounds_low.min(cell)
			_bounds_high = _bounds_high.max(cell)


func _cell_for(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x * _inverse_cell_size),
		0 if planar else floori(position.y * _inverse_cell_size),
		floori(position.z * _inverse_cell_size),
	)
