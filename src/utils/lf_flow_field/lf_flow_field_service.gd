## Keeps a crowd flow field (see `LFFlowField`) ready for each goal, recomputed on worker threads where available.
##
## Each field is recomputed on a fixed interval so it follows the crowd. Goals that land in the same grid cell
## share one field and one computation. Reading a direction never waits: it reads the
## last finished field (zero until there is one), while recomputes run on worker threads
## (`LFThread`; without thread support they run on the main thread, blocking inside `tick`)
## and are swapped in when done. Call `tick` once per frame.
class_name LFFlowFieldService

static var _log := LFLogger.new()

## Default grid cell side for a new service, in world units.
const DEFAULT_CELL_SIZE := 3.0
## Default seconds between recomputes of a wanted field.
const DEFAULT_REFRESH_INTERVAL := 1.0
## Default `max_concurrent`: computes that may run at once.
const DEFAULT_MAX_CONCURRENT := 4

## A `_since_refresh` value that is due whatever `refresh_interval` is.
const _DUE_NOW := INF


## A new field for `cell` (the goal's grid cell) is ready.
signal field_updated(cell: Vector2i)
## The ready field for `cell` was dropped (its goal pruned, or the ground changed): a
## caller keeping that field should stop sampling it.
signal field_dropped(cell: Vector2i)

## Half the side of the square the fields cover, on X and Z. Read-only: fixed at
## construction (setting it is reported and ignored).
var half_extent: float:
	get:
		return _half_extent
	set(_value):
		_log.error('LFFlowFieldService: half_extent is fixed at construction; make a new service for another grid.')
## The side of one grid cell. Read-only, like `half_extent`.
var cell_size: float:
	get:
		return _cell_size
	set(_value):
		_log.error('LFFlowFieldService: cell_size is fixed at construction; make a new service for another grid.')
## Seconds between recomputes of a wanted field. A change applies from the next `tick`. A
## NaN is rejected: reported through `LFLogger` as an error, and the interval keeps its value.
var refresh_interval: float:
	get:
		return _refresh_interval
	set(value):
		if is_nan(value):
			_log.error('LFFlowFieldService: a NaN refresh_interval is rejected; keeping %s' % _refresh_interval)
			return
		_refresh_interval = value
## How many computes may run at once; a due field beyond that waits for a free slot.
var max_concurrent: int = DEFAULT_MAX_CONCURRENT
## How strongly crowd density bends paths (`LFFlowField.compute`); 0 routes as if the
## ground were empty. A change applies to computes started after it.
var density_weight: float
## The ground every compute routes over (see `LFFlowField`). Read-only: change it with
## `set_nav_grid` (assigning is reported and ignored), and never edit the returned
## dictionary, which running computes may be reading.
var nav_grid: Dictionary:
	get:
		return _nav_grid
	set(_value):
		_log.error('LFFlowFieldService: nav_grid is read-only; call set_nav_grid() to change the ground.')

var _refresh_interval := DEFAULT_REFRESH_INTERVAL
var _half_extent: float
var _cell_size: float
var _cols: int
var _nav_grid: Dictionary = {}
## Bumped by `set_nav_grid`, so a compute started on the old ground is thrown away.
var _ground_version := 0
## The current ground prepared for computes (`LFFlowField.prepare_ground`), shared by
## every compute on it; null until the first compute on it has prepared it.
var _ground: LFFlowField.Ground = null
## Ready fields — the only state a direction read touches.
var _fields: Dictionary[Vector2i, LFFlowField.Field] = {}
## In-flight computes, one per cell, removed only once joined.
var _pending: Dictionary[Vector2i, LFThread] = {}
var _pending_version: Dictionary[Vector2i, int] = {}
## Per in-flight compute started without a prepared ground: a one-slot Array its worker
## fills with the ground it prepared, adopted once it is joined.
var _pending_ground: Dictionary[Vector2i, Array] = {}
## The goal most recently requested in each wanted cell.
var _wanted: Dictionary[Vector2i, Vector3] = {}
var _since_refresh: Dictionary[Vector2i, float] = {}


## A service for fields over `[-grid_half_extent, grid_half_extent]` on X and Z in cells
## of `grid_cell_size`, each recomputed every `initial_refresh_interval` seconds while
## wanted, weighing crowd density by `initial_density_weight`. The grid is fixed for the
## service's lifetime; a non-positive cell size or non-finite half extent is reported and no field
## ever becomes ready.
func _init(grid_half_extent: float, grid_cell_size: float = DEFAULT_CELL_SIZE, initial_refresh_interval: float = DEFAULT_REFRESH_INTERVAL, initial_density_weight: float = LFFlowField.DEFAULT_DENSITY_WEIGHT) -> void:
	_half_extent = grid_half_extent
	_cell_size = grid_cell_size
	refresh_interval = initial_refresh_interval
	density_weight = initial_density_weight
	_cols = LFGrid2D.cells_across(grid_half_extent, grid_cell_size)


## Marks `goal`'s field as wanted. A cell not yet wanted, or a different goal in an
## already wanted cell, is due on the very next `tick`; repeating the same goal changes
## nothing, so calling this every frame still recomputes only every `refresh_interval`.
## A non-finite goal is reported and ignored, and so is every goal of a service built with
## a bad grid.
func request_field(goal: Vector3) -> void:
	if _cols == 0:
		return # the constructor reported the bad cell size; no field can ever be ready
	if !goal.is_finite():
		_log.error('LFFlowFieldService.request_field: goal must be finite, got %s' % goal)
		return
	var cell := cell_for(goal)
	if _wanted.has(cell) and _wanted[cell] == goal:
		return
	_wanted[cell] = goal
	_since_refresh[cell] = _DUE_NOW


## The direction toward `goal` at `position`, or zero while no field for it is ready.
func direction(goal: Vector3, position: Vector3) -> Vector3:
	var field: Variant = _fields.get(cell_for(goal))
	if field == null:
		return Vector3.ZERO
	return field.sample(position)


## The ready field for `goal`, or null — to keep and sample directly while `goal` holds.
func field_for(goal: Vector3) -> LFFlowField.Field:
	return _fields.get(cell_for(goal))


## The grid cell a goal is keyed by — goals in one cell share a field.
func cell_for(goal: Vector3) -> Vector2i:
	return LFGrid2D.cell_of(goal, _half_extent, _cell_size, _cols, _cols)


## Whether a compute for `goal`'s cell is running.
func is_pending(goal: Vector3) -> bool:
	return _pending.has(cell_for(goal))


## How many computes are running.
func pending_count() -> int:
	return _pending.size()


## Starts a compute for every wanted field whose interval has passed and that isn't
## already computing, then swaps in every finished one. `positions` is the crowd (an
## Array or PackedVector3Array of Vector3), or a Callable returning it — called only on
## a frame that starts a compute. `delta` is in seconds; a negative or non-finite delta
## adds nothing (the finished computes are still swapped in).
func tick(delta: float, positions: Variant = []) -> void:
	if !is_finite(delta) or delta < 0.0:
		delta = 0.0
	for cell: Variant in _wanted.keys():
		var elapsed: float = _since_refresh.get(cell, 0.0) + delta
		if elapsed >= refresh_interval and !_pending.has(cell) and _pending.size() < max_concurrent:
			if positions is Callable:
				positions = positions.call()
			_start(cell, _wanted[cell], positions)
			elapsed = 0.0
		_since_refresh[cell] = elapsed

	for cell: Variant in _pending.keys():
		var thread: LFThread = _pending[cell]
		thread.poll()
		if !thread.is_done():
			continue
		var stale := _pending_version[cell] != _ground_version
		var prepared: Variant = _pending_ground.get(cell, [null])[0]
		_pending.erase(cell)
		_pending_version.erase(cell)
		_pending_ground.erase(cell)
		if !stale and _ground == null and prepared != null:
			_ground = prepared
		if !_wanted.has(cell):
			continue
		# A compute told to stop (its goal pruned, then wanted again before it finished)
		# ends with an empty field; publishing it would read zero everywhere.
		if stale or thread.is_stop_requested():
			_since_refresh[cell] = _DUE_NOW
			continue
		var field: LFFlowField.Field = thread.get_result()
		if field == null or field.directions.is_empty():
			continue
		_fields[cell] = field
		field_updated.emit(cell)


## Forgets every field not wanted for one of `active_goals` — a goal that was cleared or
## moved away. A compute still running for one is asked to stop, and its result dropped.
func prune(active_goals: Array) -> void:
	var active: Dictionary[Vector2i, bool] = {}
	for goal: Vector3 in active_goals:
		active[cell_for(goal)] = true
	# Runs every frame and almost never finds anything, so keys are copied only when needed.
	var stale: Array[Vector2i] = []
	for cell in _fields:
		if !active.has(cell):
			stale.append(cell)
	for cell in stale:
		_fields.erase(cell)
		field_dropped.emit(cell)
	stale.clear()
	for cell in _wanted:
		if !active.has(cell):
			stale.append(cell)
	for cell in stale:
		_wanted.erase(cell)
		_since_refresh.erase(cell)
		if _pending.has(cell):
			_pending[cell].request_stop()


## Routes every later compute over a copy of `grid` (empty: open ground), so later edits
## to the caller's dictionary never reach a running compute. Ready fields are dropped and
## computes still running on the old ground are stopped and thrown away, so nothing is
## ever read for the wrong ground; wanted fields recompute on the next `tick`.
func set_nav_grid(grid: Dictionary) -> void:
	_nav_grid = grid.duplicate(true)
	_ground_version += 1
	_ground = null
	var dropped := _fields.keys()
	_fields.clear()
	for cell: Variant in dropped:
		field_dropped.emit(cell)
	for thread: Variant in _pending.values():
		thread.request_stop()
	for cell in _wanted:
		_since_refresh[cell] = _DUE_NOW


func _start(cell: Vector2i, goal: Vector3, positions: Variant) -> void:
	var crowd := PackedVector3Array(positions)
	var extent := _half_extent
	var size := _cell_size
	var weight := density_weight
	var grid := _nav_grid
	var ground := _ground
	var thread := LFThread.new()
	# A new LFThread with a valid task always starts (inline when threads are unavailable).
	if ground == null and _cols > 0:
		# Prepared on the worker, not here: it costs about as much as the rest of a compute.
		var prepared: Array = [null]
		_pending_ground[cell] = prepared
		thread.start_cancelable(func(should_stop: Callable) -> LFFlowField.Field:
			prepared[0] = LFFlowField.prepare_ground(extent, size, grid)
			return LFFlowField.compute(goal, extent, size, crowd, weight, grid, should_stop, prepared[0]))
	else:
		thread.start_cancelable(func(should_stop: Callable) -> LFFlowField.Field:
			return LFFlowField.compute(goal, extent, size, crowd, weight, grid, should_stop, ground))
	_pending[cell] = thread
	_pending_version[cell] = _ground_version
