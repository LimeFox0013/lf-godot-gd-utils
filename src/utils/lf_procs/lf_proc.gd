## A "proc": an effect that may trigger when something happens, gated by chance, cooldown, condition and charges.
##
## Example: "when an event happens, 30 % chance to run an action, at most once every 2 s". The action
## runs only when every gate passes. Gates are checked in this fixed order — the order is
## part of the contract, since it decides which rolls a seeded generator spends:
##
## 1. spent: a proc with `charges_left` at 0 never fires;
## 2. condition: `condition(context) -> bool`;
## 3. cooldown: an `LFCooldown` that must be ready (checking it changes nothing);
## 4. chance: a fixed fraction or `chance_getter(context) -> float`, read at every check,
##    rolled as one `randf()` on the caller's generator (a `RandomNumberGenerator`; an
##    `LFRandom` works too, with the same results as its `chance`). A chance at or above 1,
##    at or below 0, or NaN spends no roll.
##
## Passing commits: a charge is spent and the cooldown starts. A gate that fails spends
## nothing after it. Configure with the `with_*` methods, which return the proc itself so
## calls can be chained. Register procs under trigger names with [LFTriggerSet].
##
## A proc with a cooldown or charges carries per-owner state; a proc without either can be
## registered on any number of owners.
class_name LFProc

static var _log := LFLogger.new()

## The `charges_left` value meaning the proc never runs out of charges.
const UNLIMITED_CHARGES := -1
## A chance (fraction) that always passes without a roll.
const _CERTAIN := 1.0


## What firing runs: `func(context) -> Variant`. May be replaced at any time. Its result
## only matters to `LFTriggerSet.fire_until_handled`. While it is not valid, the proc
## never fires.
var action: Callable
## How many more times this proc may fire, or `UNLIMITED_CHARGES` (the default; any negative
## number means the same). Set it with
## `with_charges`, or directly (e.g. to refill charges).
var charges_left := UNLIMITED_CHARGES

var _chance := _CERTAIN
var _chance_getter: Callable
var _condition: Callable
var _cooldown: LFCooldown


## A proc running `reaction(context)` when every gate passes; it has no gates (always
## fires) until configured with the `with_*` methods.
func _init(reaction: Callable) -> void:
	action = reaction


## Sets a fixed chance to fire, from 0 to 1 (0.3 = 30 %; default 1: always, no roll).
## Returns this proc.
func with_chance(fraction: float) -> LFProc:
	_chance = fraction
	return self


## Sets a chance read from `getter(context) -> float` at every check — for a chance that
## changes, such as one read from the owner's current state. Overrides `with_chance`. Returns
## this proc.
func with_chance_getter(getter: Callable) -> LFProc:
	_chance_getter = getter
	return self


## Sets a condition `condition(context) -> bool` that must return true, checked before
## the cooldown and the roll. Returns this proc.
func with_condition(condition: Callable) -> LFProc:
	_condition = condition
	return self


## Sets a cooldown that must be ready for the proc to fire, and is started when it does.
## Checking it changes nothing. Returns this proc.
func with_cooldown(cooldown: LFCooldown) -> LFProc:
	_cooldown = cooldown
	return self


## Sets how many times this proc may fire in all (`charges_left`); 0 makes a proc that
## never fires, `UNLIMITED_CHARGES` (or any negative number) unlimited. Returns this proc.
func with_charges(charges: int) -> LFProc:
	charges_left = charges
	return self


## Whether the charges are used up (`charges_left` is 0). Never true with unlimited
## charges.
func is_spent() -> bool:
	return charges_left == 0


## Checks every gate with `context` and, when all pass, commits (spends a charge, starts
## the cooldown) and returns true — without running the action. Returns false when a gate
## fails. A chance below 1 needs `rng` (any `RandomNumberGenerator`, `LFRandom` included);
## without one the proc reports an error and fails.
func check(rng: RandomNumberGenerator, context: Variant = null) -> bool:
	if charges_left == 0:
		return false
	if _condition.is_valid() and !_condition.call(context):
		return false
	if _cooldown != null and !_cooldown.is_ready():
		return false
	var fraction: float = _chance_getter.call(context) if _chance_getter.is_valid() else _chance
	if !(fraction >= _CERTAIN):
		if !(fraction > 0.0):
			return false
		if rng == null:
			_log.error("LFProc: a chance below 1 needs a generator to roll on")
			return false
		# The same single roll as `LFRandom.chance` makes for a fraction strictly between 0 and 1.
		if !(rng.randf() < fraction):
			return false
	if charges_left > 0:
		charges_left -= 1
	if _cooldown != null:
		_cooldown.start()
	return true


## Tries to fire: `check()`, then runs the action with `context`. Returns true when it
## fired. A proc whose `action` is not valid (empty, or its object was freed) does not
## fire: no gate is checked, no roll is spent and nothing is committed.
func fire(rng: RandomNumberGenerator, context: Variant = null) -> bool:
	if !action.is_valid() or !check(rng, context):
		return false
	action.call(context)
	return true
