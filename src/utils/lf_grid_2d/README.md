# LFGrid2D

> Static helpers for a square grid of cells laid on the ground (the XZ plane), centred on the origin: world position to cell, cell to index, and back.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_grid_2d.gd` |
| **Tests** | `tests/test_lf_grid_2d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` (reports a bad `cell_size` or `half_extent`) |

## When to use it

Use it when you keep one value per patch of ground (blocked or open, a height, a heat
map of where units died) and need to turn a world position into "which cell" and back.
For example: mark the cells under every wall as blocked before computing an
`LFFlowField`, which uses this same layout. The grid covers `[-half_extent, half_extent]`
on X and Z in square cells of `cell_size`; cell (cx, cz) lives at index `cz * cols + cx`
("row-major": row by row; an *index* is a position in a plain array). For tile-based levels drawn in the editor, Godot's
`TileMapLayer` / `GridMap` (`local_to_map`) is the better fit; for "who is near me"
queries over moving objects use `LFSpatialIndex`.

## Step by step

Goal: ask which cell of a ground grid a world position falls in, and mark cells blocked.

1. Choose *Scene → New Scene*, pick *Other Node*, create a `Node3D`, and save the scene.
2. Right-click it in the Scene dock, choose *Attach Script*, then *Create*.
3. Replace the script with the code below.
4. Press *F6* (run the current scene).
5. Read the *Output* panel at the bottom. You should see the grid size (20), the cell of a
   position, and `true` / `false` for the blocked check.

```gdscript
extends Node3D

const HALF_EXTENT := 30.0   # the grid reaches 30 world units each way from the origin (60 wide)
const CELL_SIZE := 3.0      # each square cell is 3 world units wide

var cols := LFGrid2D.cells_across(HALF_EXTENT, CELL_SIZE)   # cells per side: 20
var blocked := PackedByteArray()   # one byte per cell: 0 = open, 1 = blocked


func _ready() -> void:
	blocked.resize(cols * cols)
	# Rect2(x, z, width, depth): mark every cell this rectangle of ground touches.
	for cell in LFGrid2D.cells_overlapping(Rect2(-2.0, 5.0, 4.0, 2.0), HALF_EXTENT, CELL_SIZE):
		blocked[LFGrid2D.index_of(cell, cols)] = 1
	print("cells per side: ", cols)
	print("cell of (0, 0, 0): ", LFGrid2D.cell_of(Vector3.ZERO, HALF_EXTENT, CELL_SIZE, cols, cols))
	var wall_cell := LFGrid2D.cell_of(Vector3(0.0, 0.0, 6.0), HALF_EXTENT, CELL_SIZE, cols, cols)
	print("wall cell blocked: ", blocked[LFGrid2D.index_of(wall_cell, cols)] == 1)
```

Change `HALF_EXTENT` and `CELL_SIZE` to match your level (both in world units, like
metres). The grid lies flat on the ground, so "Z" plays the role of "down the screen".

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `NEIGHBORS_8` | `const Array[Vector2i]` | The 8 neighbor offsets, row by row. |
| `NEIGHBOR_STEP_LENGTHS` | `const Array[float]` | The step length (in cells) to each of `NEIGHBORS_8`, same order: √2 diagonally, 1 straight. |
| `cells_across` | `static cells_across(half_extent: float, cell_size: float) -> int` | Cells per axis (a partial cell counts, except a sliver under a millionth of a cell, so float rounding on an exact fit does not add one). 0 for a negative extent; 0 and an error for a non-positive `cell_size` or a non-finite `half_extent`. Not capped: a tiny `cell_size` over a large extent names more cells than an array holds. |
| `cell_center` | `static cell_center(cx: int, cz: int, half_extent: float, cell_size: float) -> Vector3` | World centre of a cell, y = 0. |
| `cell_of` | `static cell_of(position: Vector3, half_extent: float, cell_size: float, cols: int, rows: int) -> Vector2i` | The cell holding `position`, clamped into the grid. |
| `index_of` | `static index_of(cell: Vector2i, cols: int) -> int` | Row-major index, `cell.y * cols + cell.x`. |
| `in_bounds` | `static in_bounds(cell: Vector2i, cols: int, rows: int) -> bool` | Whether the cell lies inside the grid. |
| `cells_overlapping` | `static cells_overlapping(rect: Rect2, half_extent: float, cell_size: float) -> Array[Vector2i]` | Every in-grid cell whose area overlaps an XZ rect (`rect.position.y` is Z), row by row; a shared edge alone does not count. |
| `neighbor_bit` | `static neighbor_bit(offset: Vector2i) -> int` | Bit 0–8 of a neighbor offset in a per-cell 9-bit mask (4 is the cell itself). |

## Usage

```gdscript
# A fuller script: a 60 x 60 m field in 3 m cells (a 20 x 20 grid).
extends Node3D

const HALF_EXTENT := 30.0
const CELL_SIZE := 3.0

var cols := LFGrid2D.cells_across(HALF_EXTENT, CELL_SIZE)  # 20
var blocked := PackedByteArray()


func _ready() -> void:
	blocked.resize(cols * cols)
	# Block every cell a 4 x 2 m wall footprint touches (Rect2's y is world Z).
	for wall_cell in LFGrid2D.cells_overlapping(Rect2(-2.0, 5.0, 4.0, 2.0), HALF_EXTENT, CELL_SIZE):
		blocked[LFGrid2D.index_of(wall_cell, cols)] = 1


func is_blocked_at(world_position: Vector3) -> bool:
	var cell := LFGrid2D.cell_of(world_position, HALF_EXTENT, CELL_SIZE, cols, cols)
	return blocked[LFGrid2D.index_of(cell, cols)] == 1


func neighbors_of(cell: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for offset in LFGrid2D.NEIGHBORS_8:
		if LFGrid2D.in_bounds(cell + offset, cols, cols):
			found.append(cell + offset)
	return found
```

## Notes

- The grid is square: one `half_extent` and one `cell_size` for both axes.
- `cell_of` has unchecked preconditions (it runs in hot loops): a finite position, a
  positive `cell_size`, and `cols`/`rows` of at least 1. Within them it clamps anything
  off the grid to the nearest edge cell.
- `cells_overlapping` reads the rect on the XZ plane, so a `Rect2`'s `y` is world Z.
