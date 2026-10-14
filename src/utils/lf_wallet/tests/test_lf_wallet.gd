extends GutTest

var wallet: LFWallet
var heard: Array


func before_each():
	wallet = LFWallet.new(10.0)
	heard = []
	wallet.changed.connect(func(amount): heard.append(amount))


func test_it_starts_at_the_given_amount_or_zero():
	assert_eq(wallet.amount, 10.0)
	assert_eq(LFWallet.new().amount, 0.0)


func test_add_raises_the_amount_and_announces_it():
	wallet.add(5.0)
	assert_eq(wallet.amount, 15.0)
	assert_eq(heard, [15.0])


func test_add_is_not_clamped_so_a_negative_amount_can_go_below_zero():
	wallet.add(-25.0)
	assert_eq(wallet.amount, -15.0)
	assert_eq(heard, [-15.0])


func test_can_afford_is_true_up_to_and_including_the_amount():
	assert_true(wallet.can_afford(10.0))
	assert_true(wallet.can_afford(0.0))
	assert_false(wallet.can_afford(10.5))


func test_spend_takes_the_cost_and_announces_it():
	assert_true(wallet.spend(4.0))
	assert_eq(wallet.amount, 6.0)
	assert_eq(heard, [6.0])


func test_spend_of_the_whole_amount_empties_it():
	assert_true(wallet.spend(10.0))
	assert_eq(wallet.amount, 0.0)


func test_spend_that_cannot_be_afforded_changes_nothing_and_stays_quiet():
	assert_false(wallet.spend(10.5))
	assert_eq(wallet.amount, 10.0)
	assert_eq(heard, [])
