## Describes one kind of status effect (a timed modifier, a periodic effect...) as data, to apply with `LFStatusEffects`.
##
## A definition says how repeated applications on one owner combine, what happens past
## its stack cap (the most copies it can have at once), how long it lasts, and what (if
## anything) it does on each tick. One definition is shared by every owner it is applied
## to; per-application values (duration, tick interval, cap, payload) can be overridden in
## `LFStatusEffects.apply()` without touching it. It knows nothing about what the effect
## means: your tick callback and your stat code give it meaning.
class_name LFStatusEffectDef

## How repeated applications of the same effect on one owner combine.
enum Accumulation {
	## Each application is its own stack with its own expiry and tick schedule.
	INDEPENDENT,
	## One stack per owner: reapplying refreshes its expiry and raises its `count`.
	SHARED,
}

## Default `duration` of a definition, in seconds.
const DEFAULT_DURATION := 1.0
## Default `max_stacks` of a definition: one copy at a time.
const DEFAULT_MAX_STACKS := 1
## Default `tick_interval` of a definition, in seconds: 0 never ticks.
const DEFAULT_TICK_INTERVAL := 0.0

## Weight of the accumulation mode in a `shared()` cache key (above the overflow and
## per-source bits).
const _ACCUMULATION_KEY_WEIGHT := 4
## Weight of the overflow mode in a `shared()` cache key (above the per-source bit).
const _OVERFLOW_KEY_WEIGHT := 2

## What an INDEPENDENT application does when the owner is already at the stack cap.
enum Overflow {
	## The new application is ignored.
	DROP,
	## Exactly one stack, the one with the least remaining duration, is removed to make room.
	REPLACE_OLDEST,
}

## The effect's name, the key it is stored and queried under in an `LFStatusEffects`
## container (e.g. `&'effect_a'`).
var id: StringName
## How repeated applications on one owner combine.
var accumulation: Accumulation = Accumulation.INDEPENDENT
## What an INDEPENDENT application at the stack cap does.
var overflow: Overflow = Overflow.DROP
## Seconds each application lasts, unless `apply()` overrides it. INF lasts until removed.
## A NaN is rejected: reported through `LFLogger` as an error, and the value is kept.
var duration: float = DEFAULT_DURATION:
	set(value):
		if is_nan(value):
			_log.error('LFStatusEffectDef: a NaN duration is rejected; keeping %s' % duration)
			return
		duration = value
## Stack cap: the INDEPENDENT stack count, or the SHARED refresh `count`; below 1 counts
## as 1. A re-application's cap limits how far it can raise the count; it never lowers it.
var max_stacks: int = DEFAULT_MAX_STACKS
## INDEPENDENT only: the cap counts only stacks from the applying `source`, so each source
## builds up to its own cap (and REPLACE_OLDEST replaces only that source's stack).
var cap_per_source: bool = false
## Seconds between ticks; 0 or less, or INF, means the effect never ticks. Below
## `LFStatusEffects.MIN_TICK_INTERVAL` it is raised to that. A NaN is rejected: reported
## through `LFLogger` as an error, and the value is kept.
var tick_interval: float = DEFAULT_TICK_INTERVAL:
	set(value):
		if is_nan(value):
			_log.error('LFStatusEffectDef: a NaN tick_interval is rejected; keeping %s' % tick_interval)
			return
		tick_interval = value
## `func(owner: Variant, stack: LFStatusStack) -> void`, called once per elapsed tick of
## each stack. A stack applied with its own `on_tick` uses that one instead.
var on_tick: Callable
## `func(stack: LFStatusStack) -> float`: chooses the seconds until this stack's next tick,
## asked once when the stack is applied (for the first tick) and again each time it ticks,
## so an effect can re-roll a random interval at every fire. A result of 0 or less, INF or
## NaN (a NaN is also reported through `LFLogger`) ends the ticking of that stack; a
## positive result below `LFStatusEffects.MIN_TICK_INTERVAL` is raised to it. It needs a
## tick callback to have any effect. Precedence, strongest first: the `interval_fn` passed
## to `LFStatusEffects.apply()`, the `tick_interval` passed there, this field, then
## `tick_interval`. While it is empty (the default) the fixed `tick_interval` rules.
var interval_fn: Callable

## id -> { policy key: definition }, for `shared()`.
static var _log := LFLogger.new()
static var _shared_defs: Dictionary[StringName, Dictionary] = {}


## A definition with the given fields; every argument is optional and defaults to the
## field's default shown above (an unnamed, 1-second, single-stack effect that never ticks).
func _init(
	effect_id: StringName = &'',
	accumulation_mode: Accumulation = Accumulation.INDEPENDENT,
	effect_duration: float = DEFAULT_DURATION,
	stack_cap: int = DEFAULT_MAX_STACKS,
	overflow_mode: Overflow = Overflow.DROP,
	interval: float = DEFAULT_TICK_INTERVAL,
	tick_callback: Callable = Callable(),
) -> void:
	id = effect_id
	accumulation = accumulation_mode
	duration = effect_duration
	max_stacks = stack_cap
	overflow = overflow_mode
	tick_interval = interval
	on_tick = tick_callback


## One definition per `effect_id`, `accumulation_mode`, `overflow_mode` and `per_source`
## (the definition's `cap_per_source`), made on first use and the same object on every
## later call — for effects applied ad hoc by name, with duration, interval and cap passed
## per application (`LFStatusEffects.apply`). Its defaults are a 1-second duration, a cap
## of 1 and no tick. Every caller shares the returned object, so never change its fields;
## make your own definition for that. Main thread only (the cache is a plain static
## dictionary).
static func shared(effect_id: StringName, accumulation_mode: Accumulation, overflow_mode: Overflow, per_source: bool = false) -> LFStatusEffectDef:
	var by_policy: Dictionary = _shared_defs.get(effect_id, {})
	if by_policy.is_empty():
		_shared_defs[effect_id] = by_policy
	var policy := accumulation_mode * _ACCUMULATION_KEY_WEIGHT + overflow_mode * _OVERFLOW_KEY_WEIGHT + int(per_source)
	var def: LFStatusEffectDef = by_policy.get(policy)
	if def == null:
		def = LFStatusEffectDef.new(effect_id, accumulation_mode, DEFAULT_DURATION, DEFAULT_MAX_STACKS, overflow_mode)
		def.cap_per_source = per_source
		by_policy[policy] = def
	return def
