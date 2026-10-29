# LFProjectile3D

> A shot that flies in a straight line to a fixed point, ends on the first area it touches (or on arriving), and goes back to its pool.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): an `Area3D` you extend or add to a scene |
| **Files** | `lf_projectile_3d.gd` |
| **Tests** | `tests/test_lf_projectile_3d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFFactory` (optional, for pooling) |

## When to use it

Use it for arrows, bolts and bullets that travel to where the target was when you fired,
so a target that moves away is missed. You decide which areas count as a hit and what a hit
does; the class only flies, finishes and returns to its pool.

## Step by step

1. Make a scene with an **Area3D** root and a **CollisionShape3D** child (a small capsule). Set the root's **Collision Layer** and **Mask** to what the shot should touch.
2. Attach a script to the root:

```gdscript
extends LFProjectile3D

func _landed_on(area: Area3D) -> void:
	print("hit ", area.name)
	super(area)
```

3. From another script, add an instance and call `launch_to(Vector3.ZERO, Vector3(0, 0, -10), 12.0)`. It flies 10 units away at 12 units per second, prints the name of the first area it touches, and frees itself.

## API

| Member | Signature | Description |
|---|---|---|
| `launch_to` | `launch_to(origin: Vector3, aim_point: Vector3, speed: float) -> void` | Starts the flight. Switching `monitoring` and `monitorable` on is deferred. |
| `reset` | `reset() -> void` | Back to idle: hidden, not flying, detecting nothing (deferred). Call it when the shot returns to a pool; override and call `super()` to clear your own state. |
| `is_flying` | `is_flying() -> bool` | Launched and not yet finished. |
| `pool` | `var pool: LFFactory` | Where it goes when done; without one it frees itself. |
| `_accepts_area` | `_accepts_area(area: Area3D) -> bool` | Override: whether an entered area is a hit. Others are flown through. |
| `_landed_on` | `_landed_on(area: Area3D) -> void` | Override: called once with the first accepted area. The base calls `_finish()`. |
| `_finish` | `_finish() -> void` | Ends the flight: released to `pool`, else `queue_free()`. |

## Usage

```gdscript
class_name Arrow
extends LFProjectile3D

var damage := 5.0

func _accepts_area(area: Area3D) -> bool:
	return area.get_parent() is Enemy

func _landed_on(area: Area3D) -> void:
	var enemy: Enemy = area.get_parent()
	var dealt := damage
	super(area)
	enemy.take_damage(dealt)
```

## Notes

- Read your own fields before calling `super()` in `_landed_on`: for a pooled shot, `_finish()` triggers its reset hook, which may clear them.
- The `reset` is not called by the class itself: register it as the pool's release hook (`LFFactory.register(key, create, Callable(), func(shot): shot.reset())`).
- The flight is a straight line (no gravity); walls do not stop it, only an accepted area does.
- A `speed` of zero or less never reaches the aim point, so the shot ends only on an accepted area.
- `reset` and `launch_to` change `monitoring` and `monitorable` with `set_deferred`, in that order, so a shot reset inside a hit and launched again in the same frame ends up enabled.
