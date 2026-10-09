# LFShaker, LFShaker.Profile

> Screen shake for a 3D camera (or any 3D node): hits and explosions that add up, fade out smoothly and, with `auto_reset_on_idle` on (the default), settle back exactly where they started.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_shaker.gd` |
| **Tests** | `tests/test_lf_shaker.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it to shake the camera when something hits hard: an explosion near the player, a boss
landing, a heavy weapon firing. Call `shake(0.3)` on each hit; shakes stack (two quick hits
shake harder than one), fade out smoothly at any frame rate, shake rotation as well as
position, and (with `auto_reset_on_idle`, the default) put the camera back exactly at rest. A tween or animation track on
`position` can't stack two hits and drifts when two overlap. It works on any `Node3D`, not
only cameras (a rattling crate, a trembling bridge); for 2D games use a `Camera2D` offset
instead.

## Step by step

This makes a camera that shakes when you press Space. The shaker is a node that sits
between a parent and the camera and jiggles the camera for you.

1. *Scene → New Scene*, click **3D Scene** under "Create Root Node" and rename the root
   `World`.
2. Select `World`, click **+ Add Child Node**, type `LFShaker` in the search box and
   press *Create*. In the Inspector (the property panel on the right) open *Transform* and
   set *Position* to `0, 1.5, 5`.
3. Select the `LFShaker` node and **+ Add Child Node** again: a `Camera3D`. Leave its position at
   `0, 0, 0` (it is positioned by its parent). The Scene dock should read
   `World → LFShaker → Camera3D`. A camera looks along -Z, so it looks at the world's centre.
4. Something to look at: add to `World` a `DirectionalLight3D` (set *Rotation* to
   `-50, 30, 0`) and a `MeshInstance3D`. In the Inspector click its empty *Mesh* slot and
   choose **New BoxMesh**.
5. Select `World`, click **Attach Script** (above the Scene dock), *Create*, and replace
   the contents with:

   ```gdscript
   extends Node3D

   # The LFShaker node from step 2, found by its name.
   @onready var shaker: LFShaker = $LFShaker


   func _unhandled_input(event: InputEvent) -> void:
   	# Space (or Enter) is the built-in "ui_accept" action.
   	if event.is_action_pressed("ui_accept"):
   		# 0.5 means a medium bump, from 0 (nothing) to 1 (strongest).
   		shaker.shake(0.5)
   ```
6. Press **F6** (*Run Current Scene*) and save when asked. Press Space: the box jolts
   and wobbles, then the picture settles back to exactly where it was. Press Space twice
   quickly: the second shake is stronger because shakes add up.
7. The default shake is subtle. Select the `LFShaker` node and, in the Inspector, raise
   *Translation Strength* (how far it can move, in world units, on each axis) to
   `0.3, 0.3, 0.3` and *Rotation Strength Deg* (how far it can turn, in degrees) to
   `4, 4, 4`. *Trauma Decay Rate* is how fast it calms down: lower lasts longer.

## API

Everything the class offers; you only need `shake` to get started. ("Trauma" is the shake level, 0 to 1: each hit adds to it and it fades by itself.)

### Exports

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_TRAUMA_DECAY_RATE` | `const := 2.5` | Default `trauma_decay_rate` (and a `Profile`'s). |
| `DEFAULT_TRAUMA_EXPONENT` | `const := 2.0` | Default `trauma_exponent` (and a `Profile`'s). |
| `DEFAULT_TRANSLATION_STRENGTH` | `const := Vector3(0.1, 0.1, 0.1)` | Default `translation_strength`. |
| `DEFAULT_TRANSLATION_FREQUENCY` | `const := 8.0` | Default `translation_frequency` (and a `Profile`'s), Hz. |
| `DEFAULT_ROTATION_STRENGTH_DEG` | `const := Vector3(2.0, 2.0, 2.0)` | Default `rotation_strength_deg`. |
| `DEFAULT_ROTATION_FREQUENCY` | `const := 10.0` | Default `rotation_frequency` (and a `Profile`'s), Hz. |
| `DEFAULT_SEED` | `const := 12345` | Default `seed_value`. |
| `DEFAULT_NOISE_ROUGHNESS` | `const := 0.5` | Default `noise_roughness` (and a `Profile`'s). |
| `DEFAULT_IDLE_TRAUMA_THRESHOLD` | `const := 0.001` | Default `idle_trauma_threshold`. |
| `DEFAULT_MAGNITUDE` | `const := 0.5` | Default `magnitude` of `shake` and of a `Profile`. |
| `DEFAULT_DURATION` | `const := 0.2` | Default `duration` of `shake` and of a `Profile`, seconds. |
| `enabled` | `bool = true` | Master switch. Setting it false stops a running shake and returns the node to rest; a disabled shaker ignores `shake`/`add_trauma`/`set_trauma`. |
| `use_trauma_model` | `bool = true` | True: trauma decays by `trauma_decay_rate`/s. False: fixed-duration shakes. |
| `trauma_decay_rate` | `float = DEFAULT_TRAUMA_DECAY_RATE` (2.5; 0.1–10) | Trauma lost per second (trauma model). |
| `trauma_exponent` | `float = DEFAULT_TRAUMA_EXPONENT` (2.0; 0.5–4) | Intensity = `pow(trauma_value, trauma_exponent)`. |
| `enable_translation` | `bool = true` | Apply positional offset. |
| `translation_strength` | `Vector3 = DEFAULT_TRANSLATION_STRENGTH` ((0.1, 0.1, 0.1)) | Offset scale per axis at intensity 1: the most the offset can reach (the noise stays within ±1, mostly well inside). |
| `translation_frequency` | `float = DEFAULT_TRANSLATION_FREQUENCY` (8.0; 0.1–30) | Translation noise speed in Hz. |
| `enable_rotation` | `bool = true` | Apply rotational offset. |
| `rotation_strength_deg` | `Vector3 = DEFAULT_ROTATION_STRENGTH_DEG` ((2, 2, 2)) | Rotation scale per axis in degrees at intensity 1, about the node's own axes (x pitch, y yaw, z roll): the most the rotation can reach. |
| `rotation_frequency` | `float = DEFAULT_ROTATION_FREQUENCY` (10.0; 0.1–30) | Rotation noise speed in Hz. |
| `seed_value` | `int = DEFAULT_SEED` (12345) | `FastNoiseLite` seed; setting it rebuilds the noise. |
| `noise_roughness` | `float = DEFAULT_NOISE_ROUGHNESS` (0.5; 0–1) | Noise texture: 1 to 3 octaves and a rising gain. Never changes the speed. Setting it rebuilds the noise. |
| `auto_reset_on_idle` | `bool = true` | Restore `original_transform` once, when a shake ends. |
| `idle_trauma_threshold` | `float = DEFAULT_IDLE_TRAUMA_THRESHOLD` (0.001) | Intensity below this counts as idle (trauma is then zeroed). |

### Properties

| Member | Signature | Description |
|---|---|---|
| `noise_gen` | `FastNoiseLite` | Built on first use, rebuilt by `setup_noise()` and by setting `seed_value`/`noise_roughness`. |
| `time_counter` | `float` | Accumulated enabled time used to sample the noise. |
| `trauma_value` | `float` | Current trauma, 0..1. |
| `time_left` | `float` | Fixed-duration model: remaining time of the longest running shake. |
| `original_transform` | `Transform3D` | Rest transform: captured when a shake starts on an idle shaker, or by `recapture_original_transform()`. Every shaken frame is this plus the frame's offset. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `add_trauma` | `add_trauma(amount: float) -> void` | Adds to trauma, clamped to 0..1 (negative calms it; NaN is ignored). Trauma model only: the fixed-duration model clears it on the next frame. |
| `add_trauma_at` | `add_trauma_at(world_pos: Vector3, focus_pos: Vector3, trauma: float, radius: float, planar := true) -> void` | Adds `trauma` scaled by nearness: in full at `focus_pos`, falling linearly to nothing at `radius`. `planar` measures on the XZ plane (height ignored). Ignored for `radius <= 0`. |
| `set_trauma` | `set_trauma(value: float) -> void` | Sets trauma, clamped to 0..1 (NaN is ignored). Trauma model only, as `add_trauma`. |
| `shake` | `shake(magnitude: float = DEFAULT_MAGNITUDE, duration: float = DEFAULT_DURATION) -> void` (0.5, 0.2) | `magnitude` is clamped to 0..1. Trauma model: `add_trauma(magnitude)` (`duration` ignored). Fixed-duration model: starts a shake of `magnitude` for `duration` s alongside any running ones; a zero (or NaN) magnitude or duration does nothing. |
| `apply_shake_profile` | `apply_shake_profile(shake_profile: Profile) -> void` | Adopts the profile's decay, exponent, frequencies and roughness (rebuilding the noise), then calls `shake(profile.magnitude, profile.duration)`. |
| `stop_shake` | `stop_shake(reset_transform: bool = true) -> void` | Ends every shake; with `reset_transform`, restores `original_transform` if a shake offset is applied. |
| `recapture_original_transform` | `recapture_original_transform() -> void` | Stores the current `transform` as the rest transform; use it to re-base a running shake. |
| `setup_noise` | `setup_noise() -> void` | (Re)builds `noise_gen` from `seed_value` and `noise_roughness` (noise frequency 1, so the `*_frequency` exports are Hz). |
| `compute_translation` | `compute_translation(intensity: float) -> Vector3` | Noise-driven translation offset at `time_counter`. |
| `compute_rotation` | `compute_rotation(intensity: float) -> Vector3` | Noise-driven Euler rotation offset (radians) at `time_counter`. |

### LFShaker.Profile

`LFShaker.Profile.new(shake_magnitude := DEFAULT_MAGNITUDE, shake_duration := DEFAULT_DURATION, decay_rate := DEFAULT_TRAUMA_DECAY_RATE, exponent := DEFAULT_TRAUMA_EXPONENT, translation_hz := DEFAULT_TRANSLATION_FREQUENCY, rotation_hz := DEFAULT_ROTATION_FREQUENCY, roughness := DEFAULT_NOISE_ROUGHNESS)` (0.5, 0.2, 2.5, 2.0, 8.0, 10.0, 0.5). The arguments fill these public fields, in order; the defaults equal the node's export defaults.

| Field | Type | Description |
|---|---|---|
| `magnitude` | `float` | Strength passed to `shake`, 0..1. |
| `duration` | `float` | Seconds (fixed-duration model only). |
| `trauma_decay_rate` | `float` | Copied to the shaker's `trauma_decay_rate`. |
| `trauma_exponent` | `float` | Copied to the shaker's `trauma_exponent`. |
| `translation_frequency` | `float` | Copied to the shaker's `translation_frequency` (Hz). |
| `rotation_frequency` | `float` | Copied to the shaker's `rotation_frequency` (Hz). |
| `noise_roughness` | `float` | Copied to the shaker's `noise_roughness` (0..1). |

## Usage

A more advanced setup: shakes that depend on distance, and a reusable preset (a `Profile`: a bundle of shake settings). Scene: put the shaker between a rig (a parent node the camera hangs from) and the camera:

```
World (Node3D)          <- this script
└── CameraRig (Node3D)
    └── LFShaker        <- add a Node3D and attach lf_shaker.gd, or add "LFShaker" directly
        └── Camera3D
```

```gdscript
extends Node3D

@onready var shaker: LFShaker = $CameraRig/LFShaker

# A reusable "big explosion": strong, fading slower than the default.
var big_boom := LFShaker.Profile.new(0.8, 0.4, 1.5)


func on_player_hit() -> void:
	shaker.shake(0.3)  # a light bump; repeated hits add up


func on_explosion(at: Vector3) -> void:
	# Full trauma where the camera looks, none 20 units away or farther.
	shaker.add_trauma_at(at, $CameraRig.global_position, 0.6, 20.0)


func on_boss_landed() -> void:
	shaker.apply_shake_profile(big_boom)  # note: its settings stay for later shakes


func on_cutscene_started() -> void:
	shaker.stop_shake()  # snap back to rest now
```

## Notes

- Two models. **Trauma** (`use_trauma_model = true`): `shake()` adds trauma, which decays at `trauma_decay_rate`/s. **Fixed duration** (`false`): each `shake(m, d)` runs for its own `d` seconds; the strongest running shake sets the trauma, so a weaker or shorter shake never weakens or cuts short a stronger, longer one. A timed shake ends at full strength, without a fade.
- The offset at a given elapsed time is the same at any frame rate (up to float rounding). A speed in Hz is roughly swings per second, so the default speeds (8 Hz / 10 Hz) get 6 to 7.5 frames per swing at 60 fps; above about 15 Hz a swing gets 4 frames or fewer at 60 fps and reads as jitter, while 144 fps still draws about 10.
- Offsets are always re-based on `original_transform`; they never accumulate frame to frame.
- The rest transform is captured when a shake starts on an idle shaker, so you may move the node between shakes. Moves made *during* a shake are overwritten every frame; call `recapture_original_transform()` after such a move.
- The idle reset happens once, on the frame a shake ends. An idle shaker never writes `transform`. With `auto_reset_on_idle = false` the last shaken frame stays, and the next shake starts from there.
- Rotation is about the shaker's own axes: a roll-only shake (`rotation_strength_deg = (0, 0, r)`) on a pitched shaker whose camera child has no rotation of its own only rolls; it never changes where that camera looks. A camera turned inside the shaker (such as the one in `LFOrbitCamera`'s README) is rotated about the shaker's axes, not its own, so its view direction does move a little.
- Put the shaker between a rig and the camera so the shaken `transform` is local.
- `apply_shake_profile` changes the shaker's settings for every later shake, not just this one.
- Shakers with the same `seed_value` sample the same noise: two with the same settings whose enabled clocks (`time_counter`) match move identically. Give each its own seed if two are on screen.
- Runs once per drawn frame (`_process`), not once per physics step. A paused tree freezes the shake at its current offset, and `Engine.time_scale` slows it.
