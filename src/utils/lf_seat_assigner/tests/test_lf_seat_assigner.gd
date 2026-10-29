extends GutTest

var seats: LFSeatAssigner
var announced: Array


func before_each():
	seats = LFSeatAssigner.new(["a", "b", "c", "d"])
	announced = []
	seats.seat_assigned.connect(func(peer, seat): announced.append([peer, seat]))


func test_peers_get_the_seats_in_the_order_they_arrive():
	for peer in [11, 12, 13, 14]:
		assert_true(seats.assign_next(peer))
	assert_eq(announced, [[11, "a"], [12, "b"], [13, "c"], [14, "d"]])
	assert_eq(seats.assigned_count(), 4)


func test_a_peer_gets_nothing_when_every_seat_is_taken():
	for peer in [1, 2, 3, 4]:
		seats.assign_next(peer)
	assert_false(seats.assign_next(5))
	assert_null(seats.seat_of(5))
	assert_eq(announced.size(), 4)


func test_a_seat_that_is_given_up_goes_to_the_back_of_the_line():
	seats.reserve("d")
	for peer in [1, 2, 3]:
		seats.assign_next(peer)
	seats.forget(2)
	seats.forget(1)
	assert_eq(seats.free_seats(), ["b", "a"])
	announced.clear()
	seats.assign_next(7)
	seats.assign_next(8)
	assert_eq(announced, [[7, "b"], [8, "a"]])


func test_forget_returns_the_seat_and_ignores_an_unknown_peer():
	seats.assign_next(1)
	assert_eq(seats.forget(1), "a")
	assert_true(seats.is_free("a"))
	assert_null(seats.forget(1))
	assert_eq(seats.free_seats(), ["b", "c", "d", "a"])


func test_a_swap_announces_the_displaced_peer_before_the_claimant():
	seats.assign_next(1)
	seats.assign_next(2)
	announced.clear()
	assert_true(seats.move(1, "b"))
	assert_eq(announced, [[2, "a"], [1, "b"]])
	assert_eq(seats.seat_of(1), "b")
	assert_eq(seats.seat_of(2), "a")
	assert_eq(seats.free_seats(), ["c", "d"])


func test_both_peers_hold_their_new_seats_when_the_swap_is_announced():
	seats.assign_next(1)
	seats.assign_next(2)
	var seen: Array = []
	seats.seat_assigned.connect(func(_peer, _seat): seen.append([seats.seat_of(1), seats.seat_of(2)]))
	seats.move(1, "b")
	assert_eq(seen, [["b", "a"], ["b", "a"]])


func test_a_move_onto_a_free_seat_frees_the_old_one_at_the_back():
	seats.assign_next(1)
	announced.clear()
	assert_true(seats.move(1, "c"))
	assert_eq(announced, [[1, "c"]])
	assert_eq(seats.free_seats(), ["b", "d", "a"])


func test_moving_to_the_held_seat_is_a_quiet_success():
	seats.assign_next(1)
	announced.clear()
	assert_true(seats.move(1, "a"))
	assert_eq(announced, [])
	assert_eq(seats.free_seats(), ["b", "c", "d"])


func test_a_move_to_an_unknown_seat_or_by_an_unseated_peer_changes_nothing():
	seats.assign_next(1)
	announced.clear()
	assert_false(seats.move(1, "zzz"))
	assert_false(seats.move(99, "b"))
	assert_eq(announced, [])
	assert_eq(seats.free_seats(), ["b", "c", "d"])


func test_a_reserved_seat_is_never_handed_out_but_can_be_claimed():
	seats.reserve("a")
	assert_false(seats.is_free("a"))
	seats.assign_next(1)
	assert_eq(seats.seat_of(1), "b")
	assert_true(seats.move(1, "a"))
	assert_eq(seats.peer_of("a"), 1)


func test_peer_of_and_has_peer_follow_the_assignments():
	seats.assign_next(5)
	assert_eq(seats.peer_of("a"), 5)
	assert_null(seats.peer_of("b"))
	assert_true(seats.has_peer(5))
	assert_false(seats.has_peer(6))
	assert_eq(seats.peers(), [5])


func test_proof_counts_only_for_a_seated_peer_and_ends_with_forget():
	seats.assign_next(1)
	seats.mark_verified(1)
	seats.mark_verified(42)
	assert_true(seats.is_verified(1))
	assert_false(seats.is_verified(42))
	assert_eq(seats.verified_count(), 1)
	seats.forget(1)
	assert_false(seats.is_verified(1))
	assert_eq(seats.verified_count(), 0)


func test_the_lists_it_returns_are_copies():
	seats.assign_next(1)
	seats.free_seats().clear()
	seats.seats_by_peer().clear()
	assert_eq(seats.free_seats(), ["b", "c", "d"])
	assert_eq(seats.seat_of(1), "a")


func test_a_seated_peer_is_not_seated_twice():
	assert_true(seats.assign_next(1))
	announced.clear()
	assert_false(seats.assign_next(1))
	assert_eq(announced, [])
	assert_eq(seats.seat_of(1), "a")
	assert_eq(seats.free_seats(), ["b", "c", "d"])


func test_seats_by_peer_and_verified_count():
	seats.assign_next(1)
	seats.assign_next(2)
	seats.mark_verified(2)
	assert_eq(seats.seats_by_peer(), {1: "a", 2: "b"})
	assert_eq(seats.verified_count(), 1)
