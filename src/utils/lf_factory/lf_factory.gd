## Reuses nodes (short-lived visuals, scene instances) instead of creating and freeing them each time.
##
## A keyed node pool: each key is registered with a creation function and optional
## lifecycle hooks; `acquire` hands out a pooled entity (or a fresh one, already in the
## container) and `release` puts it back for reuse. "Entity" here means any Node it made.
##
## `acquire` is synchronous — a fresh entity is created and added to the container in the
## same call, so a node asked for this frame is in the container this frame. `acquire_async`
## awaits an async creation function and parents the entity with a deferred add plus one
## frame, for creation that must not touch the tree mid-callback. Hooks are called, never
## awaited, with the entity: `on_created` once per fresh entity (before it is parented),
## `on_acquire` on every hand-out, `on_release` on every release that pools it.
class_name LFFactory

## Fewest fresh entities created between two sweeps of the records of entities freed
## without `release` (see the README's Notes).
const _SWEEP_MIN_INTERVAL := 32

static var _log := LFLogger.new()


class _Kind:
	var key: Variant
	var create_fn: Callable
	var on_acquire: Callable
	var on_release: Callable
	var on_created: Callable
	var pool: Array[Node] = []


## Default parent of fresh entities.
var container: Node

var _kinds := {} # key -> _Kind
var _records := {} # entity -> the _Kind it was made under
var _pooled := {} # entity -> true while it sits in a pool
var _in_flight := {} # entity -> true while acquire_async parents it
# Bumped by `reset()`, so an `acquire_async` in flight across it returns nothing.
var _epoch := 0
# Fresh entities created since the last sweep of freed records (see `_sweep_if_due`).
var _created_since_sweep := 0
# How many records the last sweep left (all of them live then).
var _records_after_sweep := 0


## Sets the parent of fresh entities. Switching from a different live container reports an
## error (entities already out stay parented to the old one).
func set_container(new_container: Node) -> void:
	if is_instance_valid(container) and container != new_container:
		_log.error('LFFactory: switching containers can lead to unexpected behaviour')
	container = new_container


## Defines `key` (any value: a StringName, a String, an enum int). `create_fn` takes no
## arguments and returns a new Node (or awaits and returns one, for `acquire_async`). Each
## optional hook is called with the entity. Registering a key again replaces its
## definition: its idle pooled entities are freed, and entities handed out under the old
## definition are freed when released.
func register(key: Variant, create_fn: Callable, on_acquire: Callable = Callable(), on_release: Callable = Callable(), on_created: Callable = Callable()) -> void:
	var old: _Kind = _kinds.get(key)
	if old != null:
		for entity in old.pool:
			_records.erase(entity)
			_pooled.erase(entity)
			if is_instance_valid(entity):
				entity.queue_free()
		old.pool.clear()
	var kind := _Kind.new()
	kind.key = key
	kind.create_fn = create_fn
	kind.on_acquire = on_acquire
	kind.on_release = on_release
	kind.on_created = on_created
	_kinds[key] = kind


## Whether `key` has a registration.
func is_registered(key: Variant) -> bool:
	return _kinds.has(key)


## A live entity for `key`, from its pool or freshly created and added to the container —
## all within this call. Null (and an error) for an unknown key, no (or a freed) container, or a
## creation function that is invalid, returns no Node, or returns a Node already tracked or in the
## tree. Records of entities freed without `release`
## (say, by a one-shot animation) are dropped by a sweep that runs after max(32, records
## left by the previous sweep) fresh entities, so the records stay within twice that.
## A fresh entity that holds a physics object (an Area or a body with shapes), created from
## a physics-overlap signal such as `body_entered` (emitted while the physics server
## flushes its queries), makes Godot report "Can't change this state while flushing
## queries"; call `acquire_async`, or `acquire` through `call_deferred`, there. The same
## goes while the container is busy setting up children.
func acquire(key: Variant) -> Node:
	var kind := _kind_or_report(key)
	if kind == null:
		return null
	var entity := _pop_live(kind)
	if entity == null:
		if not is_instance_valid(container):
			_log.error('LFFactory has no container to create "%s" in; call set_container()' % [key])
			return null
		if not kind.create_fn.is_valid():
			_log.error('LFFactory: the creation function for "%s" is not valid (empty, or its object was freed)' % [key])
			return null
		var created: Variant = kind.create_fn.call()
		if not _is_fresh_node(created, key):
			return null
		entity = created
		if kind.on_created.is_valid():
			kind.on_created.call(entity)
		container.add_child(entity)
		_sweep_if_due()
		_records[entity] = kind
	_hand_out(kind, entity)
	return entity


## Coroutine. Like `acquire`, but awaits the creation function and parents a fresh entity
## with a deferred add plus one frame. Returns null (freeing the entity) if `reset()`, a
## re-register or the container being freed happened meanwhile.
func acquire_async(key: Variant) -> Node:
	var kind := _kind_or_report(key)
	if kind == null:
		return null
	var entity := _pop_live(kind)
	if entity == null:
		if not is_instance_valid(container):
			_log.error('LFFactory has no container to create "%s" in; call set_container()' % [key])
			return null
		if not kind.create_fn.is_valid():
			_log.error('LFFactory: the creation function for "%s" is not valid (empty, or its object was freed)' % [key])
			return null
		var epoch := _epoch
		var created: Variant = await kind.create_fn.call()
		if not _is_fresh_node(created, key):
			return null
		entity = created
		if epoch != _epoch or not is_instance_valid(container):
			entity.queue_free()
			return null
		_in_flight[entity] = true
		if kind.on_created.is_valid():
			kind.on_created.call(entity)
		_add_if_alive.call_deferred(container.get_instance_id(), entity.get_instance_id())
		await LFUtils.tree_root.process_frame
		_in_flight.erase(entity)
		if epoch != _epoch or _kinds.get(key) != kind or not is_instance_valid(entity) \
				or entity.get_parent() == null:
			# No parent: the container was freed before the deferred add ran.
			if is_instance_valid(entity):
				entity.queue_free()
			return null
		_sweep_if_due()
		_records[entity] = kind
	_hand_out(kind, entity)
	return entity


## The deferred half of `acquire_async`: parents the entity unless it or the container was
## freed since. Ids, not objects, cross the deferral: a freed object passed as an argument
## can be read back as a stale pointer on some platforms.
func _add_if_alive(container_id: int, entity_id: int) -> void:
	var target := instance_from_id(container_id) as Node
	var entity := instance_from_id(entity_id) as Node
	if target != null and entity != null and entity.get_parent() == null:
		target.add_child(entity)


## Puts `entity` (a Node, or any value — a stranger is refused) back into its key's pool and
## returns true. False — and nothing else happens — for an entity this factory doesn't
## track, one already pooled or still being parented, or one that was freed (forgotten).
## An entity whose key was re-registered is freed instead of pooled, and returns false, as is
## one that `on_release` freed or queued for deletion.
func release(entity: Variant) -> bool:
	if not is_instance_valid(entity):
		_records.erase(entity)
		_pooled.erase(entity)
		return false
	if not _records.has(entity) or _pooled.has(entity) or _in_flight.has(entity):
		return false
	var kind: _Kind = _records[entity]
	if _kinds.get(kind.key) != kind:
		_records.erase(entity)
		entity.queue_free()
		return false
	_pooled[entity] = true
	if kind.on_release.is_valid():
		kind.on_release.call(entity)
	if not _is_alive(entity):
		_records.erase(entity)
		_pooled.erase(entity)
		return false
	kind.pool.append(entity)
	return true


## Releases every entity that is handed out.
func release_all() -> void:
	for entity: Variant in _records.keys():
		if not _pooled.has(entity):
			release(entity)


## Frees every tracked entity (handed out, pooled or in flight), empties the pools and
## forgets the container; registrations stay.
func reset() -> void:
	for entity: Variant in _records.keys() + _in_flight.keys():
		if is_instance_valid(entity):
			entity.queue_free()
	for kind: _Kind in _kinds.values():
		kind.pool.clear()
	_records.clear()
	_pooled.clear()
	_in_flight.clear()
	_epoch += 1
	container = null


## Idle entities waiting in `key`'s pool; 0 for an unknown key. Entities freed elsewhere
## are dropped, not counted. Each call sweeps every record and every pool, so its cost
## grows with the number of records (all keys): not for a per-frame loop over a big pool.
func pooled_count(key: Variant) -> int:
	_forget_freed()
	var kind: _Kind = _kinds.get(key)
	return kind.pool.size() if kind != null else 0


## Entities tracked (handed out or pooled) for `key`, or for every key when `key` is null.
## Entities still being parented by `acquire_async`, and entities freed elsewhere, are not
## counted. Like `pooled_count`, each call sweeps every record, so its cost grows with the
## number of records.
func tracked_count(key: Variant = null) -> int:
	_forget_freed()
	if key == null:
		return _records.size()
	var count := 0
	for kind: _Kind in _records.values():
		if kind.key == key:
			count += 1
	return count


## Whether `entity` is live and sitting in a pool. Safe on a freed entity.
func is_pooled(entity: Variant) -> bool:
	return is_instance_valid(entity) and _pooled.has(entity)


## Whether `entity` is live and tracked here (handed out or pooled; not one still being
## parented by `acquire_async`). Safe on a freed entity.
func owns(entity: Variant) -> bool:
	return is_instance_valid(entity) and _records.has(entity)


func _kind_or_report(key: Variant) -> _Kind:
	var kind: _Kind = _kinds.get(key)
	if kind == null:
		_log.error('LFFactory has no registration for key "%s"' % [key])
	return kind


# Sweeps freed records once max(32, records left by the last sweep) fresh entities were
# created since it. A sweep costs O(records), which is at most twice that interval, so the
# cost is O(1) per creation on average; and the records never exceed the records left by
# the last sweep plus one interval.
func _sweep_if_due() -> void:
	_created_since_sweep += 1
	if _created_since_sweep >= maxi(_records_after_sweep, _SWEEP_MIN_INTERVAL):
		_forget_freed()


# Drops every entity that was freed without going through `release` or `reset`.
func _forget_freed() -> void:
	_created_since_sweep = 0
	for entity: Variant in _records.keys():
		if not is_instance_valid(entity):
			_records.erase(entity)
			_pooled.erase(entity)
	for kind: _Kind in _kinds.values():
		kind.pool = kind.pool.filter(is_instance_valid)
	_records_after_sweep = _records.size()


func _pop_live(kind: _Kind) -> Node:
	while not kind.pool.is_empty():
		var entity: Variant = kind.pool.pop_back()
		_pooled.erase(entity)
		if _is_alive(entity):
			return entity
		_records.erase(entity)
	return null


# Whether a creation function's result can become a new entity: a Node nobody tracks and
# nothing has parented.
func _is_fresh_node(created: Variant, key: Variant) -> bool:
	if not created is Node:
		_log.error('LFFactory: the creation function for "%s" returned no Node' % [key])
		return false
	if _records.has(created) or _in_flight.has(created) or created.get_parent() != null:
		_log.error('LFFactory: the creation function for "%s" returned a Node that is already tracked or in the tree' % [key])
		return false
	return true


# A live entity not waiting for deletion.
func _is_alive(entity: Variant) -> bool:
	return is_instance_valid(entity) and not entity.is_queued_for_deletion()


func _hand_out(kind: _Kind, entity: Node) -> void:
	if kind.on_acquire.is_valid():
		kind.on_acquire.call(entity)
