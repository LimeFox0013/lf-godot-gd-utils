## Keeps a window of numbered chunks alive along a line: the ones around the one you are in.
##
## For an endless level built from equal pieces (a tower, a road, a corridor). Tell it which chunk
## the player is in with `focus(index)`; it builds the missing chunks from `behind` before to
## `ahead` after that index and removes the ones outside, through two callables you give it, so
## it works with any nodes and any pooling (`LFFactory` fits). It never touches a node itself.
class_name LFChunkStream
extends RefCounted

## The number of chunks kept in front of the focused one when none is given.
const DEFAULT_AHEAD := 3
## The number of chunks kept behind the focused one when none is given.
const DEFAULT_BEHIND := 3
## The size of "no limit" for `min_index` and `max_index`.
const UNBOUNDED := 1 << 62

## Emitted after a chunk was built and is tracked.
signal chunk_spawned(index: int, chunk: Variant)
## Emitted after a chunk was removed, once the despawn callable returned.
signal chunk_despawned(index: int, chunk: Variant)

static var _log := LFLogger.new()

## Builds the chunk for an index: `func(index: int) -> Variant`. Returns the chunk (anything but null).
var spawn_fn: Callable
## Removes a chunk that left the window: `func(index: int, chunk: Variant) -> void`.
var despawn_fn: Callable
## How many chunks after the focused one are kept (0 or more).
var ahead: int:
	set(value):
		ahead = maxi(value, 0)
## How many chunks before the focused one are kept (0 or more).
var behind: int:
	set(value):
		behind = maxi(value, 0)
## The first index that may exist; a window never reaches below it.
var min_index := -UNBOUNDED
## The last index that may exist; a window never reaches above it.
var max_index := UNBOUNDED

var _chunks := {} # index -> chunk
var _focused: Variant = null
var _busy := false
var _pending: Variant = null


## A stream that builds with `initial_spawn` and removes with `initial_despawn` (see `spawn_fn` and `despawn_fn`)
## and keeps `initial_ahead` chunks in front and `initial_behind` behind. Builds nothing until `focus`.
func _init(initial_spawn: Callable, initial_despawn: Callable, initial_ahead := DEFAULT_AHEAD, initial_behind := DEFAULT_BEHIND) -> void:
	spawn_fn = initial_spawn
	despawn_fn = initial_despawn
	ahead = initial_ahead
	behind = initial_behind


## Moves the window to `index`: removes the tracked chunks outside it (lowest first), then builds the
## missing ones inside it (lowest first, so a chunk can be placed after its neighbour). An index
## outside `min_index`..`max_index` is clamped to it; if `min_index` is above `max_index` the range
## is empty: the error is reported, every chunk is removed, nothing is built and the focus is forgotten. A `spawn_fn` that returns null is reported
## and that index stays empty. A `focus` called from inside `spawn_fn` or `despawn_fn` waits for the
## running one to finish, then runs; only the last such call counts.
func focus(index: int) -> void:
	if _busy:
		_pending = index
		return
	_busy = true
	var target := index
	while true:
		_pending = null
		_apply(clampi(target, min_index, max_index))
		if _pending == null:
			break
		target = _pending
	_busy = false


## The index last passed to `focus`, clamped; null before the first `focus`.
func focused_index() -> Variant:
	return _focused


## The chunk at `index`; null when there is none.
func chunk_at(index: int) -> Variant:
	return _chunks.get(index)


## Whether a chunk is tracked at `index`.
func has_chunk(index: int) -> bool:
	return _chunks.has(index)


## The index `chunk` was built for; null when it isn't tracked.
func index_of(chunk: Variant) -> Variant:
	return _chunks.find_key(chunk)


## The tracked indices, lowest first.
func indices() -> Array[int]:
	var result: Array[int] = []
	result.assign(_chunks.keys())
	result.sort()
	return result


## How many chunks are tracked.
func count() -> int:
	return _chunks.size()


## Removes every tracked chunk (lowest first) and forgets the focus. A `focus` called from inside
## `despawn_fn` while it clears is dropped. Called from inside `spawn_fn` or `despawn_fn` of a
## running `focus`, it is reported and does nothing.
func clear() -> void:
	if _busy:
		_log.error("LFChunkStream: clear() was called from inside spawn_fn or despawn_fn; ignored")
		return
	_busy = true
	for index in indices():
		_remove(index)
	_focused = null
	_pending = null
	_busy = false


func _apply(index: int) -> void:
	if min_index > max_index:
		_log.error("LFChunkStream: min_index %d is above max_index %d; the range is empty, no chunks are kept" % [min_index, max_index])
		for tracked in indices():
			_remove(tracked)
		_focused = null
		return
	_focused = index
	var first := maxi(index - behind, min_index)
	var last := mini(index + ahead, max_index)
	for tracked in indices():
		if tracked < first or tracked > last:
			_remove(tracked)
	for wanted in range(first, last + 1):
		if !_chunks.has(wanted):
			_spawn(wanted)


func _spawn(index: int) -> void:
	if !spawn_fn.is_valid():
		_log.error("LFChunkStream: spawn_fn can no longer be called; chunk %d is not built" % index)
		return
	var chunk: Variant = spawn_fn.call(index)
	if chunk == null:
		_log.error("LFChunkStream: spawn_fn returned null for chunk %d" % index)
		return
	_chunks[index] = chunk
	chunk_spawned.emit(index, chunk)


func _remove(index: int) -> void:
	var chunk: Variant = _chunks[index]
	_chunks.erase(index)
	if despawn_fn.is_valid():
		despawn_fn.call(index, chunk)
	chunk_despawned.emit(index, chunk)
