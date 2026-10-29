## Platformer jump feel: heavier gravity on the way down, a short hop when the button is
## released early, and a jump that grows with built-up power.
##
## It is only maths on numbers you pass in, so it works with a CharacterBody2D or 3D alike. Velocities
## here are **positive upwards** (a CharacterBody2D's `velocity.y` points down, so pass
## `-velocity.y` and store the result back negated). Typical use, every physics frame while
## airborne: `velocity_up = jump_physics.fall_velocity(velocity_up, gravity, delta, jump_held)`;
## on the jump: `velocity_up = jump_physics.jump_strength(base, power_ratio, speed_ratio)`.
class_name LFJumpPhysics
extends RefCounted

## What multiplies the gravity you pass in, when none is given.
const DEFAULT_GRAVITY_SCALE := 1.0
## Extra gravity while falling, when none is given: 1 is no change.
const DEFAULT_FALL_MULTIPLIER := 1.0
## Extra gravity while rising with the jump button released, when none is given: 1 is no change.
const DEFAULT_LOW_JUMP_MULTIPLIER := 1.0
## The power of the built-up-power ratio in `jump_strength`, when none is given.
const DEFAULT_POWER_EXPONENT := 1.5
## How much of the base strength a full `speed_ratio` of 1 adds, when none is given.
const DEFAULT_SPEED_BONUS := 0.25

## Multiplies the gravity passed to `fall_velocity`.
var gravity_scale := DEFAULT_GRAVITY_SCALE
## Gravity is multiplied by this while falling (velocity below zero).
var fall_multiplier := DEFAULT_FALL_MULTIPLIER
## Gravity is multiplied by this while rising with the jump button released (a short hop).
var low_jump_multiplier := DEFAULT_LOW_JUMP_MULTIPLIER
## `jump_strength` raises the power ratio to this: above 1 makes power count for more than its share.
var power_exponent := DEFAULT_POWER_EXPONENT
## `jump_strength` adds `speed_ratio * speed_bonus * base_strength`.
var speed_bonus := DEFAULT_SPEED_BONUS


## The upward velocity after `delta` seconds of gravity. `gravity` is the engine's positive
## downward pull (for example the project setting); `jump_held` is whether the jump button is
## still down. Falling uses `fall_multiplier`; rising with the button released uses
## `low_jump_multiplier`; rising with it held uses plain `gravity_scale`.
func fall_velocity(velocity_up: float, gravity: float, delta: float, jump_held: bool) -> float:
	var pull := gravity * gravity_scale
	if velocity_up < 0.0:
		pull *= fall_multiplier
	elif velocity_up > 0.0 and !jump_held:
		pull *= low_jump_multiplier
	return velocity_up - pull * delta


## The upward velocity a jump starts with: `base_strength * power_ratio ^ power_exponent`, plus
## `speed_ratio * speed_bonus * base_strength` for running speed. `power_ratio` is how much stronger
## than normal the character is (1 is normal; a ratio of 0 or less counts as 0); `speed_ratio` is
## horizontal speed over top speed (0 to 1).
func jump_strength(base_strength: float, power_ratio := 1.0, speed_ratio := 0.0) -> float:
	return base_strength * pow(maxf(power_ratio, 0.0), power_exponent) + speed_ratio * speed_bonus * base_strength
