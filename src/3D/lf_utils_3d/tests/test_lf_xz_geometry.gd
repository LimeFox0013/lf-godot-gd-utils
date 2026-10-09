extends GutTest


func test_a_point_on_the_circle_sits_at_the_radius_and_angle():
	var center := Vector3(1, 5, -2)

	assert_true(LFUtils3D.point_on_circle_xz(center, 3.0, 0.0).is_equal_approx(Vector3(4, 5, -2)))
	assert_true(LFUtils3D.point_on_circle_xz(center, 3.0, PI / 2.0).is_equal_approx(Vector3(1, 5, 1)))


func test_a_random_direction_is_a_flat_unit_vector():
	for i in 200:
		var direction := LFUtils3D.random_direction_xz()
		assert_almost_eq(direction.length(), 1.0, 0.0001)
		assert_eq(direction.y, 0.0)


func test_away_points_from_the_origin_and_is_a_unit_direction_when_they_coincide():
	assert_true(LFUtils3D.away_xz(Vector3(5, 9, 0), Vector3(1, 0, 0)).is_equal_approx(Vector3(1, 0, 0)), 'height is ignored')

	var tie := LFUtils3D.away_xz(Vector3(2, 0, 2), Vector3(2, 1, 2))
	assert_almost_eq(tie.length(), 1.0, 0.0001, 'never a zero vector')


## A seeded game passes its own generator, so a tie rolls the same way on a replay.
func test_a_tie_rolls_from_a_given_generator():
	var first := RandomNumberGenerator.new()
	first.seed = 7
	var second := RandomNumberGenerator.new()
	second.seed = 7

	var a := LFUtils3D.away_xz(Vector3.ZERO, Vector3.ZERO, LFUtils3D.DEFAULT_EPSILON, first)
	var b := LFUtils3D.away_xz(Vector3.ZERO, Vector3.ZERO, LFUtils3D.DEFAULT_EPSILON, second)

	assert_eq(a, b)
	assert_eq(LFUtils3D.random_direction_xz(first), LFUtils3D.random_direction_xz(second))


func test_a_random_point_in_a_disk_rolls_from_a_given_generator():
	var first := RandomNumberGenerator.new()
	first.seed = 11
	var second := RandomNumberGenerator.new()
	second.seed = 11
	var center := Vector3(2, 3, 4)

	var a := LFUtils3D.random_point_in_circle_xz(center, 5.0, first)
	seed(999) # the global generator must not matter
	randf()
	var b := LFUtils3D.random_point_in_circle_xz(center, 5.0, second)

	assert_eq(a, b, "a seeded generator makes the point reproducible")
	assert_eq(a.y, 3.0, "the point keeps the center's height")
	assert_true(Vector2(a.x - 2, a.z - 4).length() <= 5.0, "the point lies within the radius")


func test_seeded_xz_rolls_match_the_plain_formula():
	var rng := LFRandom.new(42)
	var twin := LFRandom.new(42)
	var angle := twin.randf_range(0.0, TAU)
	assert_eq(LFUtils3D.random_direction_xz(rng), Vector3(cos(angle), 0.0, sin(angle)))
	angle = twin.randf_range(0.0, TAU)
	var distance := sqrt(twin.randf()) * 3.0
	assert_eq(LFUtils3D.random_point_in_circle_xz(Vector3.ONE, 3.0, rng), Vector3.ONE + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))


func test_random_points_are_uniform_by_area():
	var rng := LFRandom.new(8)
	var inner := 0
	for i in 4000:
		if LFUtils3D.random_point_in_circle_xz(Vector3.ZERO, 2.0, rng).length() < 1.0:
			inner += 1
	assert_almost_eq(inner / 4000.0, 0.25, 0.03, 'the inner half-radius disk holds a quarter of the area')


func test_nearest_distance_is_the_smallest_distance_and_inf_when_empty():
	var points: Array[Vector3] = [Vector3(10, 0, 0), Vector3(0, 0, 3), Vector3(0, 4, 0)]
	assert_almost_eq(LFUtils3D.nearest_distance(Vector3.ZERO, points), 3.0, 0.0001)
	var none: Array[Vector3] = []
	assert_eq(LFUtils3D.nearest_distance(Vector3.ZERO, none), INF)


func test_farthest_sample_xz_picks_the_accepted_sample_farthest_from_the_points():
	var away: Array[Vector3] = [Vector3(-10, 0, -10)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var replay := RandomNumberGenerator.new()
	replay.seed = 7
	var expected := Vector3.ZERO
	for i in 200:
		var sample := Vector3(replay.randf_range(-10.0, 10.0), 0.0, replay.randf_range(-10.0, 10.0))
		if sample.distance_to(away[0]) > expected.distance_to(away[0]):
			expected = sample

	var best: Vector3 = LFUtils3D.farthest_sample_xz(10.0, 200, away, Callable(), rng)

	assert_eq(best, expected, 'the farthest of the 200 samples')
	assert_gt(best.distance_to(away[0]), 20.0, 'near the opposite corner')


func test_farthest_sample_xz_is_deterministic_for_a_seeded_rng():
	var away: Array[Vector3] = [Vector3.ZERO]
	var first := RandomNumberGenerator.new()
	first.seed = 42
	var second := RandomNumberGenerator.new()
	second.seed = 42
	assert_eq(LFUtils3D.farthest_sample_xz(5.0, 20, away, Callable(), first),
		LFUtils3D.farthest_sample_xz(5.0, 20, away, Callable(), second))


func test_farthest_sample_xz_honours_accept_and_is_null_when_all_are_rejected():
	var away: Array[Vector3] = [Vector3.ZERO]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var only_positive_x := func(point: Vector3) -> bool: return point.x > 0.0
	var best: Vector3 = LFUtils3D.farthest_sample_xz(5.0, 50, away, only_positive_x, rng)
	assert_gt(best.x, 0.0)
	assert_null(LFUtils3D.farthest_sample_xz(5.0, 50, away, func(_point: Vector3) -> bool: return false, rng))


func test_farthest_sample_xz_with_nothing_to_avoid_takes_the_first_accepted_sample():
	var none: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var replay := RandomNumberGenerator.new()
	replay.seed = 9
	var first := Vector3(replay.randf_range(-5.0, 5.0), 0.0, replay.randf_range(-5.0, 5.0))
	assert_eq(LFUtils3D.farthest_sample_xz(5.0, 10, none, Callable(), rng), first)


func test_to_xz_and_distance_xz_ignore_height():
	assert_eq(LFUtils3D.to_xz(Vector3(1, 2, 3)), Vector2(1, 3))
	assert_almost_eq(LFUtils3D.distance_xz(Vector3(0, 100, 0), Vector3(3, -5, 4)), 5.0, 0.0001)


func test_away_is_never_zero_even_with_an_epsilon_of_zero_or_less():
	assert_almost_eq(LFUtils3D.away_xz(Vector3.ZERO, Vector3.ZERO, 0.0).length(), 1.0, 0.0001)
	assert_almost_eq(LFUtils3D.away_xz(Vector3.ZERO, Vector3.ZERO, -1.0).length(), 1.0, 0.0001)


func test_away_within_epsilon_but_not_coinciding_rolls_a_random_direction():
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var replay := RandomNumberGenerator.new()
	replay.seed = 5
	var near := LFUtils3D.away_xz(Vector3(0.0005, 0, 0), Vector3.ZERO, LFUtils3D.DEFAULT_EPSILON, rng)
	assert_eq(near, LFUtils3D.random_direction_xz(replay), "inside epsilon the direction is rolled, not +X")
	assert_true(LFUtils3D.away_xz(Vector3(0.0005, 0, 0), Vector3.ZERO, 0.0001).is_equal_approx(Vector3.RIGHT), "outside a smaller epsilon it is the real direction")


func test_farthest_sample_xz_with_no_samples_is_null():
	var away: Array[Vector3] = [Vector3.ZERO]
	assert_null(LFUtils3D.farthest_sample_xz(5.0, 0, away))
	assert_null(LFUtils3D.farthest_sample_xz(5.0, -3, away))


func test_farthest_sample_xz_with_nothing_to_avoid_takes_the_first_sample_accept_lets_through():
	var none: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var replay := RandomNumberGenerator.new()
	replay.seed = 21
	var first_accepted: Variant = null
	for i in 30:
		var p := Vector3(replay.randf_range(-5.0, 5.0), 0.0, replay.randf_range(-5.0, 5.0))
		if p.x > 0.0 and first_accepted == null:
			first_accepted = p
	var result: Variant = LFUtils3D.farthest_sample_xz(5.0, 30, none, func(point: Vector3) -> bool: return point.x > 0.0, rng)
	assert_eq(result, first_accepted)
