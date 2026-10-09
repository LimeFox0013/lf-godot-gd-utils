## Holds the timed status effects (timed modifiers, periodic effects) active on one owner, such as one object.
##
## Keep one per owner and call `tick()` from the owner's own update loop. Stacks store
## absolute times on this container's own clock and the container keeps a lower bound on
## its next due event (an expiry or a tick), so a frame where nothing is due does a few
## constant-time checks — no per-stack work, no nodes or timers, and no arrays,
## dictionaries or objects created. A frame where something is due walks every active
## effect id. `has`, `count` and `remaining` are dictionary lookups.
##
## Effects are keyed by `LFStatusEffectDef.id`; one owner holds at most one definition
## per id (the first one applied governs until the effect fully expires or is removed).
## Bounds on the next due time may be stale-early after a removal; that costs at most one
## extra pass, which recomputes them.
class_name LFStatusEffects

## Fired whenever an effect is applied, refreshed, replaced, expires, or is removed.
signal changed(id: StringName)

static var _log := LFLogger.new()

## Default `duration` of `apply`, in seconds: negative uses the definition's.
const DEFAULT_DURATION := -1.0
## Default `tick_interval` of `apply`, in seconds: negative uses the definition's.
const DEFAULT_TICK_INTERVAL := -1.0
## Default `max_stacks` of `apply`: 0 uses the definition's cap.
const DEFAULT_MAX_STACKS := 0
## The shortest interval between a stack's ticks, in seconds: a shorter positive interval
## is raised to this (an interval far below the clock's precision would loop forever).
const MIN_TICK_INTERVAL := 0.001

var _now := 0.0
var _next_event_at := INF
var _entries: Dictionary = {}
## Bumped by `clear()` so an in-progress tick notices it was wiped by a callback.
var _epoch := 0
## Shared empty list of ids, never written to: a due pass builds a list of changed or of
## emptied ids only when it has one to hold.
static var _NO_IDS: Array[StringName] = []
## Shared stand-in for "no stack expired" in a due pass; never written to.
static var _NO_STACKS: Array[LFStatusStack] = []


class _Entry:
	var def: LFStatusEffectDef
	## Sorted by `expires_at`, soonest first.
	var stacks: Array[LFStatusStack] = []
	## Lower bound on this entry's next expiry or tick.
	var next_event_at := INF
	## Lower bound on this entry's next tick (INF when no stack ticks). Lets a pass that
	## only has expiries due skip the tick walk entirely.
	var next_tick_at := INF
	## Set by `remove()`, so a tick walk in progress over this entry stops.
	var removed := false

	func _init(effect_def: LFStatusEffectDef) -> void:
		def = effect_def


## Applies `def` once and returns the effect's resulting `count()`. Negative `duration`
## and `tick_interval`, and a `max_stacks` of 0, mean "use the definition's value".
##
## While an effect is active, the definition it was first applied with governs it (its
## accumulation, overflow, defaults and callback); a later `def` with the same id only
## names it. `duration` (>= 0), `tick_interval` (>= 0) and `max_stacks` (> 0) override the
## governing definition for this application; a zero duration expires on the next tick,
## a zero interval never ticks. A stack ticks only when its interval is positive and
## finite and a callback exists (`on_tick` here, or the definition's); an interval below
## `MIN_TICK_INTERVAL` is raised to it. An INF duration
## lasts until `remove()` or `clear()`. A NaN duration or tick interval passed here is
## rejected: reported through `LFLogger` as an error, nothing is applied and 0 is returned
## (a NaN in a definition is rejected when it is set).
##
## A re-application never lowers the count. Its cap only limits how far it can raise it:
## - SHARED: below the cap the count rises by one; either way the expiry is refreshed
##   (never moved earlier) and `data` replaced.
## - INDEPENDENT at or above the cap: DROP ignores the application (no `changed`);
##   REPLACE_OLDEST removes exactly one stack, the soonest-expiring, to make room.
##
## `source` is recorded on the stack. With `cap_per_source` on the definition, an
## INDEPENDENT application's cap (and its replacement) counts only stacks from the same
## `source`; `count()` stays the total. A null `def` is reported and applies nothing
## (returns 0).
func apply(
	def: LFStatusEffectDef,
	duration := DEFAULT_DURATION,
	tick_interval := DEFAULT_TICK_INTERVAL,
	max_stacks := DEFAULT_MAX_STACKS,
	on_tick := Callable(),
	data: Variant = null,
	source: Variant = null,
) -> int:
	if def == null:
		_log.error("LFStatusEffects.apply: def is null; nothing applied")
		return 0
	if is_nan(duration) or is_nan(tick_interval):
		_log.error("LFStatusEffects.apply: a NaN %s is rejected; nothing applied" % ("duration" if is_nan(duration) else "tick interval"))
		return 0
	var entry: _Entry = _entries.get(def.id)
	var governing: LFStatusEffectDef = entry.def if entry else def
	var lifetime := duration if duration >= 0.0 else governing.duration
	var cap := maxi(max_stacks if max_stacks > 0 else governing.max_stacks, 1)

	if entry and governing.accumulation == LFStatusEffectDef.Accumulation.SHARED:
		var shared := entry.stacks[0]
		shared.expires_at = maxf(shared.expires_at, _now + lifetime)
		if shared.count < cap:
			shared.count += 1
		shared.data = data
		changed.emit(def.id)
		return shared.count

	if entry:
		var per_source := governing.cap_per_source
		var held := _count_from(entry, source) if per_source else entry.stacks.size()
		if held >= cap:
			if governing.overflow == LFStatusEffectDef.Overflow.DROP:
				return entry.stacks.size()
			_evict_soonest(entry, source, per_source)
	else:
		entry = _Entry.new(def)
		_entries[def.id] = entry

	var interval := tick_interval if tick_interval >= 0.0 else governing.tick_interval
	var ticks := is_finite(interval) and interval > 0.0 and (on_tick.is_valid() or governing.on_tick.is_valid())
	if !ticks:
		interval = 0.0
	else:
		interval = maxf(interval, MIN_TICK_INTERVAL)
	var next_tick_at := _now + interval if ticks else INF
	var stack := LFStatusStack.new(_now + lifetime, interval, next_tick_at, data, on_tick)
	stack.source = source
	var at := entry.stacks.bsearch_custom(stack, _expires_before, false)
	entry.stacks.insert(at, stack)

	var due := minf(stack.expires_at, next_tick_at)
	entry.next_event_at = minf(entry.next_event_at, due)
	entry.next_tick_at = minf(entry.next_tick_at, next_tick_at)
	_next_event_at = minf(_next_event_at, due)
	changed.emit(def.id)
	return entry.stacks.size()


## Advances this owner's clock by `delta`, dropping every stack that expired, then firing
## every tick that fell due (an expired stack's last ones, up to its expiry, included), so
## no callback finds an expired stack among the active ones; call it once per frame from
## the owner's update. A negative or non-finite `delta` is ignored. `owner` is handed to
## every `on_tick` — passed per call rather than stored, so an owner holding this
## container never forms a reference cycle with it.
func tick(delta: float, owner: Variant = null) -> void:
	if _entries.is_empty() or !is_finite(delta) or delta < 0.0:
		return
	_now += delta
	if _now < _next_event_at:
		return
	_process_due(owner)


## Whether an effect with `id` is currently active.
func has(id: StringName) -> bool:
	return !_entries.is_empty() and _entries.has(id)


## Number of INDEPENDENT stacks, or the refresh count of a SHARED effect; 0 if inactive.
func count(id: StringName) -> int:
	if _entries.is_empty():
		return 0
	var entry: _Entry = _entries.get(id)
	if !entry:
		return 0
	if entry.def.accumulation == LFStatusEffectDef.Accumulation.SHARED:
		return entry.stacks[0].count
	return entry.stacks.size()


## Seconds until the longest-lasting stack of `id` expires; 0 if inactive.
func remaining(id: StringName) -> float:
	if _entries.is_empty():
		return 0.0
	var entry: _Entry = _entries.get(id)
	if !entry:
		return 0.0
	return maxf(entry.stacks.back().expires_at - _now, 0.0)


## The live stacks of `id`, soonest-expiring first. Read-only — never mutate it.
func stacks(id: StringName) -> Array[LFStatusStack]:
	var entry: _Entry = _entries.get(id)
	if !entry:
		var none: Array[LFStatusStack] = []
		return none
	return entry.stacks


## Ids of every currently active effect.
func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_entries.keys())
	return result


## Whether no effect is active.
func is_empty() -> bool:
	return _entries.is_empty()


## This container's clock — every stack's `expires_at`/`next_tick_at` is on it. It only
## advances while at least one effect is active (an empty container's `tick()` returns
## before touching it), so it is not wall time.
func now() -> float:
	return _now


## Removes every stack of `id`; emits `changed` if it was active.
func remove(id: StringName) -> void:
	var entry: _Entry = _entries.get(id)
	if !entry:
		return
	for stack in entry.stacks:
		stack._removed = true
	entry.removed = true
	_entries.erase(id)
	changed.emit(id)


## Removes every effect, emitting `changed` per removed id; safe to call from `on_tick`.
func clear() -> void:
	var removed := _entries.keys()
	_entries.clear()
	_next_event_at = INF
	_epoch += 1
	for id: Variant in removed:
		changed.emit(id)


# One pass over everything due, in two phases. First every due entry's expired stacks are
# detached (an entry left without stacks stops being active), so no tick callback can see
# or revive a stack that is already over: re-applying such an effect starts it afresh and
# caps count only live stacks. Then the due ticks fire, the expired stacks' last ones
# (those at or before their expiry) included.
func _process_due(owner: Variant) -> void:
	var epoch := _epoch
	var changed_ids: Array[StringName] = _NO_IDS
	var due_entries: Array[_Entry] = []
	var expired_stacks: Array = [] # per due entry: its detached Array[LFStatusStack]
	var emptied: Array[StringName] = _NO_IDS # entries left without stacks, erased after the walk
	for id: StringName in _entries:
		var entry: _Entry = _entries[id]
		if entry.next_event_at > _now:
			continue
		var expired: Array[LFStatusStack] = _NO_STACKS
		while !entry.stacks.is_empty() and entry.stacks[0].expires_at <= _now:
			if is_same(expired, _NO_STACKS):
				expired = []
			expired.append(entry.stacks.pop_front())
		if entry.stacks.is_empty():
			if is_same(emptied, _NO_IDS):
				emptied = []
			emptied.append(id)
		if !expired.is_empty():
			if is_same(changed_ids, _NO_IDS):
				changed_ids = []
			changed_ids.append(id)
		due_entries.append(entry)
		expired_stacks.append(expired)
	for id in emptied:
		_entries.erase(id)

	for i in due_entries.size():
		var entry := due_entries[i]
		var expired: Array[LFStatusStack] = expired_stacks[i]
		_fire_due_ticks(entry, expired, owner)
		if _epoch != epoch:
			# A callback cleared the owner (clear() already reset the due time and announced
			# what it removed); still announce what expired earlier in this pass.
			for changed_id in changed_ids:
				changed.emit(changed_id)
			return
		for stack in expired:
			stack._removed = true
		if !entry.removed and !entry.stacks.is_empty() and _entries.get(entry.def.id) == entry:
			_recompute_bounds(entry)

	_next_event_at = INF
	for id: StringName in _entries:
		_next_event_at = minf(_next_event_at, (_entries[id] as _Entry).next_event_at)
	for id in changed_ids:
		changed.emit(id)


## Fires the elapsed ticks of `entry`'s stacks, `expired` (already detached) first, each
## never past its own expiry. Iterates a snapshot so a callback applying or removing
## effects on this owner can't corrupt the walk; a stack removed meanwhile is marked and
## skipped. Stops at a `clear()` or a `remove()` of this effect, also one made by another
## effect's callback earlier in the pass (the expired stacks are not marked by it).
func _fire_due_ticks(entry: _Entry, expired: Array[LFStatusStack], owner: Variant) -> void:
	if entry.next_tick_at > _now or entry.removed:
		return
	var epoch := _epoch
	for stack in expired + entry.stacks:
		if stack._removed:
			continue
		var callback: Callable = stack.on_tick if stack.on_tick.is_valid() else entry.def.on_tick
		while stack.next_tick_at <= _now and stack.next_tick_at <= stack.expires_at:
			stack.next_tick_at += stack.tick_interval
			if callback.is_valid():
				callback.call(owner, stack)
			if _epoch != epoch or entry.removed:
				return
			# The callback may have evicted this stack (e.g. a REPLACE_OLDEST re-apply).
			if stack._removed:
				break


## Recomputes `entry`'s due-time bounds from its stacks.
func _recompute_bounds(entry: _Entry) -> void:
	var next_tick := INF
	for stack in entry.stacks:
		next_tick = minf(next_tick, stack.next_tick_at)
	entry.next_tick_at = next_tick
	entry.next_event_at = minf(entry.stacks[0].expires_at, next_tick)


## How many of `entry`'s stacks came from `source`.
func _count_from(entry: _Entry, source: Variant) -> int:
	var held := 0
	for stack in entry.stacks:
		if _same_source(stack.source, source):
			held += 1
	return held


## Removes `entry`'s soonest-expiring stack (from `source` only, when `per_source`).
func _evict_soonest(entry: _Entry, source: Variant, per_source: bool) -> void:
	for i in entry.stacks.size():
		if !per_source or _same_source(entry.stacks[i].source, source):
			entry.stacks[i]._removed = true
			entry.stacks.remove_at(i)
			return


## Sources of different types never match (and never raise a comparison error).
static func _same_source(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


## Orders stacks by expiry — a method, not a lambda built on every `apply`.
static func _expires_before(a: LFStatusStack, b: LFStatusStack) -> bool:
	return a.expires_at < b.expires_at
