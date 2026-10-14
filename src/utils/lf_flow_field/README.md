# LFFlowField

> A density-aware flow field toward one goal: for every grid cell, the direction to move. `LFFlowFieldService` keeps one per goal ready, recomputed on worker threads (blocking on the main thread where threads are unavailable).

| | |
|---|---|
| **Files** | `lf_flow_field.gd`, `lf_flow_field_service.gd` |
| **Tests** | `tests/test_lf_flow_field.gd`, `tests/test_lf_flow_field_service.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFGrid2D`, `LFLogger`, `LFThread` (the service) |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFFlowField` | Static: call it on the class name |
| `LFFlowFieldService` | Object: create it with `.new()` |

## When to use it

Use it when dozens or hundreds of units all head for the same place (a base under
attack, a rally point) and should flow around walls and around each other instead of
jamming into one line. One field is computed for the goal and every unit just reads the
direction under its feet, so the path search runs once per goal rather than once per
unit (each unit then does one grid lookup). Crowding is part of the cost,
so paths bend around pile-ups. `LFFlowFieldService` keeps one field per goal fresh on
worker threads (on the main thread where threads are unavailable; see Notes); call its
`tick` each frame. For a few agents with their own individual
destinations, Godot's `NavigationAgent3D` (or `AStarGrid2D`) is simpler. To spread units
around the goal once they arrive, add `LFRingSlots`.

## Step by step

Goal: compute a "flow field" toward a goal and read which way a unit standing somewhere
should walk. A flow field is a grid over the ground where every cell stores a direction
pointing toward the neighboring cell that is cheapest to reach the goal from. (The goal here sits at the middle of a
cell, so the numbers come out round; a goal elsewhere in its cell gives slightly
blended directions near it.)

1. Choose *Scene → New Scene*, pick *Other Node*, create a `Node3D`, and save the scene.
2. Right-click it in the Scene dock, choose *Attach Script*, then *Create*.
3. Replace the script with the code below.
4. Press *F6* (run the current scene).
5. Read the *Output* panel. You should see `(1.0, 0.0, 0.0)` for a unit at the left of the
   field (it walks right, toward the goal) and `(0.0, 0.0, 0.0)` on the goal.
6. To move real units, use the code under Usage: `LFFlowFieldService` recomputes the
   field in the background while the game runs, and units read a direction every frame.

```gdscript
extends Node3D


func _ready() -> void:
	var goal := Vector3(19.5, 0, 1.5)    # where everyone is heading (world units)
	var half_extent := 30.0          # the field covers 30 units each way from the origin (60 wide)
	var cell_size := 3.0             # each square cell is 3 units wide; smaller = finer, slower

	# `compute` builds the whole field once, right now.
	var field := LFFlowField.compute(goal, half_extent, cell_size)

	# Ask for the direction at a spot. The result is a unit-length Vector3 (a direction
	# on the ground: x = east, z = south); zero when already on the goal.
	print("from the left: ", field.sample(Vector3(-19.5, 0, 1.5)))
	print("on the goal: ", field.sample(goal))
```

To make units avoid each other, pass their positions as the fourth argument
(`LFFlowField.compute(goal, half_extent, cell_size, [pos_a, pos_b, ...])`); for walls,
pass a `nav_grid` (see below).

## API

Everything the two classes offer; you only need the rows used above to get started.

### LFFlowField

| Member | Signature | Description |
|---|---|---|
| `compute` | `static compute(goal: Vector3, half_extent: float, cell_size: float, positions: Variant = [], density_weight := DEFAULT_DENSITY_WEIGHT, nav_grid: Dictionary = {}, should_stop := Callable(), ground: Ground = null) -> Field` | The field over an `LFGrid2D` grid covering `[-half_extent, half_extent]` on X/Z. A non-positive `cell_size`, a non-finite `half_extent` or a non-finite `goal` is reported and gives an empty field; a `nav_grid` that doesn't fit is reported and ignored. `positions` (an Array or `PackedVector3Array`) is the crowd: the density of every cell a path enters adds to its cost. `should_stop`, polled while computing, ends it early with an empty field. `ground` (from `prepare_ground` for the same grid) is used instead of reading `nav_grid`, which it then ignores; one for another grid size is reported and `nav_grid` read. |
| `prepare_ground` | `static prepare_ground(half_extent: float, cell_size: float, nav_grid: Dictionary = {}) -> Ground` | What `compute` works out from the ground alone (walls, allowed steps, how deep each wall cell is), to pass to every compute over that ground. Reports a `nav_grid` that doesn't fit as `compute` does. Measured on a desktop CPU it is about 30–40% of a compute's time (see Notes). |
| `Ground` | inner class `LFFlowField.Ground` (made by `prepare_ground`) | `var cols: int` and the prepared per-cell arrays (`blocked`, `allowed`, `escape`). Nothing changes it after it is made (leave it unchanged too), so computes on several threads may share one. |
| `sample_direction` | `static sample_direction(field: Field, position: Vector3) -> Vector3` | `field.sample(position)`; `Vector3.ZERO` for a null field. |
| `climbable_masks` | `static climbable_masks(lattice: PackedFloat32Array, lattice_spacing: float, half_extent: float, cell_size: float, max_slope_deg: float) -> PackedInt32Array` | Builds a nav grid's `climbable` from a square height lattice (`round(2·half_extent / lattice_spacing) + 1` samples per side, read as a bilinear surface): per cell, the neighbors reached from its centre without climbing steeper than `max_slope_deg`; going down is always allowed. A lattice of the wrong size is reported and allows every step. |
| `nav_grid` | `static nav_grid(half_extent: float, cell_size: float, height_at: Callable, wall_rects: Array[Rect2], lattice: PackedFloat32Array, lattice_spacing: float, max_slope_deg: float) -> Dictionary` | The whole `nav_grid` below in one call: `height_at(x, z)` at each cell centre, every cell a wall rect overlaps blocked, `climbable` from `lattice` (empty `lattice`: flat, every step allowed). Add `max_climb` yourself. |
| `DEFAULT_DENSITY_WEIGHT` | `const DEFAULT_DENSITY_WEIGHT := 2.0` | Default `density_weight`: how strongly crowding bends paths; 0 ignores the crowd, and so does a negative or non-finite value. |
| `Field` | inner class `LFFlowField.Field` (made by `compute`) | `var goal: Vector3`, `var half_extent: float`, `var cell_size: float`, `var cols: int`, `var rows: int` (equal to `cols`; both 0 when the grid has no cells), `var directions: PackedVector3Array` (one unit XZ direction per cell, row-major), and `sample(position: Vector3) -> Vector3`: the direction at `position`, clamped into the grid; zero for an empty field and at the goal's cell centre (near a goal that is off its cell's centre, it still points toward the goal). |

#### Costs and directions

A cell's cost is its cheapest path to the goal (8 neighbors, diagonals √2), plus the
blurred crowd density of each cell entered. Each direction is a grid step toward the
cheapest allowed neighbor; neighbors tied for cheapest are blended when the blend heads
for one of them, so the field mirrors across axes through the goal.
The step goes to the allowed neighbor with the lowest cost-to-goal, ignoring the length of
the step and that neighbor's own density, so a unit that follows the directions exactly can
end up a little longer than the cheapest path.

#### `nav_grid`

Optional, row-major per cell, matching the field's grid:

| Key | Value |
|---|---|
| `cols`, `rows` | The grid size; must equal the field's. |
| `blocked` | Array or packed array, truthy for a wall. |
| `heights` | Array or packed array of ground heights. |
| `climbable` (optional) | Array or packed array: per cell, a 9-bit mask of the neighbors one may walk to (`LFGrid2D.neighbor_bit`); `climbable_masks` builds it. |
| `max_climb` (optional) | The largest rise between adjacent cells a path takes; no limit without it. |

Paths never enter a blocked cell and never cut a diagonal past a blocked corner;
`max_climb` never limits stepping down (a `climbable` mask can still forbid any step). A grid of the wrong size or with arrays of the wrong length is
reported (`push_error`) and the ground treated as open.

### LFFlowFieldService

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFFlowFieldService.new(grid_half_extent: float, grid_cell_size: float = DEFAULT_CELL_SIZE, initial_refresh_interval: float = DEFAULT_REFRESH_INTERVAL, initial_density_weight: float = LFFlowField.DEFAULT_DENSITY_WEIGHT)` (3.0, 1.0, 2.0) | Fields over `[-grid_half_extent, grid_half_extent]` on X/Z in cells of `grid_cell_size`, each recomputed every `initial_refresh_interval` seconds while wanted. A non-positive cell size or non-finite half extent is reported and no field ever becomes ready. |
| `half_extent`, `cell_size` | `var half_extent: float`, `var cell_size: float` (read-only) | The grid, fixed at construction; setting either is reported and ignored. |
| `refresh_interval` | `var refresh_interval: float` | Seconds between recomputes of a wanted field; a change applies from the next `tick`. A NaN is rejected: reported through `LFLogger` as an error, and the value is kept. |
| `density_weight` | `var density_weight: float` | Passed to every compute started after a change; 0 routes as if the ground were empty. |
| `DEFAULT_CELL_SIZE`, `DEFAULT_REFRESH_INTERVAL` | `const DEFAULT_CELL_SIZE := 3.0`, `const DEFAULT_REFRESH_INTERVAL := 1.0` | Defaults of `_init`: the grid cell side (world units) and the seconds between recomputes. |
| `DEFAULT_MAX_CONCURRENT` | `const DEFAULT_MAX_CONCURRENT := 4` | Default `max_concurrent`. |
| `max_concurrent` | `var max_concurrent: int = DEFAULT_MAX_CONCURRENT` (4) | Computes running at once; a due field beyond that waits for a free slot. |
| `request_field` | `request_field(goal: Vector3) -> void` | Wants `goal`'s field. A newly wanted cell, or a different goal in a wanted cell, is due on the next `tick`; repeating the same goal does nothing, so calling it every frame still recomputes only every `refresh_interval`. A non-finite goal is reported and ignored. |
| `direction` | `direction(goal: Vector3, position: Vector3) -> Vector3` | From the ready field; zero while none is. |
| `field_for` | `field_for(goal: Vector3) -> LFFlowField.Field` | The ready field, or null — to keep and sample while the goal holds. |
| `cell_for` | `cell_for(goal: Vector3) -> Vector2i` | The grid cell goals are keyed by; goals in one cell share a field. |
| `tick` | `tick(delta: float, positions: Variant = []) -> void` | Advances the refresh timers by `delta` seconds (a negative or non-finite delta adds nothing), starts due recomputes (on `LFThread`s) and swaps in finished ones. `positions` may be a Callable, called only when a compute starts. |
| `prune` | `prune(active_goals: Array) -> void` | Forgets fields whose goal is no longer active; a compute still running for one is stopped and never published (a goal wanted again before it ends is simply computed again). |
| `set_nav_grid` | `set_nav_grid(grid: Dictionary) -> void` | New ground (the service keeps a copy): ready fields are dropped, computes running on the old ground are stopped and thrown away, wanted fields recompute next `tick`. |
| `nav_grid` | `var nav_grid: Dictionary` (read-only) | The current ground. Assigning it is reported and ignored (use `set_nav_grid`); don't edit the returned dictionary, running computes may be reading it. |
| `is_pending`, `pending_count` | `is_pending(goal: Vector3) -> bool`, `pending_count() -> int` | Whether a compute for `goal`'s cell is running; how many are running. |
| `version` | `var version: int` (read-only) | Goes up by one on every `field_updated` and `field_dropped` (already counted when the signal fires). Compare it with the value you stored to know a kept field must be read again. |
| `field_updated` | `signal field_updated(cell: Vector2i)` | A new field is ready. |
| `field_dropped` | `signal field_dropped(cell: Vector2i)` | A ready field was dropped (`prune`, `set_nav_grid`); stop sampling a kept copy. |

## Usage

```gdscript
# The background service: a script on the node that owns the crowd. Units are Node3D children that steer by the
# field; the battlefield is 120 x 120 m around the origin, in 3 m cells.
extends Node3D

var fields := LFFlowFieldService.new(60.0, 3.0)
var goal := Vector3(40, 0, 0)
var speed := 4.0


func _ready() -> void:
	fields.request_field(goal)


func _physics_process(delta: float) -> void:
	# Starts due recomputes and swaps in finished ones. The crowd is read only on a
	# frame that starts a compute, so pass a Callable.
	fields.tick(delta, crowd_positions)
	for unit: Node3D in get_children():
		var direction := fields.direction(goal, unit.global_position)
		if direction == Vector3.ZERO:  # no field yet, or standing on the goal
			direction = unit.global_position.direction_to(goal)
		unit.global_position += direction * speed * delta


func crowd_positions() -> PackedVector3Array:
	var positions := PackedVector3Array()
	for unit: Node3D in get_children():
		positions.append(unit.global_position)
	return positions
```

Walls: describe the ground once with a nav grid (see `nav_grid` above) and hand it over. These lines go inside a function, with `fields` the `LFFlowFieldService` created above:

```gdscript
var cols := LFGrid2D.cells_across(60.0, 3.0)
var blocked := PackedByteArray()
var heights := PackedFloat32Array()
blocked.resize(cols * cols)
heights.resize(cols * cols)
for cell in LFGrid2D.cells_overlapping(Rect2(10, -20, 3, 40), 60.0, 3.0):  # a long wall
	blocked[LFGrid2D.index_of(cell, cols)] = 1
fields.set_nav_grid({'cols': cols, 'rows': cols, 'blocked': blocked, 'heights': heights})
```

Computing one field directly (on the calling thread), with the crowd taken into account. These lines go inside a function, with `goal` a `Vector3`, `unit` a `Node3D` and `crowd_positions()` the method from the example above:

```gdscript
var field := LFFlowField.compute(goal, 60.0, 3.0, crowd_positions())
var direction := field.sample(unit.global_position)
```

## Notes

- The service runs each compute on an `LFThread`. Where threads are unavailable
  (`OS.has_feature("threads")` is false, e.g. a web export built without threads),
  `LFThread` runs the compute on the main thread instead, blocking inside `tick` until it
  is done, so a recompute then costs a frame hitch rather than running in the background:
  measured on a desktop CPU with 1000 crowd positions, about 50–60 ms for a 100 × 100 grid and
  300–370 ms for 250 × 250, and the first compute after `set_nav_grid` (or the first one
  ever) about 90 ms and 560 ms, since it also prepares the ground.
- The service prepares the ground (`LFFlowField.prepare_ground`) once per `set_nav_grid`,
  inside the first compute on it, and every later compute reuses it. Each compute still
  allocates its own search buffers (computes on different threads cannot share them).
- The service only works while you call `tick` every frame: it starts computes there and
  swaps in finished ones. A field arrives a frame or more after `request_field`, so
  `direction()` reads zero until then — have a fallback (such as heading straight for
  the goal).
- A finished compute is published only when it is whole: a compute that was told to stop
  (pruned, or started on old ground) never replaces or creates a ready field.
- A cell that cannot reach the goal points straight at it, so movers still head that way
  as far as they can.
- A goal inside a blocked cell routes to the nearest open cells around it.
- A goal off the grid routes to the edge cells nearest it, then points straight at it.
- A body standing in a blocked cell (open ground the grid marks as wall) is pointed to the
  nearest open cell, the cheapest one when several are equally near — which can be on the
  far side of a wall thinner than a cell.
- Two equally good ways round an obstacle are not blended into a step at it: the one
  nearer the bearing to the goal wins, and an exact tie always goes the same way.
- Directions are grid steps, not exact bearings: one of the 8 neighbor directions, or a
  blend of tied ones.
- The grid is square: one `half_extent` and one `cell_size` for both axes.
- Memory and time grow with the cell count (`cols²`); there is no cap, so a tiny `cell_size` over a large `half_extent` allocates accordingly.
- `max_climb` is in world units, so it depends on `cell_size`.
