# LFTerrainFeatures

> A terrain described as a list of plain-data features (platforms, ramps, hills, walls, foliage) that answers how high the ground is, what blocks sight, whether a straight walk is possible and what a flow field's walkability grid looks like.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_terrain_features.gd` |
| **Tests** | `tests/test_lf_terrain_features.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFHeightmap`, `LFFlowField`, `LFGrid2D`, `LFUtils3D` |

## When to use it

Use it when a level is a handful of hand-placed shapes (raised areas, ramps, mounds, walls,
bushes) and your code keeps asking questions about them: how high is the ground here, can
this unit see that one, can it walk straight there. The answers are plain maths on the
list, so there are no raycasts and the same object can feed the ground mesh (`LFHeightmap`),
the flow field (`LFFlowField`) and line-of-sight checks. For terrain you paint in the editor
use a terrain plugin instead.

## Step by step

1. Choose *Scene → New Scene*, pick *Other Node*, create a `Node`, and save the scene.
2. Right-click it, choose *Attach Script*, then *Create*, and replace the script with the code below.
3. Press *F6*. The *Output* panel should print `3.0`, `true` and `false`: the top of the
   platform is 3 high, a wall hides one side of the field from the other, and a walker cannot
   climb the platform's sheer side.

```gdscript
extends Node


func _ready() -> void:
	var terrain := LFTerrainFeatures.new([
		{ 'type': 'platform', 'rect': Rect2(0, 0, 10, 10), 'height': 3.0 },
		{ 'type': 'wall', 'rect': Rect2(-20, -1, 4, 2), 'height': 3.0 },
	])
	print(terrain.height_at(5.0, 5.0))
	print(terrain.blocks_sight_between(Vector3(-25, 0, 0), Vector3(-10, 0, 0)))
	print(terrain.is_walkable_between(Vector3(-5, 0, 5), Vector3(5, 3, 5)))
```

## Features

Each feature is a Dictionary; rects are XZ (`Rect2`'s `y` is world Z), heights in world units.

| `type` | Keys | Meaning |
|---|---|---|
| `platform` | `rect`, `height` | Flat raised area with vertical sides. |
| `ramp` | `rect`, `height`, `low_edge` | Rises linearly from 0 at `low_edge` (`'x-'`, `'x+'`, `'z-'`, `'z+'`: the bottom side of the rect) to `height` on the opposite side. |
| `hill` | `center` (Vector2), `radius`, `height` | A cosine mound that reaches 0 at `radius`. |
| `wall` | `rect`, `height` | Blocks movement and sight. |
| `foliage` | `rect` | Blocks sight only. |

## API

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFTerrainFeatures.new(initial_features: Array[Dictionary] = [], initial_max_slope_deg := DEFAULT_MAX_SLOPE_DEG, initial_sight_step := DEFAULT_SIGHT_STEP, initial_footprint_grow := DEFAULT_FOOTPRINT_GROW)` | A terrain over the features. |
| `features` | `var features: Array[Dictionary]` | Assigning sorts them again; lists handed out earlier stay as they were. |
| `max_slope_deg`, `sight_step`, `footprint_grow` | `var` floats (30.0, 0.5, 0.001) | The steepest climbable face in degrees, the longest sample step along a segment, and how far an elevation feature's rect is widened when a lattice is sampled. |
| `has_elevation` | `has_elevation() -> bool` | Whether any platform, ramp or hill exists. |
| `walls`, `foliage` | `walls() -> Array[Dictionary]`, `foliage() -> Array[Dictionary]` | Those features, in list order. |
| `height_at` | `height_at(x: float, z: float) -> float` | The highest elevation feature covering the point; 0 elsewhere. A rect includes its edges. |
| `height_lattice` | `height_lattice(half_extent: float, spacing: float) -> PackedFloat32Array` | `height_at` on an `LFHeightmap` lattice, evaluated only near elevation features; all zeros without any. |
| `is_wall_at`, `blocks_sight_at` | `(x: float, z: float) -> bool` | A wall covers the point; a wall or foliage does. Edges included. |
| `blocks_sight_between` | `blocks_sight_between(from: Vector3, to: Vector3) -> bool` | Something opaque on the XZ segment, sampled every `sight_step` or less with both ends included. |
| `is_walkable_between` | `is_walkable_between(from: Vector3, to: Vector3) -> bool` | A straight walk never climbs a face steeper than `max_slope_deg`; dropping down is fine. |
| `nav_grid` | `nav_grid(half_extent: float, cell_size: float, lattice_spacing: float) -> Dictionary` | `LFFlowField.nav_grid` over these features: heights, wall cells, and `climbable` from the lattice. |
| `DEFAULT_MAX_SLOPE_DEG`, `DEFAULT_SIGHT_STEP`, `DEFAULT_FOOTPRINT_GROW` | consts | Defaults of the three settings. |

## Usage

Ground mesh and flow field from one terrain:

```gdscript
var terrain := LFTerrainFeatures.new(features)
var data := terrain.height_lattice(30.0, 1.0)
add_child(LFHeightmap.build_body(data, LFHeightmap.samples_for(30.0, 1.0), 1.0, 30.0, Color.GREEN, Color.BROWN))
var grid := terrain.nav_grid(30.0, 3.0, 1.0)
grid['max_climb'] = 2.0
flow_service.set_nav_grid(grid)
```

## Notes

- A feature missing a key it needs (a ramp without `low_edge`) is a script error, as for any Dictionary lookup.
- A segment test misses a blocker thinner than `sight_step` that falls between two samples.
- Overlapping elevation features do not add: the highest wins.
