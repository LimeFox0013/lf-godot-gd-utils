# LFMagnetPull3D

> The velocity of a 3D body pulled toward nearby attractors, each with its own power: the pull is `sum(direction * power) - velocity`. The 3D counterpart of `LFMagnetPull2D`.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_magnet_pull_3d.gd` |
| **Tests** | `tests/test_lf_magnet_pull_3d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFMagnetPullCore` (`src/2D/lf_magnet_pull/lf_magnet_pull_core.gd`, the math shared with `LFMagnetPull2D`), which uses `LFLogger` |

## When to use it

Use it for 3D pickups drawn toward the players or magnets near them, where each attractor
pulls with its own power. It computes a velocity; you move the body with it. You decide
who is in range (usually an `Area3D`'s `body_entered` / `body_exited`). For 2D use
`LFMagnetPull2D`.

## Step by step

1. Make a scene with a `CharacterBody3D` root named `Orb` (give it a `CollisionShape3D`).
2. Attach a script to `Orb`:

   ```gdscript
   extends CharacterBody3D

   var pull := LFMagnetPull3D.new()

   func attract_to(player: Node3D) -> void:
   	pull.set_attractor(player, 5.0)    # 5 = meters per second it settles at

   func _physics_process(delta: float) -> void:   # delta = seconds since the last frame
   	velocity = pull.step(global_position, delta)
   	move_and_slide()
   ```
3. Put an `Orb` and a `Node3D` named `Player` in a level, call `attract_to($Player)` from the level's `_ready`, and press *F6*.

You should see the orb glide toward the player at about 5 meters per second.

## API

| Member | Signature | Description |
|---|---|---|
| `set_attractor` | `set_attractor(attractor: Node3D, power: float, on := true) -> void` | Adds the attractor or changes its power; `on = false` removes it. A NaN power is rejected through `LFLogger`. |
| `remove_attractor` | `remove_attractor(attractor: Variant) -> void` | Removes it; harmless if absent or already freed. |
| `has_attractor` | `has_attractor(attractor: Variant) -> bool` | Whether it is added; false for a freed one. |
| `attractor_count` | `attractor_count() -> int` | Added attractors that are alive and in the scene tree. |
| `clear` | `clear() -> void` | Removes every attractor and zeroes the velocity. |
| `velocity` | `Vector3` (read-only) | The current pulled velocity. |
| `force_at` | `force_at(position: Vector3) -> Vector3` | `sum(direction * power) - velocity` at the global `position`; changes nothing. |
| `step` | `step(position: Vector3, delta: float) -> Vector3` | Adds `force_at(position) * delta` to the velocity and returns it; zero when no live attractor is left. |

## Usage

```gdscript
pull.set_attractor(player_a, 4.0)
pull.set_attractor(magnet, 8.0)
velocity = pull.step(global_position, delta)
```

## Notes

The behavior, including settling speed, stopping with no attractors, freed attractors and
the lack of a range, is the same as `LFMagnetPull2D`; see its
[Notes](../../2D/lf_magnet_pull/README.md#notes).
