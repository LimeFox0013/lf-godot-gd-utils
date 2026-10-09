extends GutTest

## Too many strikes in a short window block that key for a while; old strikes age out of
## the window; `prune()` keeps the guard from growing.

const MAX := 5
const WINDOW := 60.0
const BLOCK := 300.0

var guard: LFStrikeGuard
var clock := [0.0]


func before_each():
	clock[0] = 0.0
	guard = LFStrikeGuard.new(MAX, WINDOW, BLOCK, func(): return clock[0])


func test_too_many_strikes_block_that_key_only_for_a_while():
	for i in MAX - 1:
		assert_false(guard.strike('1.2.3.4'))
	assert_false(guard.is_blocked('1.2.3.4'))

	assert_true(guard.strike('1.2.3.4'))

	assert_true(guard.is_blocked('1.2.3.4'))
	assert_false(guard.is_blocked('5.6.7.8'), 'other keys are untouched')
	clock[0] += BLOCK - 0.01
	assert_true(guard.is_blocked('1.2.3.4'))
	clock[0] += 0.01
	assert_false(guard.is_blocked('1.2.3.4'))


func test_slow_guessing_ages_out_of_the_window():
	for i in MAX * 2:
		guard.strike('1.2.3.4')
		clock[0] += WINDOW / (MAX - 1)

	assert_false(guard.is_blocked('1.2.3.4'))


func test_after_a_block_a_key_starts_over():
	for i in MAX:
		guard.strike('k')
	clock[0] += BLOCK

	assert_false(guard.is_blocked('k'), 'the expired block is cleared')
	assert_false(guard.strike('k'), 'one new strike is not a block')


func test_forget_forgets_strikes_and_lifts_a_block():
	for i in MAX - 1:
		guard.strike('a')
	for i in MAX:
		guard.strike('b')

	guard.forget('a')
	guard.forget('b')

	assert_false(guard.is_blocked('b'))
	assert_false(guard.strike('a'), 'its earlier strikes are gone')


func test_prune_forgets_keys_that_stopped_guessing_and_expired_blocks():
	guard.strike('old')
	for i in MAX:
		guard.strike('blocked')
	clock[0] += WINDOW
	guard.strike('recent')

	guard.prune()
	assert_eq(guard.tracked_count(), 2, 'the old strike aged out; the block and the recent strike stay')
	assert_true(guard.is_blocked('blocked'))

	clock[0] += BLOCK
	guard.prune()
	assert_eq(guard.tracked_count(), 0)


func test_prune_keeps_counting_recent_strikes():
	for i in MAX - 1:
		guard.strike('k')
	guard.prune()

	assert_true(guard.strike('k'))


func test_without_a_clock_it_runs_on_steady_time():
	var real := LFStrikeGuard.new(1, 10.0, 10.0)
	assert_true(real.strike('k'))
	assert_true(real.is_blocked('k'))


func test_steady_seconds_follows_the_engine_clock():
	var before := Time.get_ticks_msec() / 1000.0
	var now := LFStrikeGuard.steady_seconds()
	assert_between(now, before, Time.get_ticks_msec() / 1000.0)


func test_settings_and_the_clock_can_be_changed_later():
	guard.max_strikes = 2
	guard.block_seconds = 10.0
	assert_false(guard.strike('k'))
	assert_true(guard.strike('k'))

	var other := [5.0]
	guard.clock_seconds = func(): return other[0]
	assert_true(guard.is_blocked('k'), 'still before the end of the block on the new clock')
	other[0] += 5.0
	assert_false(guard.is_blocked('k'))

	guard.window_seconds = 1.0
	guard.strike('w')
	other[0] += 1.0
	assert_false(guard.strike('w'), 'the first strike left the shorter window')


func test_strikes_while_blocked_restart_the_block():
	for i in MAX:
		guard.strike('k')
	clock[0] += BLOCK - 1.0
	for i in MAX:
		guard.strike('k')

	clock[0] += 1.0
	assert_true(guard.is_blocked('k'), 'the second block started later, so it has not run out')
	clock[0] += BLOCK - 1.0
	assert_false(guard.is_blocked('k'))


func test_one_strike_limit_blocks_on_the_first_strike():
	guard.max_strikes = 1
	assert_true(guard.strike('k'))


## Godot accepts leading zeros in an IPv4 address; each spelling of one address must
## share one key, or a guesser could strike `1.2.3.4`, `01.2.3.4`, `001.2.3.4`... apart.
func test_address_key_drops_leading_zeros_from_ipv4_parts():
	for spelling in ['1.2.3.4', '01.2.3.4', '001.002.003.004', '1.2.3.04', ' 0001.2.3.4 ', '[01.2.3.4]', '::ffff:01.2.3.4']:
		assert_eq(LFStrikeGuard.address_key(spelling), '1.2.3.4', spelling)
	assert_eq(LFStrikeGuard.address_key('08.0.0.10'), '8.0.0.10', 'decimal, not octal')
	assert_eq(LFStrikeGuard.address_key('256.1.1.1'), '256.1.1.1', 'not an address: unchanged')


func test_address_key_groups_an_ipv6_address_by_its_64_network():
	assert_eq(LFStrikeGuard.address_key('2001:db8:0:1:2:3:4:5'), '2001:db8:0:1::/64')
	assert_eq(LFStrikeGuard.address_key('2001:db8::1:2:3:4'), '2001:db8:0:0::/64', '"::" expands to zero groups')
	assert_eq(LFStrikeGuard.address_key('2001:DB8:0:1:ffff:ffff:ffff:ffff'), '2001:db8:0:1::/64', 'same network, same key')
	assert_eq(LFStrikeGuard.address_key('[fe80::1%en0]'), 'fe80:0:0:0::/64', 'brackets and zone dropped')
	assert_eq(LFStrikeGuard.address_key('::1'), '0:0:0:0::/64')
	assert_eq(LFStrikeGuard.address_key('2001:db8:aa:bb::'), '2001:db8:aa:bb::/64')


func test_address_key_keeps_ipv4_and_unwraps_ipv4_mapped_addresses():
	assert_eq(LFStrikeGuard.address_key('203.0.113.7'), '203.0.113.7')
	assert_eq(LFStrikeGuard.address_key('::ffff:203.0.113.7'), '203.0.113.7')
	assert_eq(LFStrikeGuard.address_key('not an address'), 'not an address')
	assert_eq(LFStrikeGuard.address_key(''), '')


## Two different IPv4 hosts written as hex IPv4-mapped IPv6 must not share one key (they
## all sit in ::ffff:0:0/96, so their /64 would be the same).
func test_address_key_unwraps_hex_and_expanded_ipv4_mapped_addresses():
	assert_eq(LFStrikeGuard.address_key('::ffff:102:304'), '1.2.3.4')
	assert_eq(LFStrikeGuard.address_key('::FFFF:CB00:7107'), '203.0.113.7')
	assert_eq(LFStrikeGuard.address_key('0:0:0:0:0:ffff:203.0.113.7'), '203.0.113.7')
	assert_eq(LFStrikeGuard.address_key('[::ffff:102:304]'), '1.2.3.4')
	assert_ne(LFStrikeGuard.address_key('::ffff:102:304'), LFStrikeGuard.address_key('::ffff:506:708'))


func test_address_key_writes_the_first_four_groups_uncompressed():
	assert_eq(LFStrikeGuard.address_key('2001:0DB8:0000:0001::9'), '2001:db8:0:1::/64', 'lower case, no leading zeros')
	assert_eq(LFStrikeGuard.address_key('fe80::1'), 'fe80:0:0:0::/64', 'zero groups are written, not folded into "::"')


func test_one_ipv6_network_shares_one_block():
	var guard := LFStrikeGuard.new(2, 60.0, 60.0, func() -> float: return 0.0)
	guard.strike(LFStrikeGuard.address_key('2001:db8::1'))
	guard.strike(LFStrikeGuard.address_key('2001:db8::2'))

	assert_true(guard.is_blocked(LFStrikeGuard.address_key('2001:db8::ffff')))
	assert_false(guard.is_blocked(LFStrikeGuard.address_key('2001:db8:0:2::1')), 'the next /64 is someone else')


func test_a_limit_of_zero_or_less_blocks_on_the_first_strike():
	guard.max_strikes = 0
	assert_true(guard.strike('zero'))
	guard.max_strikes = -3
	assert_true(guard.strike('negative'))


func test_forgetting_an_unknown_key_changes_nothing():
	guard.strike('k')

	guard.forget('never-seen')

	assert_eq(guard.tracked_count(), 1)


func test_clear_forgets_every_key_and_lifts_every_block():
	for i in MAX:
		guard.strike('blocked')
	guard.strike('guessing')
	assert_true(guard.is_blocked('blocked'))

	guard.clear()

	assert_false(guard.is_blocked('blocked'))
	assert_eq(guard.tracked_count(), 0)


func test_a_nan_window_or_block_is_rejected_and_the_value_is_kept():
	guard.window_seconds = NAN
	guard.block_seconds = NAN
	assert_push_error_count(2)
	assert_eq([guard.window_seconds, guard.block_seconds], [WINDOW, BLOCK])
	for i in MAX:
		guard.strike('k')
	assert_true(guard.is_blocked('k'), 'the block still has a real end')
	clock[0] += BLOCK
	assert_false(guard.is_blocked('k'))


func test_keys_can_be_peer_ids_and_do_not_mix_with_strings():
	for i in MAX:
		guard.strike(7)

	assert_true(guard.is_blocked(7))
	assert_false(guard.is_blocked('7'), 'a String key is a different key')


## Strikes while blocked put the key in both the strike list and the block list; it is
## still one key.
func test_tracked_count_counts_a_blocked_key_that_keeps_striking_once():
	for i in MAX:
		guard.strike('k')
	guard.strike('k')

	assert_eq(guard.tracked_count(), 1)


## A key with old and new strikes keeps only the new ones: it stays tracked, and only the
## strikes still inside the window count toward the block.
func test_prune_trims_a_key_with_old_and_recent_strikes():
	for i in MAX - 1:
		guard.strike('k')
	clock[0] += WINDOW
	guard.strike('k')

	guard.prune()

	assert_eq(guard.tracked_count(), 1)
	for i in MAX - 2:
		assert_false(guard.strike('k'), 'the aged-out strikes no longer count')
	assert_true(guard.strike('k'))


func test_address_key_strips_surrounding_whitespace():
	assert_eq(LFStrikeGuard.address_key(' 203.0.113.7 '), '203.0.113.7')
	assert_eq(LFStrikeGuard.address_key('\t2001:db8:0:1::9\n'), '2001:db8:0:1::/64')


## Only `0:0:0:0:0:ffff:…` is an IPv4 address in IPv6 form; anything else with `ffff` in
## the sixth group, or a different sixth group, is an ordinary IPv6 address.
func test_address_key_unwraps_only_true_ipv4_mapped_addresses():
	assert_eq(LFStrikeGuard.address_key('1::ffff:102:304'), '1:0:0:0::/64', 'a non-zero first group is not mapped')
	assert_eq(LFStrikeGuard.address_key('::fffe:102:304'), '0:0:0:0::/64', 'a sixth group other than ffff is not mapped')


func test_a_window_or_block_that_makes_the_guard_useless_is_reported():
	LFStrikeGuard.new(3, 0.0, BLOCK)
	LFStrikeGuard.new(3, NAN, BLOCK)
	LFStrikeGuard.new(3, WINDOW, 0.0)
	assert_push_error_count(3)


func test_a_one_strike_limit_does_not_need_a_window():
	LFStrikeGuard.new(1, 0.0, BLOCK)
	assert_push_error_count(0)


class ClockHolder:
	extends Object
	func now() -> float:
		return 0.0


func test_a_freed_clock_fails_closed_and_errors_once():
	var holder := ClockHolder.new()
	var frozen := LFStrikeGuard.new(MAX, WINDOW, BLOCK, holder.now)
	assert_false(frozen.is_blocked('1.2.3.4'))
	holder.free()

	assert_true(frozen.is_blocked('1.2.3.4'), 'every key stays blocked')
	assert_true(frozen.is_blocked('5.6.7.8'))
	assert_true(frozen.strike('1.2.3.4'), 'a strike blocks, as nothing can be timed')
	frozen.prune()
	assert_push_error_count(1, 'reported once, however often it is read')


func test_a_block_survives_the_clock_being_freed():
	var holder := ClockHolder.new()
	var frozen := LFStrikeGuard.new(1, WINDOW, BLOCK, holder.now)
	assert_true(frozen.strike('1.2.3.4'))
	holder.free()

	assert_true(frozen.is_blocked('1.2.3.4'))
	assert_push_error_count(1)


func test_the_clock_given_to_the_constructor_is_the_public_clock_seconds():
	var mine := Callable(self, '_zero')
	var timed := LFStrikeGuard.new(MAX, WINDOW, BLOCK, mine)
	assert_eq(timed.clock_seconds, mine)
	assert_eq(LFStrikeGuard.new(MAX, WINDOW, BLOCK).clock_seconds, LFStrikeGuard.steady_seconds)


func _zero() -> float:
	return 0.0
