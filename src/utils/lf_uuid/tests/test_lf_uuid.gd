extends GutTest

var UUID_V4_RE := RegEx.new()


func before_all():
	UUID_V4_RE.compile("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")


func test_generated_uuid_matches_rfc4122_v4_shape():
	var uuid = LFUuid.gen()
	assert_not_null(UUID_V4_RE.search(uuid), "%s did not match the v4 pattern" % uuid)


func test_generated_uuid_sets_version_nibble_to_4():
	for i in 20:
		var uuid = LFUuid.gen()
		assert_eq(uuid[14], "4", "version nibble wrong in %s" % uuid)


func test_generated_uuid_sets_variant_bits_regardless_of_prefix():
	for i in 20:
		var uuid = LFUuid.gen("lf")
		var unprefixed = uuid.substr(3) # drop the "lf-" prefix before indexing groups
		var variant_nibble = unprefixed.split("-")[3][0]
		assert_true(variant_nibble in ["8", "9", "a", "b"], "variant nibble wrong in %s" % uuid)


func test_prefix_is_prepended():
	var uuid = LFUuid.gen("lf")
	assert_true(uuid.begins_with("lf-"))
	assert_not_null(UUID_V4_RE.search(uuid.substr(3)))


func test_successive_calls_produce_different_uuids():
	assert_ne(LFUuid.gen(), LFUuid.gen())


func test_many_calls_in_the_same_instant_never_collide():
	# Calls in the same instant (threads, tight loops) must still differ.
	var seen := {}
	for i in 2000:
		seen[LFUuid.gen()] = true
	assert_eq(seen.size(), 2000)


func test_concurrent_calls_from_threads_never_collide():
	var results: Array = [[], [], [], []]
	var threads: Array[Thread] = []
	for t in 4:
		var thread := Thread.new()
		var bucket: Array = results[t]
		thread.start(func():
			for i in 300:
				bucket.append(LFUuid.gen())
		)
		threads.append(thread)
	for thread in threads:
		thread.wait_to_finish()
	var seen := {}
	for bucket in results:
		for uuid in bucket:
			seen[uuid] = true
	assert_eq(seen.size(), 1200)


func test_a_token_is_twice_its_byte_count_of_lowercase_hex():
	var hex := RegEx.create_from_string("^[0-9a-f]+$")
	assert_eq(LFUuid.token().length(), 32, "16 bytes by default")
	var long := LFUuid.token(32)
	assert_eq(long.length(), 64)
	assert_not_null(hex.search(long), "%s is not lowercase hex" % long)


func test_tokens_do_not_repeat():
	var seen := {}
	for i in 200:
		seen[LFUuid.token(8)] = true
	assert_eq(seen.size(), 200)


func test_a_token_of_no_bytes_is_empty():
	assert_eq(LFUuid.token(0), "")
	assert_eq(LFUuid.token(-3), "")
