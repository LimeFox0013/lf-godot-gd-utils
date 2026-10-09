# LFCrowdBody, LFObstacleSidestep

> Keeps a crowd of walking 3D characters from piling on top of each other, lets heavy units shove light ones, adds knockback, and helps a unit step around a wall it walks straight into.

| | |
|---|---|
| **Files** | `lf_crowd_body.gd`, `lf_obstacle_sidestep.gd` |
| **Tests** | `tests/test_lf_crowd_body.gd`, `tests/test_lf_obstacle_sidestep.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFSpatialIndex`, `LFUtils3D` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFCrowdBody` | Object: create it with `.new()` |
| `LFObstacleSidestep` | Object: create it with `.new()` |

## When to use it

Use `LFCrowdBody` when a crowd of `CharacterBody3D` units walks around together
(an RTS army, a zombie horde, a tower-defense wave) and should not overlap or walk through
each other. Crowd bodies usually collide only with the ground and obstacles, not with each
other (fewer physics pairs, and bodies do not catch on each other), so `LFCrowdBody` keeps them apart instead,
lets weight decide who gives way (an infantry unit's velocity toward a heavier
neighbor it knows of is cancelled, while the heavier unit is never blocked by it; the
separation push itself ignores weight, so both are still pushed apart equally), and
adds knockback for blasts. Use `LFObstacleSidestep` so a unit that walks straight into a
wall steps around it instead of standing still. For a handful of units that may simply
collide, physics layers alone are enough; for full avoidance with path planning, see
Godot's `NavigationAgent3D` avoidance.

## Step by step

This builds a ring of 30 units that all walk to the middle and crowd together without
overlapping. A `CharacterBody3D` is Godot's node for a character you move with code.

1. **The unit scene.** *Scene → New Scene*, then under "Create Root Node" choose
   **Other Node**, search `CharacterBody3D` and press *Create*. Rename it `Unit` and save
   it with *Scene → Save Scene* as `res://unit.tscn`.
2. Select `Unit`, click **+ Add Child Node**, add a `CollisionShape3D`. In the Inspector
   (the property panel on the right) click its *Shape* slot, choose **New CapsuleShape3D**.
   Add a second child, a `MeshInstance3D`, and choose **New CapsuleMesh** in its *Mesh*
   slot, so you can see it.
3. Select `Unit` and in the Inspector open *Collision*. Set *Layer* to only **2** and
   *Mask* to only **1** (click the numbered squares). Units now stand on the ground (layer 1)
   but do not bump each other: `LFCrowdBody` keeps them apart instead.
4. With `Unit` selected click **Attach Script** (the scroll icon above the Scene dock),
   *Create*, and replace the contents with:

   ```gdscript
   extends CharacterBody3D

   # One shared "who is where" list for the whole crowd. `static` means every
   # unit uses the same one. 5.0 is the size of its grid cells in world units;
   # `true` ignores height.
   static var crowd_index := LFSpatialIndex.new(5.0, true)

   @export var speed := 4.0  # world units per second
   @export var weight := 1.0  # heavier units shove lighter ones aside
   var goal := Vector3.ZERO  # where this unit walks to
   var crowd: LFCrowdBody


   func _ready() -> void:
   	crowd = LFCrowdBody.new(self, weight)           # crowd physics for this unit
   	crowd_index.register(self, global_position)     # add it to the shared list


   # Godot calls this once per physics step; `delta` is its length in seconds.
   func _physics_process(delta: float) -> void:
   	# 1. Your own movement: walk toward the goal on the ground at `speed`
   	#    (limit_length slows the unit down once it is closer than that).
   	var to_goal := goal - global_position
   	to_goal.y = 0.0
   	var step := to_goal.limit_length(speed)
   	velocity.x = step.x
   	velocity.z = step.z
   	# 2. Crowd physics: knockback, then pushing apart.
   	velocity = crowd.velocity_with_knockback(delta)
   	crowd.resolve(crowd_index)
   	# 3. Move, then tell the shared list where this unit is now.
   	move_and_slide()
   	crowd_index.update_position(self, global_position)


   # Called when the unit leaves the scene: take it off the list.
   func _exit_tree() -> void:
   	crowd_index.remove(self)
   ```
5. **The level scene.** *Scene → New Scene*, **3D Scene**, rename the root `World`. Add
   a `StaticBody3D` child named `Floor` with a `CollisionShape3D` child (shape: **New
   BoxShape3D**, then click it and set *Size* to `60, 1, 60`) and a `MeshInstance3D`
   child (mesh: **New BoxMesh**, *Size* `60, 1, 60`). Set `Floor`'s *Position* to
   `0, -0.5, 0` so its top is at height 0. Add a `DirectionalLight3D` (*Rotation*
   `-50, 30, 0`) and a `Camera3D` (*Position* `0, 25, 18`, *Rotation* `-55, 0, 0`).
6. Select `World`, **Attach Script**, *Create*, and replace the contents with:

   ```gdscript
   extends Node3D

   # The unit scene from step 1.
   var unit_scene: PackedScene = load("res://unit.tscn")


   func _ready() -> void:
   	for i in 30:
   		# Spread 30 units around a circle 12 units from the centre.
   		var angle := TAU * i / 30.0
   		var unit := unit_scene.instantiate() as Node3D
   		unit.position = Vector3(cos(angle) * 12.0, 1.0, sin(angle) * 12.0)
   		add_child(unit)
   ```
7. Press **F6** (*Run Current Scene*) and save when asked. You should see a ring of
   capsules walk to the middle and settle into a tight cluster. Separation is a soft push
   (3 units per second per unit of overlap) against a walk of up to 4 units per second,
   so all 30 units are still pressed together and many capsules overlap a little. To see
   what the class does, put `#` in front of the `crowd.resolve(crowd_index)` line and run
   again: the units now all sit almost on one spot.
8. For your own game: change `goal` per unit, give different units a bigger `weight`, and
   tune `crowd.separation_radius` (how far apart bodies try to stay, in world units;
   about twice the body's radius). Knockback and the wall sidestep are in Usage below.

## API

Everything the two classes offer; you only need the rows used above to get started. (A Callable is a function passed around as a value.)

### LFCrowdBody

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFCrowdBody.new(character: CharacterBody3D, body_weight := DEFAULT_WEIGHT, rng: RandomNumberGenerator = null)` (1.0) | Sets `body`, `weight` and `rng`, and registers itself on the body as its `META` metadata. `rng` breaks ties and staggers refreshes (null: Godot's global generator). |
| `META` | `const META := &"lf_crowd_body"` | The metadata key. |
| `DEFAULT_WEIGHT` | `const DEFAULT_WEIGHT := 1.0` | Default `weight` (constructor `body_weight`). |
| `DEFAULT_KNOCKBACK_DECAY` | `const DEFAULT_KNOCKBACK_DECAY := 6.0` | Default `knockback_decay`. |
| `DEFAULT_SEPARATION_RADIUS` | `const DEFAULT_SEPARATION_RADIUS := 0.9` | Default `separation_radius`. |
| `DEFAULT_SEPARATION_STRENGTH` | `const DEFAULT_SEPARATION_STRENGTH := 3.0` | Default `separation_strength`. |
| `DEFAULT_NEIGHBOR_RADIUS` | `const DEFAULT_NEIGHBOR_RADIUS := 1.0` | Default `neighbor_radius`. |
| `DEFAULT_REFRESH_FRAMES` | `const DEFAULT_REFRESH_FRAMES := 3` | Default `refresh_frames`. |
| `of` | `static of(node: Variant) -> LFCrowdBody` | The crowd body registered on `node`, or null (also for null or freed). |
| `body` | `var body: CharacterBody3D` | The body whose `velocity` this changes. Not owned. |
| `weight` | `var weight: float` | Blocking compares weights: a body is blocked only by a heavier one. |
| `knockback_decay` | `var := DEFAULT_KNOCKBACK_DECAY` (6.0) | Fraction of the knockback's speed lost per second. |
| `separation_radius`, `separation_strength` | `var := DEFAULT_SEPARATION_RADIUS` (0.9), `var := DEFAULT_SEPARATION_STRENGTH` (3.0) | Neighbors closer than the radius on the ground plane push apart, by strength × overlap. |
| `neighbor_radius` | `var := DEFAULT_NEIGHBOR_RADIUS` (1.0) | 3D distance that counts as a neighbor. |
| `refresh_frames` | `var := DEFAULT_REFRESH_FRAMES` (3; at least 1) | `resolve` re-queries neighbors once per this many calls. |
| `rng` | `var rng: RandomNumberGenerator` | Push direction for exact overlaps and the refresh stagger; null uses the global generator. |
| `peer_of` | `var peer_of: Callable` | `(other_body) -> LFCrowdBody` or null to ignore it for blocking. Default: `LFCrowdBody.of`. `resolve` asks it about each neighbor once per refresh and keeps the answer until the next (asking again only if that crowd body was freed); peers' `weight` is read every call. `resolve_blocking` asks it every call. |
| `apply_knockback` | `apply_knockback(direction: Vector3, force: float) -> void` | Starts a knockback of speed `force` along `direction` (normalized), replacing any running one. |
| `velocity_with_knockback` | `velocity_with_knockback(delta: float) -> Vector3` | `body.velocity` plus the knockback, which decays by `delta`. |
| `is_knocked_back` | `is_knocked_back() -> bool` | Whether a knockback is still moving the body. |
| `neighbors_in` | `neighbors_in(index: LFSpatialIndex) -> Array` | Registered objects within `neighbor_radius` (the body itself too, if registered). A fresh query each call. |
| `resolve` | `resolve(index: LFSpatialIndex) -> void` | One frame of separation and blocking; neighbors, push and the neighbors' crowd bodies (`peer_of`) are refreshed every `refresh_frames` calls and reused in between. |
| `refresh_next` | `refresh_next() -> void` | The next `resolve` re-queries. |
| `resolve_separation` | `resolve_separation(neighbors: Array) -> void` | Adds `separation_from(neighbors)` to `body.velocity`. |
| `separation_from` | `separation_from(neighbors: Array) -> Vector3` | The push apart; ignores weight. Exactly overlapping bodies push in a random direction. |
| `resolve_blocking` | `resolve_blocking(neighbors: Array) -> void` | Cancels the velocity heading into any heavier neighbor; wedged between several, keeps only movement into none of them. |

### LFObstacleSidestep

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFObstacleSidestep.new(square_dot := DEFAULT_HEAD_ON_DOT, distance := DEFAULT_PROBE_DISTANCE, hold := DEFAULT_HOLD_SECONDS, remember := DEFAULT_MEMORY_SECONDS)` (0.9, 0.5, 0.4, 2.0) | Sets `head_on_dot`, `probe_distance`, `hold_seconds` and `memory_seconds`. One per body. |
| `DEFAULT_HEAD_ON_DOT` | `const DEFAULT_HEAD_ON_DOT := 0.9` | Default `head_on_dot`. |
| `DEFAULT_DEAD_CENTER_SLIDE` | `const DEFAULT_DEAD_CENTER_SLIDE := 0.05` | Default `dead_center_slide`. |
| `DEFAULT_PROBE_DISTANCE` | `const DEFAULT_PROBE_DISTANCE := 0.5` | Default `probe_distance`. |
| `DEFAULT_HOLD_SECONDS` | `const DEFAULT_HOLD_SECONDS := 0.4` | Default `hold_seconds`. |
| `DEFAULT_MEMORY_SECONDS` | `const DEFAULT_MEMORY_SECONDS := 2.0` | Default `memory_seconds`. |
| `head_on_dot` | `var := DEFAULT_HEAD_ON_DOT` (0.9) | How square a hit must be (cosine between heading and the direction into the wall). |
| `dead_center_slide` | `var := DEFAULT_DEAD_CENTER_SLIDE` (0.05) | The sideways lean below which a hit is dead centre (the side then goes toward the destination). |
| `probe_distance` | `var := DEFAULT_PROBE_DISTANCE` (0.5) | How far ahead (world units) a side is checked for another wall. |
| `hold_seconds` | `var := DEFAULT_HOLD_SECONDS` (0.4) | How long a sidestep is held, in seconds. |
| `memory_seconds` | `var := DEFAULT_MEMORY_SECONDS` (2.0) | How long the side is remembered for the same face. |
| `steer` | `steer(body: CharacterBody3D, direction: Vector3, to_destination: Vector3, delta: float) -> Vector3` | `direction`, unless the body is pressing into a wall nearly head-on: then a unit step along the wall, held for `hold_seconds`. |
| `is_sidestepping` | `is_sidestepping() -> bool` | Whether a sidestep is being held. |
| `reset` | `reset() -> void` | Ends a sidestep and forgets the side. |

## Usage

The full unit script: the one above plus a wall sidestep and a knockback. The whole crowd
shares one `LFSpatialIndex` (a grid that answers "who is near here?"), here a static
variable so every unit sees the same one:

```gdscript
extends CharacterBody3D

# One index for the whole crowd: 5-unit cells, planar (height ignored).
static var crowd_index := LFSpatialIndex.new(5.0, true)

@export var speed := 4.0
@export var weight := 1.0  # heavier units shove lighter ones aside
var goal := Vector3.ZERO
var crowd: LFCrowdBody
var sidestep := LFObstacleSidestep.new()


func _ready() -> void:
	crowd = LFCrowdBody.new(self, weight)
	crowd_index.register(self, global_position)


func _physics_process(delta: float) -> void:
	var to_goal := goal - global_position
	to_goal.y = 0.0
	# 1. Your own movement, with the sidestep turning it along walls hit head-on.
	var direction := sidestep.steer(self, to_goal.normalized(), to_goal, delta)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	# 2. Crowd physics: knockback, then push apart and weight blocking.
	velocity = crowd.velocity_with_knockback(delta)
	crowd.resolve(crowd_index)
	# 3. Move, and keep the index current.
	move_and_slide()
	crowd_index.update_position(self, global_position)


func _exit_tree() -> void:
	crowd_index.remove(self)


func hit_by_blast(from: Vector3) -> void:
	var away := global_position - from
	away.y = 0.0  # this script never resets velocity.y, so keep the knockback flat
	crowd.apply_knockback(away, 12.0)
```

To stop units snagging on each other, put them on their own physics layer and leave that
layer out of their collision mask; `LFCrowdBody` does the keeping apart.

## Notes

- `velocity_with_knockback` and `resolve` add to whatever `body.velocity` holds. Your movement code must set `body.velocity` afresh every physics frame (to zero when the unit stands still) before calling them; a unit whose code skips that assignment keeps last frame's knockback and separation push in its velocity, and each frame adds more.
- Every body in the crowd must be registered in the same `LFSpatialIndex` and kept
  current; neighbors come only from there. A planar index suits ground crowds.
- Blocking needs both sides to have a crowd body (by default, registered on the body's
  metadata by the constructor). A body without one never blocks anyone; inject `peer_of`
  to look peers up elsewhere.
- Separation and blocking work on the ground plane; vertical velocity is left alone.
- A freed neighbor still in the reused list is skipped, never touched.
- With a null `rng`, ties and the refresh stagger use Godot's global generator; pass a
  seeded one for replays.
- `steer` reads `is_on_wall()` and `get_wall_normal()` from the body's last
  `move_and_slide()`, so call it before this frame's slide. The returned direction has no
  speed; scale it yourself.
- `LFCrowdBody` holds its body as a plain reference and is stored on the body's metadata,
  so it lives as long as the body (no reference cycle). `LFObstacleSidestep` holds no body;
  `steer` takes it each call.
