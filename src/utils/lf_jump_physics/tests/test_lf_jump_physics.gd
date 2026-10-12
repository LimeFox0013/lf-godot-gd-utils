extends GutTest

## Gravity and frame used by the fall tests.
const GRAVITY := 10.0
const DELTA := 0.1

var _physics: LFJumpPhysics


func before_each():
	_physics = LFJumpPhysics.new()


func test_defaults_are_plain_gravity():
	assert_almost_eq(_physics.fall_velocity(5.0, GRAVITY, DELTA, true), 4.0, 0.0001)
	assert_almost_eq(_physics.fall_velocity(-5.0, GRAVITY, DELTA, false), -6.0, 0.0001)


func test_the_scale_multiplies_gravity():
	_physics.gravity_scale = 3.0
	assert_almost_eq(_physics.fall_velocity(0.0, GRAVITY, DELTA, true), -3.0, 0.0001)


func test_falling_uses_the_fall_multiplier():
	_physics.fall_multiplier = 2.0
	assert_almost_eq(_physics.fall_velocity(-1.0, GRAVITY, DELTA, true), -3.0, 0.0001)
	assert_almost_eq(_physics.fall_velocity(-1.0, GRAVITY, DELTA, false), -3.0, 0.0001, "holding makes no difference while falling")


func test_rising_with_the_button_released_uses_the_low_jump_multiplier():
	_physics.low_jump_multiplier = 3.0
	assert_almost_eq(_physics.fall_velocity(5.0, GRAVITY, DELTA, false), 2.0, 0.0001)
	assert_almost_eq(_physics.fall_velocity(5.0, GRAVITY, DELTA, true), 4.0, 0.0001, "held: plain gravity")


func test_at_rest_vertically_only_plain_gravity_applies():
	_physics.fall_multiplier = 5.0
	_physics.low_jump_multiplier = 5.0
	assert_almost_eq(_physics.fall_velocity(0.0, GRAVITY, DELTA, false), -1.0, 0.0001)


func test_an_early_release_makes_a_lower_jump():
	_physics.low_jump_multiplier = 3.0
	var held := _simulate(true)
	var released := _simulate(false)
	assert_gt(held, released * 1.5)


func test_jump_strength_with_nothing_extra_is_the_base():
	assert_eq(_physics.jump_strength(10.0), 10.0)


func test_jump_strength_grows_with_power_to_the_exponent():
	assert_almost_eq(_physics.jump_strength(10.0, 4.0), 80.0, 0.0001)
	_physics.power_exponent = 2.0
	assert_almost_eq(_physics.jump_strength(10.0, 3.0), 90.0, 0.0001)


func test_jump_strength_adds_a_running_speed_bonus():
	assert_almost_eq(_physics.jump_strength(10.0, 1.0, 1.0), 12.5, 0.0001)
	_physics.speed_bonus = 0.5
	assert_almost_eq(_physics.jump_strength(10.0, 1.0, 0.5), 12.5, 0.0001)


func test_a_negative_power_ratio_counts_as_zero():
	assert_eq(_physics.jump_strength(10.0, -2.0), 0.0)


## The height reached by a jump of 10 with the button held or released straight away.
func _simulate(held: bool) -> float:
	var velocity := 10.0
	var height := 0.0
	while velocity > 0.0:
		height += velocity * DELTA
		velocity = _physics.fall_velocity(velocity, GRAVITY, DELTA, held)
	return height
