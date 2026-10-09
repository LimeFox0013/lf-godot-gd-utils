extends GutTest

## The expected hashes are fixtures: hashes already saved by any account file must keep
## verifying, so these bytes may never change.


func test_hashes_match_the_stored_fixtures():
	assert_eq(LFPasswordHash.compute('open the pod bay', 'a1b2c3d4e5f60718293a4b5c6d7e8f90', 10), 'c303fa89a0ebaf5a87282398e08a35ff4a62bbc9d7f006074d91c5768ea7dfea')
	assert_eq(LFPasswordHash.compute('pässwörd ✓', 'salt', 3), '269b62c92e4da1a8dc4feab5088c30190a9f9736559293e5ba2228166583f15b', 'UTF-8 bytes of both')
	assert_eq(LFPasswordHash.compute('hunter22', '00', 20000), '79e2a7fdcd88306c7aa736ad51b9875fce486f2badff6941611dbafc4d235b92')


func test_one_round_is_plain_hmac_sha256():
	var expected := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, 'key'.to_utf8_buffer(), 'message'.to_utf8_buffer()).hex_encode()
	assert_eq(LFPasswordHash.compute('message', 'key', 1), expected)


func test_an_empty_password_and_salt_still_hash_to_the_standard_hmac():
	# HMAC-SHA256 with an empty key over an empty message.
	assert_eq(LFPasswordHash.compute('', '', 1), 'b613679a0814d9ec772f95d778c35fc5ff1697c493715653c6c712144292c5ad')
	assert_eq(LFPasswordHash.compute('', 'salt', 2).length(), 64)


func test_fewer_than_one_round_still_hashes_once():
	assert_eq(LFPasswordHash.compute('pw', 'salt', 0), LFPasswordHash.compute('pw', 'salt', 1))
	assert_ne(LFPasswordHash.compute('pw', 'salt', 0), 'pw'.to_utf8_buffer().hex_encode())


func test_salt_rounds_and_password_all_change_the_hash():
	var base := LFPasswordHash.compute('pw', 'salt', 5)
	assert_ne(LFPasswordHash.compute('pw', 'pepper', 5), base)
	assert_ne(LFPasswordHash.compute('pw', 'salt', 6), base)
	assert_ne(LFPasswordHash.compute('pW', 'salt', 5), base)


func test_verify_accepts_only_the_right_password():
	var stored := LFPasswordHash.compute('open the pod bay', 'salt', 10)

	assert_true(LFPasswordHash.verify('open the pod bay', 'salt', 10, stored))
	assert_false(LFPasswordHash.verify('open the pod bay!', 'salt', 10, stored))
	assert_false(LFPasswordHash.verify('open the pod bay', 'salt', 11, stored))
	assert_false(LFPasswordHash.verify('', 'salt', 10, ''), 'an empty stored hash never matches')


func test_constant_time_equality():
	assert_true(LFPasswordHash.equals_full_scan('abc', 'abc'))
	assert_true(LFPasswordHash.equals_full_scan('', ''))
	assert_false(LFPasswordHash.equals_full_scan('abc', 'abd'))
	assert_false(LFPasswordHash.equals_full_scan('abc', 'ab'))
	assert_false(LFPasswordHash.equals_full_scan('', 'a'))
	assert_false(LFPasswordHash.equals_full_scan('ab\u0000', 'ab'), 'a trailing zero byte is still a difference')


## The engine's HMAC refuses an empty key or message, so those go through the hand-written
## RFC 2104 path: it must give the same bytes as any standard HMAC-SHA256 (Python's
## `hmac` module produced these).
func test_the_hand_written_hmac_matches_the_standard_for_an_empty_key_or_message():
	assert_eq(LFPasswordHash.compute('', 'salt', 1), '379d7f7966f400cb6e3c0b2cca4bf8a2db03b8c81fef8020015b5a3103c30460', 'empty password')
	assert_eq(LFPasswordHash.compute('', 'salt', 2), 'ae296cc2d561b3e27e230280c91d5c57728fa7327c19a603d2fe2b951c5f3d18', 'the second round has a message again')
	assert_eq(LFPasswordHash.compute('pw', '', 1), 'b341db40a4fff0be22734225a191a5296924222c7ecbeea220726b7aabe6a742', 'empty salt')
	assert_eq(LFPasswordHash.compute('pw', '', 3), '0aa127819a2805a877c049e3730953872cb1a29a170956114efe2c1827f4b9ce', 'empty salt, every round')


func test_a_salt_longer_than_the_hash_block_is_hashed_first_as_rfc_2104_says():
	assert_eq(LFPasswordHash.compute('', 'x'.repeat(100), 1), 'f27e9d033f8afb8db9abbb1cee40470512ffbe9e76153cc2481ec7e812869b6f')
