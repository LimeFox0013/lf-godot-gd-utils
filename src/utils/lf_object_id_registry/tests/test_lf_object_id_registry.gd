extends GutTest

signal gone

const PREFIX_OF_TESTS := 'thing'
var _registry: LFObjectIdRegistry


func before_each():
	_registry = LFObjectIdRegistry.new(PREFIX_OF_TESTS)


func test_ids_are_sequential_stable_and_map_back():
	var registry := LFObjectIdRegistry.new('item')
	var a := RefCounted.new()
	var b := RefCounted.new()

	assert_eq(registry.id_for(a), 'item-1')
	assert_eq(registry.id_for(b), 'item-2')
	assert_eq(registry.id_for(a), 'item-1', 'the same object keeps its id')
	assert_eq(registry.object_for('item-2'), b)
	assert_null(registry.object_for('item-9'))


func test_a_released_id_is_never_reused():
	var registry := LFObjectIdRegistry.new('x')
	var a := RefCounted.new()
	registry.id_for(a)

	registry.release(a)

	assert_null(registry.object_for('x-1'))
	assert_false(registry.has_object(a))
	assert_eq(registry.id_for(RefCounted.new()), 'x-2')
	assert_eq(registry.id_for(a), 'x-3', 'even the same object comes back with a new id')


func test_a_release_signal_releases_the_id_when_it_fires():
	var registry := LFObjectIdRegistry.new('x')
	var a := RefCounted.new()
	registry.id_for(a, gone)

	gone.emit()

	assert_null(registry.object_for('x-1'))
	assert_eq(gone.get_connections().size(), 0, 'one shot')


class _Owner extends RefCounted:
	signal gone


## The release hook binds the id, not the object, so an object whose own signal releases
## it isn't kept alive by that connection.
func test_the_release_hook_does_not_hold_the_object():
	var registry := LFObjectIdRegistry.new('thing')
	var owner := _Owner.new()
	var id := registry.id_for(owner, owner.gone)
	var watch: WeakRef = weakref(owner)
	registry.release_id(id)
	owner = null

	assert_null(watch.get_ref(), 'freed once nothing else holds it')
	assert_null(registry.object_for(id))


func test_an_object_freed_without_release_stays_mapped_until_released():
	var registry := LFObjectIdRegistry.new('n')
	var node := Node.new()
	var id := registry.id_for(node)
	node.free()

	assert_null(registry.object_for(id), 'a freed object maps to nothing')
	registry.release(node)
	assert_null(registry.object_for(id), 'releasing the freed object forgets its id')


func test_a_release_signal_with_arguments_releases_the_id():
	var holder := Emitter.new()
	var id := _registry.id_for(holder, holder.gone)
	holder.gone.emit(42)
	assert_null(_registry.object_for(id))
	assert_false(_registry.has_object(holder))
	holder.free()


func test_a_freed_object_is_handled_without_errors():
	var node := Node.new()
	var id := _registry.id_for(node)
	node.free()
	assert_false(_registry.has_object(node))
	assert_eq(_registry.find_id(node), '')
	_registry.release(node)
	assert_null(_registry.object_for(id))
	assert_eq(_registry.id_for(node), '')
	assert_push_error('freed')


func test_find_id_never_assigns_one():
	var node := Node.new()
	assert_eq(_registry.find_id(node), '')
	assert_false(_registry.has_object(node))
	var id := _registry.id_for(node)
	assert_eq(_registry.find_id(node), id)
	node.free()


func test_the_prefix_is_read_only():
	_registry.prefix = 'other'
	assert_push_error('read-only')
	assert_true(_registry.id_for(autofree(Node.new())).begins_with(PREFIX_OF_TESTS))


func test_a_later_release_on_for_an_object_that_already_has_an_id_is_ignored():
	var holder := Emitter.new()
	var id := _registry.id_for(holder)
	assert_eq(_registry.id_for(holder, holder.gone), id, 'the same id')
	holder.gone.emit(1)
	assert_same(_registry.object_for(id), holder, 'only the first id_for connects release_on')
	holder.free()


func test_a_stale_release_on_never_releases_a_newer_id_of_the_same_object():
	var holder := Emitter.new()
	var old_id := _registry.id_for(holder, holder.gone)
	_registry.release(holder)
	var new_id := _registry.id_for(holder)
	assert_ne(new_id, old_id)
	holder.gone.emit(1)
	assert_same(_registry.object_for(new_id), holder, 'the old one-shot only releases the old id')
	assert_eq(_registry.find_id(holder), new_id)
	holder.free()


func test_releasing_an_unknown_id_is_a_no_op():
	var a := RefCounted.new()
	var id := _registry.id_for(a)
	_registry.release_id('nope-1')
	assert_same(_registry.object_for(id), a)


class Emitter:
	extends Object
	signal gone(code: int)


func test_objects_freed_without_a_release_are_forgotten_while_ids_are_assigned():
	for i in 500:
		var node := Node.new()
		_registry.id_for(node)
		node.free()
	assert_lt(_registry._objects_by_id.size(), 100, 'freed entries are swept')
	assert_lt(_registry._ids_by_object.size(), 100)


func test_freed_objects_are_forgotten_while_other_objects_stay_registered():
	var kept := Node.new()
	_registry.id_for(kept) # alive the whole time
	for i in 1000:
		var node := Node.new()
		_registry.id_for(node)
		node.free()
	assert_true(_registry.has_object(kept))
	assert_lte(_registry._objects_by_id.size(), 1 + 32, 'at most one sweep interval of freed entries')
	assert_lte(_registry._ids_by_object.size(), 1 + 32)
	kept.free()


func test_the_sweep_interval_follows_the_live_count_after_the_last_sweep():
	var kept: Array[Node] = []
	for i in 50:
		kept.append(Node.new())
		_registry.id_for(kept[-1])
	for i in 1000:
		var node := Node.new()
		_registry.id_for(node)
		node.free()
	assert_lte(_registry._objects_by_id.size(), 50 + 50, 'the live entries plus one interval of 50')
	for node in kept:
		assert_true(_registry.has_object(node))
		node.free()


func test_releasing_a_live_object_without_an_id_is_a_no_op():
	var kept := RefCounted.new()
	var id := _registry.id_for(kept)
	_registry.release(RefCounted.new())
	assert_same(_registry.object_for(id), kept)
	assert_eq(_registry.id_for(RefCounted.new()), PREFIX_OF_TESTS + '-2', 'no id was consumed')


func test_null_gets_no_id():
	assert_eq(_registry.id_for(null), '')
	assert_push_error('freed')
	assert_eq(_registry.find_id(null), '')
	assert_false(_registry.has_object(null))


## Several units die without a release; releasing one of them by its stale reference
## forgets only that one.
func test_releasing_one_freed_object_among_others_forgets_only_it():
	var alive := Node.new()
	var dead_a := Node.new()
	var dead_b := Node.new()
	var alive_id := _registry.id_for(alive)
	var a_id := _registry.id_for(dead_a)
	var b_id := _registry.id_for(dead_b)
	dead_a.free()
	dead_b.free()

	_registry.release(dead_b)

	assert_false(_registry._objects_by_id.has(b_id), 'its entry is gone')
	assert_true(_registry._objects_by_id.has(a_id), 'the other freed entry waits for its own release or a sweep')
	assert_same(_registry.object_for(alive_id), alive)
	alive.free()


## The README's usage: a node released when it leaves the tree.
func test_a_node_released_when_it_leaves_the_tree():
	var node := Node.new()
	add_child(node)
	var id := _registry.id_for(node, node.tree_exited)
	assert_same(_registry.object_for(id), node)

	remove_child(node)

	assert_null(_registry.object_for(id))
	assert_false(_registry.has_object(node))
	assert_ne(_registry.id_for(node), id, 'coming back gives a new id')
	node.free()
