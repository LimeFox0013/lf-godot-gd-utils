# LFRingSlots

> The nearest free spot around a point, searched ring by ring, so an arriving crowd settles into a packed disc.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_ring_slots.gd` |
| **Tests** | `tests/test_lf_ring_slots.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFSpatialIndex`, `LFUtils3D`, `LFLogger` (reports a bad `spacing`) |

## When to use it

Use it when many units are sent to one point (a rally flag, a gather order, a capture
zone) and should end up standing side by side around it rather than all pushing for the
exact same spot. Each unit asks for the free spot nearest the side it comes from; give
each unit an `Arrival` so it keeps its spot while being jostled, and share one `Claims`
between them so units arriving together don't pick the same spot. Occupancy comes from
an `LFSpatialIndex` you already keep up to date. For a fixed formation (rows, a wedge),
compute the offsets yourself instead; for steering around obstacles on the way there,
use `LFFlowField` or a `NavigationAgent3D`.

## Step by step

Goal: ask for a free standing spot near a waypoint, and see that a second body is given a
different one. "Slots" are the spots on rings around the waypoint; the index (an
`LFSpatialIndex`) tells the function where bodies already stand.

1. Choose *Scene → New Scene*, pick *Other Node*, create a `Node3D`, and save the scene.
2. Right-click it in the Scene dock, choose *Attach Script*, then *Create*.
3. Replace the script with the code below.
4. Press *F6* (run the current scene).
5. Read the *Output* panel. You should see `a stands at (0.0, 0.0, 0.0)` (the waypoint
   itself was free) and `b stands at (1.0, 0.0, 0.0)` (one unit away, on the side b
   comes from).

```gdscript
extends Node3D


func _ready() -> void:
	var waypoint := Vector3.ZERO            # the point everyone is heading for
	var index := LFSpatialIndex.new(4.0)    # where bodies stand (4.0 = cell width, world units)

	# First body, coming from the +X side. The key ("a") is how the index knows it;
	# any unique value works. Passing it as `exclude` stops the body blocking itself.
	var spot_a := LFRingSlots.find_slot(waypoint, Vector3(10, 0, 0), index, "a", 1.0)
	index.register("a", spot_a)             # it now "stands" there
	print("a stands at ", spot_a)

	# Second body, also from +X: the waypoint is taken, so it gets the nearest free spot on the ring around it.
	var spot_b := LFRingSlots.find_slot(waypoint, Vector3(10, 0, 0), index, "b", 1.0)
	print("b stands at ", spot_b)
```

The `1.0` is the spacing between neighboring spots in world units (use about the width
of your units). Inside a real game you would register each body under itself (the node)
and keep its position current with `index.update_position(...)`; the Usage section below
shows a complete unit script.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_SPACING` | `const DEFAULT_SPACING := 1.0` | Default distance between neighboring spots and between rings. |
| `DEFAULT_MAX_RINGS` | `const DEFAULT_MAX_RINGS := 5` | Default number of rings searched. |
| `find_slot` | `static find_slot(center: Vector3, from: Vector3, spatial_index: LFSpatialIndex, exclude: Variant, spacing := DEFAULT_SPACING, max_rings := DEFAULT_MAX_RINGS, claims: Claims = null) -> Vector3` | `center` when free (ignoring `exclude`); spots others hold in `claims` count as taken; otherwise the free ring position nearest `from`, rings `spacing` apart; with every ring full, the outermost ring's point nearest `from`. A non-finite `from` counts as coming from `center`; a null `spatial_index` counts as nobody standing anywhere. |
| `Claims` | inner class `LFRingSlots.Claims.new()` | Spots promised to claimants before they reach them, one per claimant: `claim(claimant: Variant, slot: Vector3) -> void` (replaces its earlier spot), `release(claimant: Variant) -> void`, `slot_of(claimant: Variant) -> Variant` (the spot or null), `size() -> int`, `clear() -> void`. A freed Object claimant is forgotten on the next search. |
| `Arrival` | inner class `LFRingSlots.Arrival.new(initial_enter_radius: float, initial_exit_radius: float, initial_spacing: float = DEFAULT_SPACING, initial_max_rings: int = DEFAULT_MAX_RINGS)` | A committed slot with hysteresis, one per arriving body (below). |
| `Arrival.destination` | `destination(goal: Vector3, from: Vector3, index: LFSpatialIndex, exclude: Variant, extra_ok := true) -> Variant` | Inside the zone: the committed slot, claimed with `find_slot` on entry (within `enter_radius`) and kept until beyond `exit_radius`. Outside it, or when `extra_ok` is false: null, and the slot is dropped. A different `goal` drops the slot first. |
| `Arrival.slot`, `Arrival.reset` | `slot() -> Variant`, `reset() -> void` | The committed slot or null; drop it. |
| `Arrival.enter_radius`, `exit_radius`, `spacing`, `max_rings` | `var enter_radius: float`, `var exit_radius: float`, `var spacing: float`, `var max_rings: int` | Set by the constructor (where `exit_radius` is raised to `enter_radius` when smaller); may change later. `spacing` and `max_rings` are passed to `find_slot`. |
| `Arrival.claims` | `var claims: Claims = null` | Shared by every arrival heading for the same places: the held slot is claimed under `exclude` and released when dropped or reset, so arrivals entering together don't commit to one spot while a free one remains (with every ring full they can share the fallback point). |
| `ring_candidates` | `static ring_candidates(center: Vector3, radius: float, spacing: float) -> Array[Vector3]` | One ring's candidate positions — an even count (≥ 6), symmetric across both axes; none (and an error) for a `spacing` that is not finite and positive. |

## Usage

One-off: where should this body stand near `waypoint`? This line goes inside a function, with `waypoint` a `Vector3`, `body` a `Node3D` and `spatial_index` an `LFSpatialIndex` holding the bodies:

```gdscript
var target := LFRingSlots.find_slot(waypoint, body.global_position, spatial_index, body, 1.0)
```

Per unit, with hysteresis ("stickiness": a jostled body keeps its spot) and shared claims (bodies
arriving together don't pick the same spot while free ones remain):

```gdscript
# unit.gd, on a CharacterBody3D. `spatial_index` is the LFSpatialIndex every unit is
# registered in (under the unit itself), kept current by whoever owns the units.
extends CharacterBody3D

# One Claims for every unit heading to the same places (a static var is one per class).
static var claims := LFRingSlots.Claims.new()

var spatial_index: LFSpatialIndex
var waypoint := Vector3.ZERO
var speed := 5.0
# Claim a spot within 6 m of the waypoint; keep it until farther than 9 m.
var arrival := LFRingSlots.Arrival.new(6.0, 9.0)


func _ready() -> void:
	arrival.claims = claims


func _physics_process(_delta: float) -> void:
	var slot: Variant = arrival.destination(waypoint, global_position, spatial_index, self)
	var target: Vector3 = slot if slot != null else waypoint  # outside the zone: route as usual
	if global_position.distance_to(target) > 0.1:
		velocity = global_position.direction_to(target) * speed
	else:
		velocity = Vector3.ZERO
	move_and_slide()


func _exit_tree() -> void:
	arrival.reset()  # releases its claimed spot
```

## Notes

- `exclude` is the one key to ignore, the same value the arriving body was registered
  under in `spatial_index` (a Node, an id…). Keys are compared by value; a key of a
  different type never matches.
- "Free" means no occupant within `spacing / 2` on the XZ plane and less than `spacing`
  above or below — a body standing over a point takes it, one on another level does not.
- Occupancy comes from one `spatial_index` query per call, so registered positions must
  be current. Without `claims` nothing is reserved: arrivals choosing in the same frame,
  before any stands in its spot, can choose the same one.
- A `spacing` that is not finite and positive is reported (the answer is `center`); `max_rings` of 0 answers
  `center` even when it is taken.
- `find_slot` writes no static state: rings 1–16 are built when the class loads and only
  read afterwards (rings further out are built per call, uncached). It does write the
  objects you pass: its `LFSpatialIndex` query forgets freed objects it meets, and a
  `Claims` drops freed claimants. Calling it from a worker thread is therefore only safe
  while no other thread uses that index or `Claims`; the tests do not exercise threads.
- Each extra ring adds more candidates to check (about 6 per ring number), so keep
  `max_rings` small; it only matters when the inner rings are full.
