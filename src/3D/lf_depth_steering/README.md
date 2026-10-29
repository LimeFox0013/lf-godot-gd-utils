# LFDepthSteering

> For a 2.5D platformer: the player steers x and jump, and this works out where in depth the character should be so each jump ends on a platform and never bumps one from below.

| | |
|---|---|
| **Kind** | [Class](../../../README.md#how-lf-classes-work): `LFDepthSteering.new()`, plain maths on numbers and data |
| **Files** | `lf_depth_steering.gd` |
| **Tests** | `tests/test_lf_depth_steering.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it in a platformer where platforms are spread in depth (z) as well as in x and height,
and the player should not have to steer depth. It only answers three questions with numbers:
where does this jump land, where should the body stand to clear the platforms overhead, and
how does the depth ease there. It moves nothing itself.

## Step by step

1. Describe each platform once as a `LFDepthSteering.Footprint`: its centre, half sizes, `bottom` and `top` heights, and the landing area on top.
2. Create the helper: `var steering := LFDepthSteering.new()`.
3. While the character is in the air, each physics frame:

```gdscript
var feet := character.global_position
var landing := steering.landing(feet, velocity_up, velocity.x, gravity_rise, gravity_fall, footprints)
var dodge := steering.dodge(feet, velocity_up, velocity.x, gravity_rise, footprints, landing.z if landing else feet.z)
var target := dodge.z if dodge else (landing.z if landing else feet.z)
var time_left := landing.time if landing else 1.0
var next := steering.step(feet.z, depth_velocity, target, delta, time_left)
character.global_position.z = next.x
depth_velocity = next.y
```

4. Set `depth_velocity = 0.0` when the character lands. Y is up and the position is the feet.

## API

| Member | Signature | Description |
|---|---|---|
| `landing` | `landing(position, velocity_up, velocity_x, gravity_rise, gravity_fall, footprints) -> Landing` | The first platform the fall reaches: the highest top at or below the jump's apex whose landing area, widened by `foot_half_x`, holds the feet's x then. `Landing` has `footprint`, `time`, `z`. Null if nothing is below. |
| `dodge` | `dodge(position, velocity_up, velocity_x, gravity_rise, footprints, prefer_z) -> Dodge` | Where to stand to clear platforms overhead: the nearest free edge on the side the body is already on (never across a platform's centre line); only from dead centre does it go toward `prefer_z`, else toward 0. `Dodge` has `z`, `time` (until the head meets the earliest blocker, 0 if already level). Null if nothing blocks, or if the body's depth is already outside every blocker's band (nothing to dodge). |
| `step` | `step(z, depth_velocity, target_z, delta, time_left) -> Vector2` | Next depth (`x`) and depth velocity (`y`): eased, keeps its velocity when the target changes, never overshoots, lands on the target once `time_left <= delta`. |
| `apex_height` | `static apex_height(height, velocity_up, gravity) -> float` | Top of the jump; the height itself when not rising or when `gravity` is not finite and positive (logged). |
| `time_to_apex` | `static time_to_apex(velocity_up, gravity) -> float` | Seconds to the top of the jump; 0 when not rising or when `gravity` is not finite and positive (logged). |
| `Footprint` | `id`, `center_x`, `half_x`, `center_z`, `half_z`, `bottom`, `top`, `land_half_x`, `land_half_z` | A platform: solid body plus landing area (surface at `top`). |
| settings | `body_radius`, `body_height`, `foot_half_x`, `clearance`, `look_ahead`, `smooth_divisor` | Defaults are the `DEFAULT_*` constants. |

## Usage

A self-contained check with one platform one unit above the feet and two units ahead in depth:

```gdscript
var platform := LFDepthSteering.Footprint.new()
platform.center_x = 0.0
platform.half_x = 2.0
platform.center_z = -3.0
platform.half_z = 1.0
platform.bottom = 0.5
platform.top = 1.0
platform.land_half_x = 2.0
platform.land_half_z = 1.0

var steering := LFDepthSteering.new()
var feet := Vector3(0.0, 1.0, -3.2)
# Rising at 6 units per second, gravity 20 up and 30 down, standing still in x.
var landing := steering.landing(feet, 6.0, 0.0, 20.0, 30.0, [platform])
print(landing.z)  # -3.0: the platform's centre in depth
var dodge := steering.dodge(feet, 6.0, 0.0, 20.0, [platform], 0.0)
print(dodge)  # null here: the platform's top is not above the feet, so it never blocks
var next := steering.step(feet.z, 0.0, landing.z, 1.0 / 60.0, landing.time)
print(next)  # (z, depth_velocity) one frame closer to -3.0
```

## Notes

- Velocities are positive upwards, as in `LFJumpPhysics`; pass its gravities for the current jump state.
- `landing` holds `velocity_x` constant to the touchdown; call it every frame so it follows the player's steering.
- A platform blocks when the body would meet it in height (head included, up to the jump's top) and in x (widened by `look_ahead`); a platform whose top is at or below the feet never blocks.
- `step` smooths over `time_left / smooth_divisor` (3.5 by default: about 1% of the distance is left at `time_left`, then it snaps), so a long depth step in a short time is fast, not late.
- A non-finite input or a non-positive gravity is reported through `LFLogger`; `landing` and `dodge` return null and `step` returns `z` and `depth_velocity` unchanged. `apex_height` and `time_to_apex` log the same way for a zero, negative or non-finite gravity and return the height unchanged and 0. An empty footprint list returns null, and null entries in a footprint list are skipped.
