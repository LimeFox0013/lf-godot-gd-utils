## Small static helpers: timers, waiting, array queries and node chores.
##
## Never instantiated: call everything on the class, e.g. [code]await LFUtils.timeout(200)[/code].
## It covers SceneTree timers in milliseconds, a per-frame polling loop, array/resource
## merging, deep equality, deferred reparenting, clearing and syncing a container's children,
## signal disconnection, array queries and grouping (min/max/find/group/count by a key),
## the project's viewport size and a random point in a rectangle.
class_name LFUtils

## Milliseconds in one second, to turn a millisecond delay into the seconds a timer takes.
const _MS_PER_SECOND := 1000.0
## Node meta holding the ticket of the latest `move_node` request; the deferred move runs
## only for the ticket that is still current.
const _MOVE_TICKET_META := &'_lf_move_ticket'
## Project setting holding the configured viewport width, in pixels.
const _VIEWPORT_WIDTH_SETTING := "display/window/size/viewport_width"
## Project setting holding the configured viewport height, in pixels.
const _VIEWPORT_HEIGHT_SETTING := "display/window/size/viewport_height"
## Key of the callable in a dictionary `Signal.get_connections()` returns.
const _CONNECTION_CALLABLE_KEY := 'callable'
## Name of the static method `move_node` defers to apply a move.
const _APPLY_MOVE_METHOD := '_apply_move'

static var _log := LFLogger.new()


## Creates a SceneTreeTimer firing after `delay_ms` milliseconds, calls `callback` once when it
## fires, and returns the timer (await its `timeout` signal to wait for it). The timer
## always runs while the tree is paused. By default it scales with `Engine.time_scale`
## (slow motion stretches it); with `real_time` it ignores the time scale and counts
## wall-clock time. Needs a running SceneTree.
static func create_timer(delay_ms: float, callback := func() -> void: pass, real_time := false) -> SceneTreeTimer:
	var timer: SceneTreeTimer = tree_root.create_timer(delay_ms / _MS_PER_SECOND, true, false, real_time)
	timer.timeout.connect(callback, CONNECT_ONE_SHOT)
	return timer


## Coroutine (use it with `await`). Waits `delay_ms` milliseconds of game time (it follows
## `Engine.time_scale` and keeps running while paused), calling `callback` when the timer
## fires, just before the awaiting code resumes. Needs a running SceneTree.
static func timeout(delay_ms: float, callback := func() -> void: pass) -> void:
	await create_timer(delay_ms, callback).timeout


## The engine's main loop (`Engine.get_main_loop()`) — the running SceneTree in a normal
## game or a headless test run; read it rather than caching it.
static var main_loop: MainLoop:
	get(): return Engine.get_main_loop()

## The main loop as a SceneTree (null when it is not one, e.g. a custom MainLoop). Used by
## `create_timer`/`timeout`, `move_node` and `LFAwait.next_tick`; needs no node in the tree.
static var tree_root: SceneTree:
	get(): return main_loop as SceneTree


## Returns a deep copy of `target_array` with every array in `arrays` appended in order.
## The inputs are not changed; appended elements are shared, not copied.
static func merge_arrays(target_array: Array, ...arrays: Array) -> Array:
	var target := target_array.duplicate(true)
	for array: Array in arrays:
		target.append_array(array)
	return target


## Returns a deep duplicate of `target_object` with every key/value of each dictionary in
## `dictionaries` set on it, in order (a later dictionary wins a repeated key). The
## original is not changed. A key that is not a property of the resource is ignored and reported once
## per call through `LFLogger` as a warning naming it.
static func merge_resource(target_object: Resource, ...dictionaries: Array) -> Resource:
	var target := target_object.duplicate(true)
	var names := property_names(target)
	var unknown := {}
	for dictionary: Dictionary in dictionaries:
		for prop: Variant in dictionary.keys():
			if not names.has(prop):
				unknown[prop] = true
				continue
			target.set(prop, dictionary.get(prop))
	for prop: Variant in unknown:
		_log.warning('merge_resource: "%s" is not a property of %s; ignored' % [str(prop), target.get_class()])
	return target


## True when every resource in `resources` deep-equals `target` on each property named in
## `props` (a property a resource lacks reads as null); true when `resources` is empty,
## false when one of them is null or not a Resource.
static func are_resources_equal(props: Array[String], target: Resource, ...resources: Array) -> bool:
	if resources.is_empty():
		return true
	var target_props := {}
	var target_names := property_names(target)
	for prop in props:
		target_props[prop] = target.get(prop) if target_names.has(prop) else null

	for resource: Variant in resources:
		if resource == null or !(resource is Resource):
			return false
		var resource_names := property_names(resource)
		for prop in props:
			var a: Variant = target_props[prop]
			var b: Variant = resource.get(prop) if resource_names.has(prop) else null
			if !deep_equal(a, b):
				return false
	return true


## The names of every property in `resource`'s property list (its script variables and
## the built-in ones it inherits).
static func property_names(resource: Resource) -> Array[String]:
	var props: Array[String] = []
	props.assign(
		resource.get_property_list().map(
			func (prop_dict: Dictionary) -> String: return prop_dict.name,
		),
	)
	return props


## Structural equality: arrays and dictionaries compared element-wise, recursively;
## other values as `same_value` compares them (an int equals a float of the same number,
## a String equals a StringName with the same text). Unlike `==`, NaN equals NaN: in a
## float, and in a component of a Vector2/3/4, Color, Quaternion or packed float array, so
## an unchanged NaN never counts as a difference. Accepts any two values.
##
## Exact for values nested up to `DEEP_EQUAL_MAX_DEPTH` (100) Arrays/Dictionaries deep.
## Godot's own `==` is tried first at each level for speed (the element walk is far
## slower), but it gives up after about 51 nested containers, logs "Max recursion
## reached" and counts everything below as equal. So an equal answer from `==` also needs
## equal `hash()` values (which look about 101 levels deep); a pair failing either is
## walked element by element. Values nested deeper than that are not told apart by the
## first check, and the walk itself stops at `DEEP_EQUAL_MAX_DEPTH` with a pushed warning
## and answers `false`, so deep input from outside (a 1,000-level JSON document) cannot
## overflow the script stack. Comparing values nested more than about 50 levels prints
## the engine's "Max recursion reached" log lines.
static func deep_equal(a: Variant, b: Variant) -> bool:
	return _deep_equal(a, b, 0)


## How many nested Arrays/Dictionaries the element walk of `deep_equal` descends before it
## stops with a warning and answers `false`.
const DEEP_EQUAL_MAX_DEPTH := 100


## `deep_equal` at `depth` containers below the values first passed in.
static func _deep_equal(a: Variant, b: Variant, depth: int) -> bool:
	if typeof(a) != typeof(b):
		return same_value(a, b)

	match typeof(a):
		TYPE_ARRAY:
			if depth >= DEEP_EQUAL_MAX_DEPTH:
				return _too_deep()
			var aa: Array = a
			var bb: Array = b
			return _arrays_equal(aa, bb, depth)

		TYPE_DICTIONARY:
			if depth >= DEEP_EQUAL_MAX_DEPTH:
				return _too_deep()
			var da: Dictionary = a
			var db: Dictionary = b
			return _dictionaries_equal(da, db, depth)

		TYPE_FLOAT:
			var fa: float = a
			var fb: float = b
			return _floats_equal(fa, fb)

		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_QUATERNION, \
				TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			return _components_equal(a, b)

		_:
			return a == b


static func _arrays_equal(aa: Array, bb: Array, depth: int) -> bool:
	# The engine's comparison first: it is stricter (an int never equals a float
	# inside it), so when it says equal so does this; only a difference it reports
	# is checked again element by element. Its `==` stops looking after about 51
	# nested containers, so equal also needs equal hashes (hash() looks deeper); a
	# pair that fails either is walked element by element.
	if aa == bb and hash(aa) == hash(bb):
		return true
	if aa.size() != bb.size():
		return false
	for i in aa.size():
		if !_deep_equal(aa[i], bb[i], depth + 1):
			return false
	return true


static func _dictionaries_equal(da: Dictionary, db: Dictionary, depth: int) -> bool:
	if da == db and hash(da) == hash(db):
		return true
	if da.size() != db.size():
		return false
	for k: Variant in da:
		if !db.has(k) or !_deep_equal(da[k], db[k], depth + 1):
			return false
	return true


## Fixed-size float types (and packed float arrays) compared one component at a time.
static func _components_equal(a: Variant, b: Variant) -> bool:
	if a == b:
		return true
	var length: int = _COMPONENTS.get(typeof(a), -1)
	if length < 0:
		length = a.size()
		if length != b.size():
			return false
	for i in length:
		if !_floats_equal(a[i], b[i]):
			return false
	return true


## Component counts of the fixed-size float types `deep_equal` compares one component at
## a time (packed float arrays use their size).
const _COMPONENTS := {
	TYPE_VECTOR2: 2, TYPE_VECTOR3: 3, TYPE_VECTOR4: 4, TYPE_COLOR: 4, TYPE_QUATERNION: 4,
}


## Reports a comparison stopped at DEEP_EQUAL_MAX_DEPTH; answers "not equal".
static func _too_deep() -> bool:
	_log.warning('LFUtils.deep_equal: values nested more than %d levels deep; compared as different' % DEEP_EQUAL_MAX_DEPTH)
	return false


## `a == b`, except that NaN equals NaN.
static func _floats_equal(a: float, b: float) -> bool:
	return a == b or (is_nan(a) and is_nan(b))


## Coroutine. Moves `node` under `new_parent` at the end of this frame, as one deferred
## step, and returns once it has happened; `node.owner` becomes `new_parent` unless
## `set_owner` is false. If either is freed meanwhile the move does not happen (`node`
## stays where it was); when several moves of one node are requested in a
## frame, the last one wins. A no-op when `new_parent` already is the parent.
static func move_node(node: Node, new_parent: Node, set_owner := true) -> void:
	if not is_instance_valid(node) or not is_instance_valid(new_parent):
		return
	var ticket: int = node.get_meta(_MOVE_TICKET_META, 0) + 1
	node.set_meta(_MOVE_TICKET_META, ticket)
	Callable(LFUtils, _APPLY_MOVE_METHOD).call_deferred(node, new_parent, set_owner, ticket)
	await tree_root.process_frame


static func _apply_move(node: Variant, new_parent: Variant, set_owner: bool, ticket: int) -> void:
	if not is_instance_valid(node) or not is_instance_valid(new_parent):
		return
	if node.get_meta(_MOVE_TICKET_META, 0) != ticket:
		return
	node.remove_meta(_MOVE_TICKET_META)
	if node.get_parent() == new_parent:
		return
	if node == new_parent or node.is_ancestor_of(new_parent):
		_log.error('LFUtils.move_node: a node cannot be moved under itself or its own descendant; it stays where it was')
		return
	var old_parent: Node = node.get_parent()
	if old_parent:
		old_parent.remove_child(node)
	new_parent.add_child(node)
	if set_owner:
		node.owner = new_parent


## The project's configured viewport width and height (Project Settings > Display >
## Window > Size), not the live window size.
static func get_project_screen_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting(_VIEWPORT_WIDTH_SETTING)),
		float(ProjectSettings.get_setting(_VIEWPORT_HEIGHT_SETTING)),
	)


## A uniformly random point inside `rect`, edges inclusive. Draws from `rng` when given
## (reproducible with a seeded generator). A cosmetic helper: without `rng` it falls back to
## Godot's global generator (not reproducible) instead of reporting an error, unlike the
## gameplay rollers, which require one.
static func random_point_in_rect(rect: Rect2, rng: RandomNumberGenerator = null) -> Vector2:
	if rng:
		return Vector2(
			rng.randf_range(rect.position.x, rect.position.x + rect.size.x),
			rng.randf_range(rect.position.y, rect.position.y + rect.size.y),
		)
	return Vector2(
		randf_range(rect.position.x, rect.position.x + rect.size.x),
		randf_range(rect.position.y, rect.position.y + rect.size.y),
	)


## Detaches and frees every child of `parent` (or only those `filter` accepts). Detached
## first, not just `queue_free()`d: a queued child stays in `get_children()` until the end
## of the frame, so a rebuild in the same frame would otherwise sit beside stale ones.
## An empty `Callable()` means no filter; a filter that can no longer be called (its object
## was freed) frees nothing and reports an error.
static func free_children(parent: Node, filter := Callable()) -> void:
	if not filter.is_null() and not filter.is_valid():
		_log.error('LFUtils.free_children: the filter can no longer be called (its object was freed); no child was freed')
		return
	for child in parent.get_children():
		if not filter.is_null() and !filter.call(child):
			continue
		parent.remove_child(child)
		child.queue_free()


## Disconnects every connection of `sig`, or only those whose callable belongs to
## `only_object` — e.g. to drop the hooks that keep an object alive through itself.
## A signal with no connections is left as it is.
static func disconnect_all(sig: Signal, only_object: Object = null) -> void:
	for connection: Dictionary in sig.get_connections():
		var callable: Callable = connection[_CONNECTION_CALLABLE_KEY]
		if only_object == null or callable.get_object() == only_object:
			sig.disconnect(callable)


## The item with the smallest `key.call(item)` (`key` returns a number for an item), or
## null for an empty array; the first one wins a tie (so all-INF keys still return the
## first item). A NaN key never beats a number; with only NaN keys the first item wins.
static func min_by(items: Array, key: Callable) -> Variant:
	if items.is_empty():
		return null
	var best: Variant = items[0]
	var best_key: float = key.call(best)
	for i in range(1, items.size()):
		var value: float = key.call(items[i])
		if value < best_key or (is_nan(best_key) and not is_nan(value)):
			best = items[i]
			best_key = value
	return best


## The item with the largest `key.call(item)`, or null for an empty array; the first one
## wins a tie (so all-`-INF` keys still return the first item); a NaN key never beats a
## number. The mirror of `min_by`.
static func max_by(items: Array, key: Callable) -> Variant:
	if items.is_empty():
		return null
	var best: Variant = items[0]
	var best_key: float = key.call(best)
	for i in range(1, items.size()):
		var value: float = key.call(items[i])
		if value > best_key or (is_nan(best_key) and not is_nan(value)):
			best = items[i]
			best_key = value
	return best


## `{ key.call(item): [item, ...] }`: every item filed under its key. Keys appear in the
## order they are first met, and each list keeps the items' order.
static func group_by(items: Array, key: Callable) -> Dictionary:
	var groups := {}
	for item: Variant in items:
		var k: Variant = key.call(item)
		if groups.has(k):
			groups[k].append(item)
		else:
			groups[k] = [item]
	return groups


## `{ key.call(item): count }`: how many items share each key, keys in the order first met.
static func count_by(items: Array, key: Callable) -> Dictionary:
	var counts := {}
	for item: Variant in items:
		var k: Variant = key.call(item)
		counts[k] = counts.get(k, 0) + 1
	return counts


## Makes `parent` hold exactly `count` children, keeping the first ones as they are: it
## grows by calling `create.call(index)` for each missing index (a returned Node without
## a parent is added to `parent`; one `create` already added is left where it is), and
## trims the tail with `remove_child` + `queue_free`, so the count is right at once. When
## `create` adds more children than the one it was asked for, the surplus at the tail is
## trimmed too. A negative `count` is treated as zero.
static func sync_children(parent: Node, count: int, create: Callable) -> void:
	count = maxi(count, 0)
	_trim_children(parent, count)
	var index := parent.get_child_count()
	while index < count:
		var node: Variant = create.call(index)
		if is_instance_valid(node) and node is Node and node.get_parent() == null:
			parent.add_child(node)
		var grown := parent.get_child_count()
		if grown <= index:
			_log.error('LFUtils.sync_children: create did not add a child for index %d' % index)
			return
		index = grown
	_trim_children(parent, count)


## Detaches and queues for freeing the last children of `parent` until `count` are left.
static func _trim_children(parent: Node, count: int) -> void:
	while parent.get_child_count() > count:
		var extra := parent.get_child(parent.get_child_count() - 1)
		parent.remove_child(extra)
		extra.queue_free()


## Calls the method named `step` on `owner` now and then once every process frame,
## until it returns anything but the bool `true` or `owner` is freed. Holds `owner` only
## weakly between frames, so a RefCounted owner nobody else keeps is freed and the loop
## ends instead of keeping it alive. Fire and forget: no need to `await` it. Does nothing
## without a running SceneTree or with a null `owner`.
static func poll_each_frame(owner: Object, step: StringName) -> void:
	var tree := tree_root
	if tree == null or owner == null:
		return
	var ref: WeakRef = weakref(owner)
	owner = null
	while true:
		var target: Object = ref.get_ref()
		if target == null or not _is_true(target.call(step)):
			return
		target = null
		await tree.process_frame


## The first item whose `key` equals `value` — a Dictionary's entry or an Object's
## property — or null when none does (null and freed items are skipped). Compared with `same_value`: values of different types never match,
## except an int and a float of the same number, or a String and a StringName of the same text.
static func find_by(items: Array, key: Variant, value: Variant) -> Variant:
	for item: Variant in items:
		if _readable(item) and same_value(item.get(key), value):
			return item
	return null


const _NUMBER_TYPES := [TYPE_INT, TYPE_FLOAT]
const _TEXT_TYPES := [TYPE_STRING, TYPE_STRING_NAME]

## `a == b` without the type surprises: values of different types are unequal (no
## error), except an int and a float (compared as numbers) and a String and a StringName
## (compared by content — `Node.name` is a StringName).
static func same_value(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if ta == tb:
		return a == b
	if ta in _NUMBER_TYPES and tb in _NUMBER_TYPES:
		return a == b
	if ta in _TEXT_TYPES and tb in _TEXT_TYPES:
		return String(a) == String(b)
	return false


## `{ item[key]: item }` for every item — a Dictionary's entry or an Object's property;
## a later item wins a repeated key. Null and freed items are skipped.
static func index_by(items: Array, key: Variant) -> Dictionary:
	var index := {}
	for item: Variant in items:
		if _readable(item):
			index[item.get(key)] = item
	return index


## `value` is the bool `true` (comparing another type with `true` is a script error).
static func _is_true(value: Variant) -> bool:
	return value is bool and value


## A Dictionary, or an Object that is still alive. Checks the type with `typeof` rather
## than `is`, which is a script error on a freed Object.
static func _readable(item: Variant) -> bool:
	var type := typeof(item)
	return type == TYPE_DICTIONARY or (type == TYPE_OBJECT and is_instance_valid(item))


## The lower median of `values` (for an even count, the lower of the two middle values),
## or null for an empty array. Does not change `values`.
static func lower_median(values: Array) -> Variant:
	if values.is_empty():
		return null
	var sorted := values.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	return sorted[(sorted.size() - 1) / 2]
