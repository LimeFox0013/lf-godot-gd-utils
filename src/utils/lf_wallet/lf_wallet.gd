## A balance of one kind of currency: add to it, check a price, spend it, and hear every change.
##
## It knows nothing about what the currency is called. `add` does not limit the amount
## (a negative add can go below zero); `spend` refuses what the balance cannot cover.
class_name LFWallet
extends RefCounted

## The balance changed (`add`, or a successful `spend`); carries the new amount.
signal changed(amount: float)

## The current balance.
var amount: float


func _init(starting_amount := 0.0) -> void:
	amount = starting_amount


## Adds `delta` (may be negative) and announces the new amount.
func add(delta: float) -> void:
	amount += delta
	changed.emit(amount)


## Whether the balance covers `cost`.
func can_afford(cost: float) -> bool:
	return amount >= cost


## Takes `cost` and announces the new amount; false, changing nothing and staying quiet, when the balance falls short.
func spend(cost: float) -> bool:
	if not can_afford(cost):
		return false
	amount -= cost
	changed.emit(amount)
	return true
