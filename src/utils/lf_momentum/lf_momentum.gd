## A value that is built up by bumps and, while you say it is slowing, wears off down to a base.
##
## Think of the acceleration of a runner that grows with every good jump, melts away while the
## runner is slowing down, and is cut back by a mistake. The class holds the number; the game
## decides what a bump is worth, when the character is slowing, and what the number does. Decay
## is a plain on/off you pass in at every `step`: nothing is remembered between steps, so there is
## no state to forget to switch off. The value always stays between `base` and `cap`.
class_name LFMomentum
extends RefCounted


## The decay, in value per second, a momentum has when none is given: 0, no decay.
const DEFAULT_DECAY_PER_SECOND := 0.0
## The `initial_cap` meaning "no room to grow": the cap equals the base.
const CAP_AT_BASE := NAN

## The lowest the value goes. Raising it lifts the value and the cap if they are below it.
var base: float = 0.0:
	set(new_base):
		if not is_finite(new_base):
			_log.error('the base must be finite, got', new_base)
			return
		base = new_base
		cap = maxf(cap, base)
		value = maxf(value, base)
## The highest the value goes: `bump` stops here. Finite, and not below `base`; otherwise
## reported through `LFLogger` and ignored.
var cap: float = 0.0:
	set(new_cap):
		if not is_finite(new_cap) or new_cap < base:
			_log.error('the cap must be finite and not below the base', base, 'got', new_cap)
			return
		cap = new_cap
		value = minf(value, cap)
## How much of the value wears off per second of `step(delta, true)`: 0 or more and finite,
## otherwise reported through `LFLogger` and ignored.
var decay_per_second: float = DEFAULT_DECAY_PER_SECOND:
	set(new_rate):
		if not is_finite(new_rate) or new_rate < 0.0:
			_log.error('the decay must be finite and 0 or more, got', new_rate)
			return
		decay_per_second = new_rate
## The value now, from `base` to `cap`. Read it; change it through the methods.
var value: float = 0.0

var _log := LFLogger.new(['LFMomentum'])


## A momentum resting at `initial_base`, able to grow to `initial_cap` (not below the base;
## otherwise reported and the base is used; `CAP_AT_BASE`, the default, is the base itself; a NaN counts as that, not as an error),
## losing `initial_decay_per_second` while slowing.
func _init(initial_base: float = 0.0, initial_cap: float = CAP_AT_BASE, initial_decay_per_second: float = DEFAULT_DECAY_PER_SECOND) -> void:
	base = initial_base
	if not is_nan(initial_cap):
		cap = initial_cap
	decay_per_second = initial_decay_per_second
	value = base


## Adds `amount` (0 or more) to the value, up to `cap`, and returns the value. A negative,
## NaN or INF amount is reported through `LFLogger` and ignored: lower the value with
## `penalize`.
func bump(amount: float) -> float:
	if not is_finite(amount) or amount < 0.0:
		_log.error('a bump must be finite and 0 or more, got', amount)
		return value
	value = minf(value + amount, cap)
	return value


## Advances `delta` seconds and returns the value. While `slowing` is true the value falls by
## `decay_per_second * delta`, never below `base`; while it is false nothing changes. Pass the
## flag fresh at every step (for example "the character's speed dropped since last frame"):
## a step with false never decays, whatever came before. A negative or non-finite `delta`
## changes nothing.
func step(delta: float, slowing: bool) -> float:
	if slowing and is_finite(delta) and delta > 0.0:
		value = maxf(value - decay_per_second * delta, base)
	return value


## Cuts the value by `fraction` (0 to 1: 0.2 removes a fifth of it) but never below `base`, and
## returns the value. A fraction outside 0 to 1, or NaN, is reported through `LFLogger` and
## ignored. The cut is on the whole value, not on the part above the base, so with a high base
## a large fraction ends on the base.
func penalize(fraction: float) -> float:
	if is_nan(fraction) or fraction < 0.0 or fraction > 1.0:
		_log.error('a penalty fraction must be from 0 to 1, got', fraction)
		return value
	value = maxf(value - value * fraction, base)
	return value


## Puts the value back on `base`.
func reset() -> void:
	value = base


## Where the value sits between `base` (0.0) and `cap` (1.0). 0.0 when the cap equals the base.
func ratio() -> float:
	if cap <= base:
		return 0.0
	return clampf((value - base) / (cap - base), 0.0, 1.0)


## Whether the value is above `base`.
func is_built_up() -> bool:
	return value > base
