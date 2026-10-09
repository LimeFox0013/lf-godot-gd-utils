# LFSpatialIndex

> Finds registered objects near a point ("everything within 5 m", "the nearest enemy") by sorting their 3D positions into a grid of cells, so a query checks only the objects in the cells its radius touches.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_spatial_index.gd` |
| **Tests** | `tests/test_lf_spatial_index.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` (reports an unusable `cell_size`) |

## When to use it

Use it when many moving things need to find each other every frame: a tower looking for
the nearest enemy in range, a unit pushing away from neighbors, an explosion damaging
everything within 5 m. Checking every object against every other grows with the square of the count (100
units means 10,000 distance checks); the index only looks at objects in nearby grid
cells. For a handful of objects a plain loop is fine. For physics-accurate shapes, or
when the objects already have collision shapes, use an `Area3D` or
`PhysicsDirectSpaceState3D.intersect_shape` instead. To look objects up by an exact value
(team, type) rather than by distance, use `LFInvertIndex`.

## Step by step

Goal: register a few markers in the index, then ask "what is near this point?" and "which
one is nearest?".

1. Choose *Scene → New Scene*, pick *Other Node*, create a `Node3D`, and save the scene.
2. Right-click it in the Scene dock, choose *Attach Script*, then *Create*.
3. Replace the script with the code below.
4. Press *F6* (run the current scene).
5. Read the *Output* panel. You should see two names within 5 units of the origin, then
   the nearest one, `Near`.

```gdscript
extends Node3D


func _ready() -> void:
	# The index sorts positions into square cells. 5.0 is the cell width in world units;
	# pick about the distance you usually search within.
	var index := LFSpatialIndex.new(5.0)

	# Make three markers at different spots. (In a real game these are your units.)
	var near := Marker3D.new()
	near.name = "Near"
	near.position = Vector3(2, 0, 0)
	var middle := Marker3D.new()
	middle.name = "Middle"
	middle.position = Vector3(4, 0, 0)
	var far := Marker3D.new()
	far.name = "Far"
	far.position = Vector3(40, 0, 0)

	# Tell the index where each one is. Call update_position again whenever one moves.
	for marker in [near, middle, far]:
		add_child(marker)
		index.register(marker, marker.position)

	# Everything within 5 units of the origin (an Array of the registered objects).
	for found in index.query_radius(Vector3.ZERO, 5.0):
		print("within 5: ", found.name)

	# The single closest object within 50 units, or null if there is none.
	var nearest: Variant = index.query_nearest(Vector3.ZERO, 50.0)
	print("nearest: ", nearest.name)
```

Change the numbers to your game's scale: positions and radii are world units, and the
cell width (`5.0`) is also in world units. If your units only move on the ground, create
the index with `LFSpatialIndex.new(5.0, true)` (the `true` means "ignore height when
sorting into cells"; distances are still 3D).

## API

Everything the class offers; you only need the rows used above to get started.

### Properties

| Member | Signature | Description |
|---|---|---|
| `cell_size` | `var cell_size: float` | Grid cell edge length, finite and > 0. Changing it re-buckets every registered object; any other value is reported and ignored. |
| `planar` | `var planar: bool` | Bucket by X/Z only. Changing it re-buckets every registered object. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_CELL_SIZE` | `const DEFAULT_CELL_SIZE := 4.0` | Default `cell_size`, in world units. |
| `_init` | `LFSpatialIndex.new(initial_cell_size := DEFAULT_CELL_SIZE, is_planar := false)` (4.0) | A non-positive or non-finite `initial_cell_size` is reported and `DEFAULT_CELL_SIZE` kept. `is_planar` buckets by X/Z only: for things spread over the ground, a query reads one layer of cells instead of every layer its radius spans in Y. Distances stay 3D, so results are the same. |
| `clear` | `clear() -> void` | Forgets every registered object. |
| `register` | `register(object: Variant, position: Vector3) -> void` | Adds `object`; if already registered, behaves as `update_position`. |
| `update_position` | `update_position(object: Variant, position: Vector3) -> void` | Moves `object`, changing cell only when needed; registers it if untracked. |
| `remove` | `remove(object: Variant) -> void` | Erases `object` from its cell. No-op if never registered. |
| `query_radius` | `query_radius(position: Vector3, radius: float) -> Array` | Exactly the objects with `distance <= radius` (boundary inclusive), unordered, in a new array each call, so you may query again while iterating a result. A freed object is never returned; the query forgets it. |
| `query_radius_positions` | `query_radius_positions(position: Vector3, radius: float, out_positions: PackedVector3Array) -> Array` | `query_radius`, also filling `out_positions` with each returned object's position in the same order (its content replaced). |
| `query_nearest` | `query_nearest(position: Vector3, radius: float, accept := Callable(), exclude: Variant = null) -> Variant` | The nearest object within `radius` (boundary inclusive) that `accept` takes, or null; never `exclude`. `accept(object)` — or `accept(object, position)` when it takes two arguments — is called only for a candidate nearer than the best accepted so far. Of equally near candidates, the first one the scan meets wins; which that is depends on the order the cells are visited (a wide query visits them differently from a narrow one), so don't rely on it. Builds no array or object of its own (`accept` may); a freed object it meets is forgotten. `accept` may run other queries, but must not register, move or remove objects. |
| `has` | `has(object: Variant) -> bool` | Whether `object` is registered. |
| `position_of` | `position_of(object: Variant) -> Variant` | Its registered position, or null. |
| `positions` | `positions() -> PackedVector3Array` | Every registered position, unordered; a new array each call. |
| `size` | `size() -> int` | Registered objects. |
| `cell_count` | `cell_count() -> int` | Cells holding at least one object. |

## Usage

```gdscript
# A fuller script on the node that owns the units (a level, a battle manager).
extends Node3D

# Cells about the size of a typical query radius; planar: everything is on the ground.
var index := LFSpatialIndex.new(5.0, true)


func add_unit(unit: Node3D) -> void:
	add_child(unit)
	index.register(unit, unit.global_position)


func remove_unit(unit: Node3D) -> void:
	index.remove(unit)
	remove_child(unit)  # out of get_children() now, so the loop below can't register it again
	unit.queue_free()


func _physics_process(_delta: float) -> void:
	# Keep every position current, once per frame.
	for unit in get_children():
		index.update_position(unit, unit.global_position)


# Everything within `radius` of `point`, e.g. for an explosion.
func units_near(point: Vector3, radius: float) -> Array:
	return index.query_radius(point, radius)


# The nearest unit of another team within 8 m of `unit`, or null. The filter runs
# only for a candidate nearer than the best found so far, so costly checks go there.
func nearest_enemy(unit: Node3D) -> Variant:
	return index.query_nearest(unit.global_position, 8.0,
		func(other): return other.get_meta("team") != unit.get_meta("team"), unit)
```

## Notes

- `register`/`update_position`/`remove` do a constant number of Dictionary operations (O(1) on average). A query scans every cell in its bounding box, so its cost grows with `(radius / cell_size)^3` — `^2` when `planar` — plus the objects in those cells. When that box has more cells than are occupied, it is clamped to a box around the occupied cells (kept up to date as cells are made; re-measured in one pass over the occupied cells only after cells on its edge emptied), and when even that holds more cells than are occupied, the query walks the occupied cells instead, testing each object in those inside its box. So a query never looks at more cells than the smaller of its box and the occupied-cell count: a huge or `INF` radius costs one pass over the occupied cells and their objects (measured on a desktop CPU: 500 objects spread over 1000 × 50 × 1000 units in cells of 1, `query_nearest` with radius 40 ≈ 0.1 ms, with `INF` ≈ 0.35 ms). Pick `cell_size` close to typical query radii; use `planar` for anything on the ground.
- Each cell stores its objects' positions next to them, so a query never looks a position up per candidate.
- Objects are dictionary keys, so they are identified by Variant equality: Dictionaries or Arrays with equal content collide, and one mutated after registering can no longer be found. Use Objects (or unique values) as keys.
- A freed Object stays registered until a query reaches it (or you `remove` it); queries never return it. One met by a query run from inside a `query_nearest` `accept` is forgotten when that outer query ends.
- A negative (or NaN) radius finds nothing; a zero radius finds only an object exactly at `position`.
- `query_nearest` compares `exclude` by value and only with keys of its own type.
- A NaN position lands in a CPU-dependent cell, but its distance is never within range, so no query returns it.
- Cell coordinates are 32-bit ints: positions beyond about 2 billion cells from the origin (`2e9 * cell_size` world units) are not supported.
- Cells are dropped as soon as they empty; `clear()` forgets every object.
- Uses only `LFLogger`; complements `LFInvertIndex` (exact-value lookup) for proximity lookup.
