## Groups [LFProc]s under trigger names (like `&"on_enter"` or `&"on_exit"`) and fires them all when that moment happens.
##
## Register procs under any key you choose, then call `fire(key, rng, context)` from your
## code when the moment happens; the procs under it run in the order they were
## added, rolling on the generator you pass. Firing a key costs one lookup plus the procs
## under it, and creates no arrays, dictionaries or objects of its own (the procs'
## conditions, chance getters and actions may, and so does an error report). Adding,
## removing or clearing during a fire is safe and takes effect from the next fire.
##
## Keys are Dictionary keys: `1` and `1.0` are different keys, while a String and a
## StringName with the same text (`"on_enter"`, `&"on_enter"`) are the same key.
class_name LFTriggerSet

static var _log := LFLogger.new()


var _buckets: Dictionary = {} # key -> Array[LFProc]
# How many fires are walking a bucket right now; a change then copies the bucket first.
var _firing := 0


## Registers `proc` under `key`, after the ones already there. The same proc twice under
## one key is registered once; a null key or a null proc is reported as an error and
## stores nothing.
func add(key: Variant, proc: LFProc) -> void:
	if key == null:
		_log.error("LFTriggerSet: a trigger key can't be null")
		return
	if proc == null:
		_log.error("LFTriggerSet: a null proc can't be registered")
		return
	var bucket: Variant = _buckets.get(key)
	if bucket == null:
		var fresh: Array[LFProc] = [proc]
		_buckets[key] = fresh
		return
	if bucket.has(proc):
		return
	_mutable(key, bucket).append(proc)


## Unregisters `proc` from `key` and returns true; false if it wasn't there. A key left
## with no procs is dropped (`has(key)` turns false).
func remove(key: Variant, proc: LFProc) -> bool:
	var bucket: Variant = _buckets.get(key)
	if bucket == null or !bucket.has(proc):
		return false
	var list := _mutable(key, bucket)
	list.erase(proc)
	if list.is_empty():
		_buckets.erase(key)
	return true


## Whether any proc is registered under `key`.
func has(key: Variant) -> bool:
	return _buckets.has(key)


## How many procs are registered under `key`.
func count(key: Variant) -> int:
	var bucket: Variant = _buckets.get(key)
	return bucket.size() if bucket != null else 0


## A copy of the procs under `key`, in firing order (empty when none) — for inspection,
## not hot paths. Changing the copy changes nothing here.
func procs_for(key: Variant) -> Array[LFProc]:
	var bucket: Variant = _buckets.get(key)
	var copy: Array[LFProc] = []
	if bucket != null:
		copy.assign(bucket)
	return copy


## Unregisters every proc under every key.
func clear() -> void:
	_buckets = {}


## Fires every proc under `key` with `context`, in registration order, rolling chances
## on `rng` (any `RandomNumberGenerator`, `LFRandom` included). Returns how many fired (0 for a key with no procs).
func fire(key: Variant, rng: RandomNumberGenerator, context: Variant = null) -> int:
	var bucket: Variant = _buckets.get(key)
	if bucket == null:
		return 0
	var fired := 0
	_firing += 1
	for proc: LFProc in bucket:
		if proc.fire(rng, context):
			fired += 1
	_firing -= 1
	return fired


## Fires the procs under `key` in order until one fires and its action returns exactly
## `true` (a truthy non-bool such as `1` does not count); later procs are not checked (no
## rolls). A proc whose action is not valid is skipped without checking its gates. Returns
## true when one handled it. For "first one wins" reactions, such as
## several handlers of one moment where only one should apply.
func fire_until_handled(key: Variant, rng: RandomNumberGenerator, context: Variant = null) -> bool:
	var bucket: Variant = _buckets.get(key)
	if bucket == null:
		return false
	_firing += 1
	for proc: LFProc in bucket:
		if !proc.action.is_valid() or !proc.check(rng, context):
			continue
		# Compared by type first: `==` between an int and a bool is a script error.
		var result: Variant = proc.action.call(context)
		if typeof(result) == TYPE_BOOL and result:
			_firing -= 1
			return true
	_firing -= 1
	return false


## The bucket to change: while a fire walks it, a copy replaces it first.
func _mutable(key: Variant, bucket: Array[LFProc]) -> Array[LFProc]:
	if _firing == 0:
		return bucket
	var copy: Array[LFProc] = bucket.duplicate()
	_buckets[key] = copy
	return copy
