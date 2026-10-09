extends GutTest

func test_sampled_point_always_falls_within_rect_bounds_inclusive_of_edges():
	var rect = Rect2(10, 20, 5, 8)
	for i in 200:
		var point = LFUtils.random_point_in_rect(rect)
		assert_true(point.x >= rect.position.x and point.x <= rect.position.x + rect.size.x)
		assert_true(point.y >= rect.position.y and point.y <= rect.position.y + rect.size.y)


func test_sampled_point_can_land_exactly_on_the_far_edge():
	# A zero-size rect forces every sample onto its single "edge" point,
	# proving the far bound is reachable, not just approached.
	var point = LFUtils.random_point_in_rect(Rect2(10, 20, 0, 0))
	assert_eq(point, Vector2(10, 20))


func test_a_seeded_generator_makes_the_point_reproducible():
	var rect = Rect2(0, 0, 100, 100)
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42

	var point = LFUtils.random_point_in_rect(rect, rng_a)

	assert_eq(point, LFUtils.random_point_in_rect(rect, rng_b))
	assert_true(rect.has_point(point) or point.x == 100 or point.y == 100)


func test_without_a_generator_the_global_one_is_used():
	var rect := Rect2(-50, -50, 100, 100)
	seed(77)
	var first := LFUtils.random_point_in_rect(rect)
	seed(77)
	assert_eq(LFUtils.random_point_in_rect(rect), first, 'reseeding the global generator replays it')
