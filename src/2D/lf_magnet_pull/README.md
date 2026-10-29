# LFMagnetPull2D

> The velocity of a body pulled toward nearby attractors, each with its own power: the pull is `sum(direction * power) - velocity`, so the body glides in and settles instead of accelerating forever.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_magnet_pull_2d.gd`, `lf_magnet_pull_core.gd` (`LFMagnetPullCore`: the math shared with `LFMagnetPull3D`) |
| **Tests** | `tests/test_lf_magnet_pull.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

**Classes:**

| Class | How you use it |
|---|---|
| `LFMagnetPull2D` | Object: one per pulled body |
| `LFMagnetPullCore` | Part of `LFMagnetPull2D` and `LFMagnetPull3D`, created for you |

## When to use it

Use it for loot or pickups that drift toward the players who stand near them, orbs drawn
into a vacuum, or anything that should be sucked toward one or several points, where each
point can pull with a different strength (a player with a better magnet pulls harder).
It computes a velocity; you move the body with it. Which attractors count as "in range" is
yours (usually an `Area2D`'s `body_entered` / `body_exited`). For 3D bodies use `LFMagnetPull3D`
(`src/3D/lf_magnet_pull_3d`).

## Step by step

Goal: a coin that slides toward the player when it gets close.

1. Make a scene with a `CharacterBody2D` root named `Coin` (give it a `CollisionShape2D`).
2. Attach a script to `Coin`:

   ```gdscript
   extends CharacterBody2D

   var pull := LFMagnetPull2D.new()

   func attract_to(player: Node2D) -> void:     # call from your pickup-range Area2D
   	pull.set_attractor(player, 300.0)          # 300 = pixels per second it settles at

   func release(player: Node2D) -> void:
   	pull.remove_attractor(player)

   func _physics_process(delta: float) -> void:   # delta = seconds since the last frame
   	velocity = pull.step(global_position, delta)
   	move_and_slide()
   ```
3. Put a `Coin` and a `Node2D` named `Player` in a level, call `attract_to($Player)` from `_ready` of the level, and press *F6*.

You should see the coin speed up toward the player and glide in at about 300 pixels per second.

## API

| Member | Signature | Description |
|---|---|---|
| `set_attractor` | `set_attractor(attractor: Node2D, power: float, on := true) -> void` | Adds the attractor or changes its power; `on = false` removes it. A NaN power is rejected through `LFLogger`. |
| `remove_attractor` | `remove_attractor(attractor: Variant) -> void` | Removes it; harmless if absent or already freed. |
| `has_attractor` | `has_attractor(attractor: Variant) -> bool` | Whether it is added; false for a freed one. |
| `attractor_count` | `attractor_count() -> int` | Added attractors that are alive and in the scene tree. |
| `clear` | `clear() -> void` | Removes every attractor and zeroes the velocity. |
| `velocity` | `Vector2` (read-only) | The current pulled velocity. |
| `force_at` | `force_at(position: Vector2) -> Vector2` | `sum(direction * power) - velocity` at the global `position`; changes nothing. |
| `step` | `step(position: Vector2, delta: float) -> Vector2` | Adds `force_at(position) * delta` to the velocity and returns it; zero when no live attractor is left. |

`LFMagnetPull3D` has the same members with `Node3D` and `Vector3` (see
`src/3D/lf_magnet_pull_3d`). `LFMagnetPullCore` is the same logic on untyped vectors
(`LFMagnetPullCore.new(zero)`); use the 2D or 3D class instead.

## Usage

Two players with different magnets; the stronger one wins the tug of war:

```gdscript
pull.set_attractor(player_a, 200.0)
pull.set_attractor(player_b, 400.0)
velocity = pull.step(global_position, delta)
```

## Notes

- For one attractor the velocity settles at its `power` (units per second): the `- velocity` term is drag. Several attractors settle where the summed pulls balance the drag, so equal and opposite ones cancel.
- With no live attractor `step` sets the velocity to zero at once: the body stops, it does not coast.
- An attractor exactly at the body's position has no direction and adds nothing.
- Freed attractors and ones outside the scene tree are skipped (and forgotten); attractors are held by weak reference, so the pull never keeps them alive.
- The pull has no range: add and remove attractors as they come and go. Positions are global.
- `delta` scales the step, so results differ slightly between frame rates, as with any Euler integration.
- `remove_attractor` and `has_attractor` take a `Variant`, so a freed attractor does not raise a type error: `has_attractor` returns false, and `remove_attractor` cannot tell which entry it was, so it drops every freed or out-of-tree attractor from the list.
