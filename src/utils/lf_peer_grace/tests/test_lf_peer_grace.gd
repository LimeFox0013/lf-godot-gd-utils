extends GutTest

const GRACE := 5.0

var grace: LFPeerGrace


func before_each():
	grace = LFPeerGrace.new(GRACE)


func test_a_peer_expires_once_its_time_is_up_and_not_before():
	grace.add(1)
	assert_eq(grace.tick(GRACE - 0.1), [])
	assert_true(grace.is_pending(1))
	assert_eq(grace.tick(0.1), [1])
	assert_false(grace.is_pending(1))
	assert_eq(grace.tick(GRACE), [], 'an expired peer is reported once')


func test_a_proven_peer_never_expires():
	grace.add(1)
	grace.proven(1)
	assert_eq(grace.tick(GRACE * 2), [])
	assert_eq(grace.pending_count(), 0)


func test_forget_stops_the_clock_of_a_peer_that_left():
	grace.add(1)
	grace.forget(1)
	assert_eq(grace.tick(GRACE * 2), [])


func test_expired_peers_come_back_in_the_order_they_were_added():
	grace.add(3)
	grace.add(1)
	grace.add(2)
	assert_eq(grace.tick(GRACE), [3, 1, 2])


func test_each_peer_has_its_own_clock():
	grace.add(1)
	grace.tick(3.0)
	grace.add(2)
	assert_eq(grace.tick(2.0), [1])
	assert_true(grace.is_pending(2))
	assert_eq(grace.tick(3.0), [2])


func test_adding_a_waiting_peer_again_restarts_its_clock():
	grace.add(1)
	grace.tick(4.0)
	grace.add(1)
	assert_eq(grace.tick(4.0), [])


func test_proving_an_unknown_peer_does_nothing():
	grace.proven(9)
	assert_eq(grace.pending_count(), 0)


func test_the_default_grace_applies_when_none_is_given():
	var default_grace := LFPeerGrace.new()
	default_grace.add(1)
	assert_eq(default_grace.tick(LFPeerGrace.DEFAULT_GRACE_SECONDS), [1])
