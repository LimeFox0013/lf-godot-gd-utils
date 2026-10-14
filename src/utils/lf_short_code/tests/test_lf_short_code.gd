extends GutTest

const ALPHABET := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
const LENGTH := 5


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_gen_draws_one_randi_range_per_character_in_order():
	var expected := ''
	var mirror := _rng(7)
	for i in LENGTH:
		expected += ALPHABET[mirror.randi_range(0, ALPHABET.length() - 1)]
	assert_eq(LFShortCode.gen(LENGTH, ALPHABET, _rng(7)), expected)


func test_gen_uses_only_the_alphabet_and_the_length():
	var rng := _rng(1)
	for i in 50:
		var code := LFShortCode.gen(LENGTH, ALPHABET, rng)
		assert_eq(code.length(), LENGTH)
		assert_true(LFShortCode.is_valid(code, LENGTH, ALPHABET), code)


func test_gen_redraws_a_taken_code():
	var first := LFShortCode.gen(LENGTH, ALPHABET, _rng(3))
	var taken := func(code: String) -> bool: return code == first
	var code := LFShortCode.gen(LENGTH, ALPHABET, _rng(3), taken)
	assert_ne(code, first)
	assert_eq(code.length(), LENGTH)


func test_gen_gives_up_when_every_code_is_taken():
	assert_eq(LFShortCode.gen(2, 'A', _rng(1), func(_code: String) -> bool: return true), '')


func test_gen_returns_empty_for_bad_input():
	assert_eq(LFShortCode.gen(0, ALPHABET, _rng(1)), '')
	assert_eq(LFShortCode.gen(LENGTH, '', _rng(1)), '')


func test_normalize_trims_and_upper_cases():
	assert_eq(LFShortCode.normalize(' k7mqa '), 'K7MQA')


func test_is_valid_accepts_any_case_and_padding():
	assert_true(LFShortCode.is_valid(' k7mqa ', LENGTH, ALPHABET))


func test_is_valid_rejects_wrong_length_and_letters_outside_the_alphabet():
	assert_false(LFShortCode.is_valid('ABCD', LENGTH, ALPHABET))
	assert_false(LFShortCode.is_valid('ABCDEF', LENGTH, ALPHABET))
	assert_false(LFShortCode.is_valid('ABCDO', LENGTH, ALPHABET))
	assert_false(LFShortCode.is_valid('192.168.1.20', LENGTH, ALPHABET))
