# LFJumpPhysics

> Platformer jump feel as plain maths: heavier gravity when falling, a short hop on early release, and a jump that grows with built-up power.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_jump_physics.gd` |
| **Tests** | `tests/test_lf_jump_physics.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | nothing |

## When to use it

Use it in a platformer's `_physics_process` so jumps feel snappy instead of floaty: fall
faster than you rise, let a tap make a small hop and a hold make a full jump. It is only
arithmetic on the numbers you pass in, so it serves a `CharacterBody2D` or a `CharacterBody3D`
alike. Velocities here are **positive upwards**; a 2D body's `velocity.y` points down, so
pass `-velocity.y` and store the answer negated.

## Step by step

This makes a square jump with a short hop on a quick tap.

1. In the editor choose *Scene → New Scene*, click **2D Scene**; attach a script to the root `Node2D`.
2. Replace the script's text with this:

```gdscript
extends Node2D

var _physics := LFJumpPhysics.new()
var _velocity_up := 0.0
var _height := 0.0

func _ready() -> void:
	_physics.fall_multiplier = 2.0         # fall twice as heavy as rising
	_physics.low_jump_multiplier = 3.0     # letting go early cuts the jump short

func _physics_process(delta: float) -> void:
	if _height <= 0.0 and Input.is_action_just_pressed("ui_accept"):
		_velocity_up = _physics.jump_strength(500.0)
	if _height > 0.0 or _velocity_up > 0.0:
		_velocity_up = _physics.fall_velocity(_velocity_up, 980.0, delta, Input.is_action_pressed("ui_accept"))
		_height = maxf(_height + _velocity_up * delta, 0.0)
	position = Vector2(300.0, 400.0 - _height)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-20.0, -40.0, 40.0, 40.0), Color.ORANGE)
```
3. Save, press **F6** and tap Space: a small hop. Hold Space: a full jump, then a quick fall.
4. Change the multipliers and watch how the feel changes.

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_GRAVITY_SCALE`, `DEFAULT_FALL_MULTIPLIER`, `DEFAULT_LOW_JUMP_MULTIPLIER`, `DEFAULT_POWER_EXPONENT`, `DEFAULT_SPEED_BONUS` | `const …` | `1.0`, `1.0`, `1.0`, `1.5`, `0.25`: the starting values below. |
| `gravity_scale` | `var gravity_scale: float` | Multiplies the gravity you pass in. |
| `fall_multiplier` | `var fall_multiplier: float` | Extra gravity while falling (velocity below 0). |
| `low_jump_multiplier` | `var low_jump_multiplier: float` | Extra gravity while rising with the button released. |
| `power_exponent` | `var power_exponent: float` | `jump_strength` raises the power ratio to this. |
| `speed_bonus` | `var speed_bonus: float` | The share of the base strength a full `speed_ratio` adds. |
| `fall_velocity` | `fall_velocity(velocity_up: float, gravity: float, delta: float, jump_held: bool) -> float` | The velocity after `delta` seconds of gravity. Falling: `fall_multiplier`. Rising and released: `low_jump_multiplier`. Rising and held, or still: only `gravity_scale`. |
| `jump_strength` | `jump_strength(base_strength: float, power_ratio := 1.0, speed_ratio := 0.0) -> float` | `base * power_ratio ^ power_exponent + speed_ratio * speed_bonus * base`; a negative ratio counts as 0. |

## Usage

A 3D character whose built-up speed boost makes the next jump higher:

```gdscript
var _jump := LFJumpPhysics.new()
var _boost := 25.0           # grows with perfectly timed jumps
const BASE_BOOST := 25.0
var top_speed := 8.0

func _physics_process(delta: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	if !is_on_floor():
		velocity.y = _jump.fall_velocity(velocity.y, gravity, delta, Input.is_action_pressed("jump"))
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = _jump.jump_strength(10.0, _boost / BASE_BOOST, absf(velocity.x) / top_speed)
	move_and_slide()
```

## Notes

- It does not detect the floor or read input; you decide when gravity applies and what "held" means.
- Both multipliers act only while moving: exactly at the top of a jump (velocity 0) the pull is plain `gravity_scale`.
- For 2D, whose y axis points down: `velocity.y = -_jump.fall_velocity(-velocity.y, gravity, delta, held)`.
