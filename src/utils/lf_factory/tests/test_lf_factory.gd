extends GutTest

var factory: LFFactory
var container: Node
var log: Array


func before_each():
	container = Node.new()
	add_child_autofree(container)
	factory = LFFactory.new()
	factory.set_container(container)
	log = []


func _node() -> Node:
	return Node.new()


func _tagged(tag: String) -> Callable:
	return func(): var n := Node.new(); n.name = tag; return n


func test_acquire_creates_from_its_keys_function_inside_the_container_at_once():
	factory.register('a', _tagged('A'))
	var entity := factory.acquire('a')
	assert_eq(entity.name, 'A')
	assert_eq(entity.get_parent(), container, 'parented within the call')


func test_keys_never_share_pools():
	factory.register('a', _tagged('A'))
	factory.register('b', _tagged('B'))
	factory.release(factory.acquire('a'))
	assert_eq(factory.acquire('b').name, 'B')


func test_a_released_entity_is_reused():
	factory.register('a', _node)
	var first := factory.acquire('a')
	assert_true(factory.release(first))
	assert_true(factory.is_pooled(first))
	assert_same(factory.acquire('a'), first)
	assert_eq(factory.tracked_count('a'), 1)


func test_an_empty_pool_creates_fresh():
	factory.register('a', _node)
	var first := factory.acquire('a')
	assert_ne(factory.acquire('a'), first)
	assert_eq(factory.tracked_count(), 2)


func test_acquire_async_awaits_the_creation_function_and_parents_it():
	factory.register('a', func():
		await get_tree().process_frame
		return Node.new())
	var entity := await factory.acquire_async('a')
	assert_eq(entity.get_parent(), container)


func test_releasing_twice_pools_once():
	factory.register('a', _node)
	var entity := factory.acquire('a')
	assert_true(factory.release(entity))
	assert_false(factory.release(entity))
	assert_eq(factory.pooled_count('a'), 1)
	assert_ne(factory.acquire('a'), factory.acquire('a'), 'never handed out twice')


func test_a_release_from_inside_the_release_hook_changes_nothing():
	var entity: Node
	factory.register('a', _node, Callable(), func(e): factory.release(e))
	entity = factory.acquire('a')
	factory.release(entity)
	assert_eq(factory.pooled_count('a'), 1)


func test_releasing_an_untracked_or_freed_entity_is_a_no_op():
	factory.register('a', _node)
	var stranger := Node.new()
	assert_false(factory.release(stranger))
	stranger.free()
	var entity := factory.acquire('a')
	entity.free()
	assert_false(factory.release(entity))
	assert_eq(factory.tracked_count(), 0, 'forgotten')


func test_release_all_pools_everything_handed_out():
	factory.register('a', _node)
	factory.acquire('a')
	factory.acquire('a')
	factory.release_all()
	assert_eq(factory.pooled_count('a'), 2)


func test_a_pooled_entity_freed_meanwhile_is_skipped():
	factory.register('a', _node)
	var entity := factory.acquire('a')
	factory.release(entity)
	entity.free()
	var next := factory.acquire('a')
	assert_true(is_instance_valid(next))
	assert_eq(factory.tracked_count('a'), 1)


func test_a_fresh_entity_gets_created_then_acquire_and_a_reused_one_only_acquire():
	factory.register('a', _node,
		func(_e): log.append('acquire'),
		func(_e): log.append('release'),
		func(e): log.append('created %s' % (e.get_parent() == null)))
	var entity := factory.acquire('a')
	factory.release(entity)
	factory.acquire('a')
	assert_eq(log, ['created true', 'acquire', 'release', 'acquire'])


func test_an_unknown_key_reports_and_returns_null():
	assert_null(factory.acquire('nope'))
	assert_push_error('no registration')


func test_no_container_reports_and_returns_null():
	factory.register('a', _node)
	factory.reset()
	assert_null(factory.acquire('a'))
	assert_push_error('no container')


func test_a_creation_function_returning_no_node_reports_and_tracks_nothing():
	factory.register('a', func(): return null)
	assert_null(factory.acquire('a'))
	assert_push_error('returned no Node')
	assert_eq(factory.tracked_count(), 0)


func test_switching_containers_reports_and_still_switches():
	factory.register('a', _node)
	var before := factory.acquire('a')
	var other: Node = add_child_autofree(Node.new())

	factory.set_container(other)

	assert_push_error('switching containers')
	assert_eq(factory.container, other, 'the switch happens despite the report')
	assert_eq(factory.acquire('a').get_parent(), other, 'fresh entities go to the new container')
	assert_eq(before.get_parent(), container, 'an entity already out stays where it was')


func test_setting_the_same_container_again_reports_nothing():
	factory.set_container(container)
	assert_push_error_count(0)
	assert_eq(factory.container, container)


func test_reset_frees_everything_and_keeps_registrations():
	factory.register('a', _node)
	var out := factory.acquire('a')
	var pooled := factory.acquire('a')
	factory.release(pooled)
	factory.reset()
	await get_tree().process_frame
	assert_false(is_instance_valid(out))
	assert_false(is_instance_valid(pooled))
	assert_null(factory.container)
	assert_true(factory.is_registered('a'))


func test_a_reset_during_acquire_async_returns_null():
	factory.register('a', func():
		await get_tree().process_frame
		return Node.new())
	var result := [Node]
	var run := func(): result[0] = await factory.acquire_async('a')
	run.call()
	factory.reset()
	for i in 4:
		await get_tree().process_frame
	assert_null(result[0])
	assert_eq(factory.tracked_count(), 0)


func test_re_registering_frees_idle_pooled_and_stale_handed_out_entities():
	factory.register('a', _tagged('old'))
	var idle := factory.acquire('a')
	var out := factory.acquire('a')
	factory.release(idle)
	factory.register('a', _tagged('new'))
	assert_eq(factory.acquire('a').name, 'new')
	assert_false(factory.release(out), 'a stale entity is freed, not pooled')
	await get_tree().process_frame
	assert_false(is_instance_valid(idle))
	assert_false(is_instance_valid(out))


func test_a_freed_container_reports_and_returns_null():
	var other := LFFactory.new()
	var doomed := Node.new()
	other.set_container(doomed)
	other.register('a', _node)
	doomed.free()
	assert_null(other.acquire('a'))
	assert_push_error('no container')
	assert_null(await other.acquire_async('a'))
	assert_push_error('no container')
	assert_eq(other.tracked_count(), 0)


func test_setting_a_container_after_the_old_one_was_freed_does_not_report():
	var other := LFFactory.new()
	var doomed := Node.new()
	other.set_container(doomed)
	doomed.free()
	other.set_container(container)
	assert_push_error_count(0)


func test_owns_handed_out_and_pooled_entities_only():
	factory.register('a', _node)
	var out := factory.acquire('a')
	var pooled := factory.acquire('a')
	factory.release(pooled)
	var stranger: Node = autofree(Node.new())
	assert_true(factory.owns(out))
	assert_true(factory.owns(pooled))
	assert_false(factory.owns(stranger))
	factory.reset()
	assert_false(factory.owns(out), 'nothing is owned after reset')
	assert_false(factory.owns(pooled))


func test_owns_is_false_for_a_freed_entity():
	factory.register('a', _node)
	var out := factory.acquire('a')
	out.free()
	assert_false(factory.owns(out))


func test_acquire_async_hands_a_pooled_entity_back_without_waiting_a_frame():
	factory.register('a', _node)
	var pooled := factory.acquire('a')
	factory.release(pooled)
	var frame := Engine.get_process_frames()
	var entity := await factory.acquire_async('a')
	assert_same(entity, pooled)
	assert_eq(Engine.get_process_frames(), frame, 'no frame passed')


func test_a_re_register_during_acquire_async_returns_null_and_frees_the_entity():
	var created := []
	factory.register('a', _node, Callable(), Callable(), func(e): created.append(e))
	var result := [Node]
	var run := func(): result[0] = await factory.acquire_async('a')
	run.call()
	factory.register('a', _node)
	for i in 3:
		await get_tree().process_frame
	assert_null(result[0])
	assert_eq(created.size(), 1)
	assert_false(is_instance_valid(created[0]), 'the entity made under the old definition is freed')
	assert_eq(factory.tracked_count(), 0)


func test_acquire_async_with_a_creation_function_returning_no_node_reports_and_returns_null():
	factory.register('a', func(): return 7)
	assert_null(await factory.acquire_async('a'))
	assert_push_error('returned no Node')
	assert_eq(factory.tracked_count(), 0)


func test_acquire_async_runs_on_created_before_the_entity_is_parented():
	var parents := []
	factory.register('a', _node, Callable(), Callable(), func(e): parents.append(e.get_parent()))
	var entity := await factory.acquire_async('a')
	assert_eq(parents.size(), 1)
	assert_null(parents[0], 'not parented yet when on_created runs')
	assert_eq(entity.get_parent(), container)


func test_an_entity_still_being_parented_cannot_be_released():
	var created := []
	factory.register('a', _node, Callable(), Callable(), func(e): created.append(e))
	var result := [Node]
	var run := func(): result[0] = await factory.acquire_async('a')
	run.call()
	assert_eq(created.size(), 1)
	assert_false(factory.release(created[0]), 'in flight: not releasable')
	assert_false(factory.owns(created[0]))
	for i in 3:
		await get_tree().process_frame
	assert_same(result[0], created[0])
	assert_true(factory.release(created[0]), 'releasable once handed out')


func test_a_container_freed_during_acquire_async_returns_null_and_frees_the_entity():
	var other := LFFactory.new()
	var doomed := Node.new()
	add_child(doomed)
	other.set_container(doomed)
	var created := []
	other.register('a', _node, Callable(), Callable(), func(e): created.append(e))
	var result := [Node]
	var run := func(): result[0] = await other.acquire_async('a')
	run.call()
	doomed.free()
	for i in 3:
		await get_tree().process_frame
	assert_null(result[0])
	assert_eq(created.size(), 1)
	assert_false(is_instance_valid(created[0]), 'never parented, so freed rather than leaked')
	assert_eq(other.tracked_count(), 0)


func test_release_all_frees_a_stale_entity_instead_of_pooling_it():
	factory.register('a', _node)
	var out := factory.acquire('a')
	factory.register('a', _node)
	factory.release_all()
	assert_eq(factory.pooled_count('a'), 0)
	assert_eq(factory.tracked_count(), 0)
	await get_tree().process_frame
	assert_false(is_instance_valid(out))



func test_counts_skip_entities_freed_behind_the_factorys_back():
	factory.register('a', _node)
	var out := factory.acquire('a')
	var pooled := factory.acquire('a')
	factory.release(pooled)
	out.free()
	pooled.free()

	assert_eq(factory.pooled_count('a'), 0, 'a freed entity is not waiting in the pool')
	assert_eq(factory.tracked_count('a'), 0)
	assert_eq(factory.tracked_count(), 0)


func test_records_of_entities_freed_behind_the_factorys_back_do_not_pile_up():
	factory.register('a', _node)
	for i in 500:
		factory.acquire('a').free() # freed without release, like a one-shot effect
	assert_lt(factory._records.size(), 100, 'freed records are swept while acquiring')
	assert_eq(factory.tracked_count('a'), 0)


func test_freed_records_are_swept_while_other_entities_stay_alive():
	factory.register('a', _node)
	var kept := factory.acquire('a') # alive the whole time, like a long-lived unit
	for i in 1000:
		factory.acquire('a').free() # freed without release, like a one-shot effect
	assert_true(factory.owns(kept))
	assert_lte(factory._records.size(), 1 + 32, 'at most one sweep interval of freed records')


func test_the_sweep_interval_follows_the_live_count_after_the_last_sweep():
	factory.register('a', _node)
	var kept: Array[Node] = []
	for i in 50:
		kept.append(factory.acquire('a'))
	for i in 1000:
		factory.acquire('a').free()
	assert_lte(factory._records.size(), 50 + 50, 'the live records plus one interval of 50')
	assert_eq(factory.tracked_count('a'), 50)


func test_an_unknown_key_is_not_registered_and_has_an_empty_pool():
	assert_false(factory.is_registered('nope'))
	assert_eq(factory.pooled_count('nope'), 0)
	assert_eq(factory.tracked_count('nope'), 0)


func test_acquire_async_with_an_unknown_key_reports_and_returns_null():
	assert_null(await factory.acquire_async('nope'))
	assert_push_error('no registration')


func test_releasing_a_value_that_is_not_a_node_is_refused():
	factory.register('a', _node)
	factory.acquire('a')
	for stranger in [5, 'a', null, {}]:
		assert_false(factory.release(stranger), str(stranger))
	assert_eq(factory.tracked_count('a'), 1)


func test_setting_the_same_container_again_does_not_report():
	factory.set_container(container)
	assert_push_error_count(0)
	assert_same(factory.container, container)


func test_acquire_async_calls_the_acquire_hook_for_fresh_and_pooled_entities():
	factory.register('a', _node, func(e): log.append(['acquire', e]), func(e): log.append(['release', e]))
	var entity := await factory.acquire_async('a')
	factory.release(entity)
	await factory.acquire_async('a')
	assert_eq(log, [['acquire', entity], ['release', entity], ['acquire', entity]])


func test_a_container_freed_while_the_creation_function_awaits_returns_null_and_frees_the_entity():
	var other := LFFactory.new()
	var doomed := Node.new()
	add_child(doomed)
	other.set_container(doomed)
	var made := []
	other.register('a', func():
		await get_tree().process_frame
		var n := Node.new()
		made.append(n)
		return n)
	var result := [Node]
	var run := func(): result[0] = await other.acquire_async('a')
	run.call()
	doomed.free()
	for i in 4:
		await get_tree().process_frame
	assert_null(result[0])
	assert_eq(made.size(), 1)
	assert_false(is_instance_valid(made[0]), 'freed instead of leaked')
	assert_eq(other.tracked_count(), 0)


func test_a_reset_while_an_entity_is_being_parented_returns_null_and_frees_it():
	var created := []
	factory.register('a', _node, Callable(), Callable(), func(e): created.append(e))
	var result := [Node]
	var run := func(): result[0] = await factory.acquire_async('a')
	run.call()
	assert_eq(created.size(), 1, 'in flight now')
	factory.reset()
	for i in 3:
		await get_tree().process_frame
	assert_null(result[0])
	assert_false(is_instance_valid(created[0]))
	assert_eq(factory.tracked_count(), 0)


func test_an_entity_freed_while_being_parented_returns_null():
	var created := []
	factory.register('a', _node, Callable(), Callable(), func(e): created.append(e))
	var result := [Node]
	var run := func(): result[0] = await factory.acquire_async('a')
	run.call()
	created[0].free()
	for i in 3:
		await get_tree().process_frame
	assert_null(result[0])
	assert_eq(factory.tracked_count(), 0)
	assert_eq(container.get_child_count(), 0)


# --- where acquire and release may be called ---


## An Area2D with a circle shape: adding one to the tree registers it with the physics server.
func _make_area() -> Node:
	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	area.add_child(shape)
	area.position = Vector2(-500, -500) # far from the trigger
	return area


func _show_and_run(entity: Node) -> void:
	entity.process_mode = Node.PROCESS_MODE_INHERIT
	entity.show()


func _hide_and_stop(entity: Node) -> void:
	entity.process_mode = Node.PROCESS_MODE_DISABLED
	entity.hide()


## A trigger area and a body that moves into it on the next physics frames, so the
## trigger's `body_entered` fires during the physics server's query flush. Returns the trigger.
func _trigger_with_incoming_body(on_entered: Callable) -> Area2D:
	var trigger: Area2D = add_child_autofree(_make_area())
	trigger.position = Vector2.ZERO
	trigger.body_entered.connect(on_entered)
	var body := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	body.add_child(shape)
	body.position = Vector2(200, 0)
	add_child_autofree(body)
	await wait_physics_frames(2)
	body.position = Vector2.ZERO
	return trigger


class _PhysicsSpawner:
	extends Node
	var factory: LFFactory
	var frames := 0
	var last: Node

	func _physics_process(_delta: float) -> void:
		frames += 1
		if last != null:
			factory.release(last)
		last = factory.acquire(&'area')
		if frames % 3 == 0:
			last = factory.acquire(&'area') # a second one: the pool is empty, so it is fresh


func test_acquire_and_release_from_physics_process_create_physics_entities_without_errors():
	factory.register(&'area', _make_area, _show_and_run, _hide_and_stop)
	var spawner := _PhysicsSpawner.new()
	spawner.factory = factory
	add_child_autofree(spawner)
	await wait_physics_frames(10)
	assert_gt(spawner.frames, 5)
	assert_gt(factory.tracked_count(&'area'), 1, 'fresh areas were created in _physics_process')
	assert_engine_error_count(0)


func test_a_fresh_physics_entity_acquired_in_body_entered_makes_godot_report_the_query_flush():
	factory.register(&'area', _make_area)
	var got := []
	await _trigger_with_incoming_body(func(_body: Node2D) -> void: got.append(factory.acquire(&'area')))
	await wait_physics_frames(3)
	assert_eq(got.size(), 1)
	assert_engine_error('flushing queries', 'Godot refuses part of the physics setup there')


func test_acquire_deferred_or_async_from_body_entered_creates_without_errors():
	factory.register(&'area', _make_area)
	var got := []
	var on_entered := func(_body: Node2D) -> void:
		factory.acquire.call_deferred(&'area')
		got.append(await factory.acquire_async(&'area'))
	await _trigger_with_incoming_body(on_entered)
	await wait_physics_frames(3)
	await wait_process_frames(2)
	assert_eq(got.size(), 1)
	assert_true(got[0] is Area2D)
	assert_eq(factory.tracked_count(&'area'), 2, 'one deferred, one async')
	assert_engine_error_count(0)


func test_a_pooled_entity_acquired_and_released_in_body_entered_raises_no_errors():
	factory.register(&'area', _make_area, _show_and_run, _hide_and_stop)
	var spare := factory.acquire(&'area')
	var held := factory.acquire(&'area')
	factory.release(spare)
	var got := []
	var on_entered := func(_body: Node2D) -> void:
		factory.release(held)
		got.append(factory.acquire(&'area'))
	await _trigger_with_incoming_body(on_entered)
	await wait_physics_frames(3)
	assert_eq(got.size(), 1)
	assert_true(factory.owns(got[0]))
	assert_eq(factory.tracked_count(&'area'), 2, 'nothing fresh was made')
	assert_engine_error_count(0)


enum _State { ALIVE, DEAD }
enum _Move { DIE, REVIVE }


## A pooled enemy whose death is a state machine transition.
class _Enemy:
	extends Node
	signal died(enemy: Node)
	var machine: LFStateMachine

	func _init() -> void:
		machine = LFStateMachine.new(LFStateMachineConfig.new(_State.ALIVE, [
			LFStateTransition.new(_Move.DIE, [_State.ALIVE], _State.DEAD),
			LFStateTransition.new(_Move.REVIVE, [_State.DEAD], _State.ALIVE),
		], [LFStateEnterHook.new([_State.DEAD], _on_dead)]))

	func _on_dead() -> void:
		died.emit(self)


func _make_enemy() -> Node:
	var enemy := _Enemy.new()
	enemy.died.connect(_respawn)
	return enemy


func _revive(enemy: _Enemy) -> void:
	if enemy.machine.get_state() == _State.DEAD:
		log.append(await enemy.machine.do(_Move.REVIVE))


func _respawn(enemy: Node) -> void:
	factory.release(enemy)
	factory.acquire(&'enemy')


func test_release_and_acquire_inside_a_state_machine_enter_hook_but_the_entitys_own_machine_is_still_busy():
	factory.register(&'enemy', _make_enemy, _revive)
	var enemy: _Enemy = factory.acquire(&'enemy')

	await enemy.machine.do(_Move.DIE) # the DEAD enter hook releases it and acquires again: the same enemy

	assert_eq(factory.tracked_count(&'enemy'), 1, 'the pooled enemy was handed out again')
	assert_false(factory.is_pooled(enemy))
	assert_eq(log, [false], 'its own machine was still in its enter hook, so REVIVE was refused')
	assert_eq(enemy.machine.get_state(), _State.DEAD)


func test_deferring_the_respawn_out_of_the_enter_hook_lets_the_entity_reset_its_own_machine():
	factory.register(&'enemy', _make_enemy, _revive)
	var enemy: _Enemy = factory.acquire(&'enemy')
	enemy.died.disconnect(_respawn)
	enemy.died.connect(_respawn, CONNECT_DEFERRED)

	await enemy.machine.do(_Move.DIE)
	await wait_process_frames(1)

	assert_eq(log, [true])
	assert_eq(enemy.machine.get_state(), _State.ALIVE)
	assert_eq(factory.tracked_count(&'enemy'), 1)


func test_release_and_acquire_inside_a_status_effect_tick_callback():
	factory.register(&'enemy', _node, Callable(), _clear_effects)
	var effects := LFStatusEffects.new()
	var poison := LFStatusEffectDef.new(&'poison', LFStatusEffectDef.Accumulation.INDEPENDENT, 3.0, 1,
		LFStatusEffectDef.Overflow.DROP, 1.0, _kill_and_respawn)
	var enemy := factory.acquire(&'enemy')
	enemy.set_meta(&'effects', effects)
	effects.apply(poison)

	effects.tick(1.0, enemy) # the tick kills the enemy: released (its effects cleared) and respawned

	assert_eq(log, ['tick'])
	assert_false(effects.has(&'poison'), 'clear() inside the tick stopped the poison')
	assert_eq(factory.tracked_count(&'enemy'), 1)
	assert_false(factory.is_pooled(enemy), 'the same enemy was handed out again')
	effects.tick(5.0, enemy)
	assert_eq(log, ['tick'], 'no tick after the clear')


func _kill_and_respawn(target: Variant, _stack: LFStatusStack) -> void:
	log.append('tick')
	factory.release(target)
	factory.acquire(&'enemy')


func _clear_effects(entity: Node) -> void:
	(entity.get_meta(&'effects') as LFStatusEffects).clear()


# --- callbacks whose object was freed ---


class _Owner:
	extends Node
	var calls := []

	func make() -> Node:
		return Node.new()

	func shown(_entity: Node) -> void:
		calls.append('shown')


func test_a_hook_whose_object_was_freed_is_skipped():
	var hook_owner := _Owner.new()
	factory.register('a', _node, hook_owner.shown)
	factory.release(factory.acquire('a'))
	hook_owner.free()

	assert_not_null(factory.acquire('a'), 'the pooled entity is handed out')
	assert_engine_error_count(0)


func test_a_creation_function_whose_object_was_freed_is_reported():
	var creator := _Owner.new()
	factory.register('a', creator.make)
	creator.free()

	assert_null(factory.acquire('a'))
	assert_push_error('freed')
	assert_engine_error_count(0)


func test_respawning_from_a_state_entered_listener_lets_the_entity_reset_its_own_machine():
	factory.register(&'enemy', _make_enemy, _revive)
	var enemy: _Enemy = factory.acquire(&'enemy')
	enemy.died.disconnect(_respawn)
	enemy.machine.state_entered.connect(func(state: int) -> void:
		if state == _State.DEAD:
			_respawn(enemy))

	await enemy.machine.do(_Move.DIE)

	assert_eq(log, [true], 'the REVIVE from on_acquire was queued, then ran')
	assert_eq(enemy.machine.get_state(), _State.ALIVE)


## A child whose `_ready` acquires: when its parent (the container) enters the tree with it,
## the container is still setting up its children.
class _GreedyChild:
	extends Node
	var factory: LFFactory
	var got: Array

	func _ready() -> void:
		got.append(factory.acquire(&'a'))
		got.append(await factory.acquire_async(&'a'))


func test_a_fresh_acquire_while_the_container_sets_up_children_is_refused_by_godot_but_async_works():
	var screen := Node.new()
	var child := _GreedyChild.new()
	child.factory = factory
	child.got = []
	screen.add_child(child)
	factory.reset()
	factory.set_container(screen)
	factory.register(&'a', _node)
	add_child_autofree(screen) # the screen enters the tree with its child: the child's _ready acquires
	await wait_process_frames(3)

	assert_engine_error('busy setting up children')
	assert_eq(child.got.size(), 2)
	assert_eq(child.got[1].get_parent(), screen, 'acquire_async parented its entity')


func test_a_fresh_entity_acquired_in_a_state_machine_hook_or_a_tick_callback_is_in_the_container():
	factory.register(&'spark', _node)
	var got := []
	var spark := func(_a: Variant = null, _b: Variant = null) -> void: got.append(factory.acquire(&'spark'))
	var machine := LFStateMachine.new(LFStateMachineConfig.new(_State.ALIVE, [
		LFStateTransition.new(_Move.DIE, [_State.ALIVE], _State.DEAD),
	], [LFStateEnterHook.new([_State.DEAD], spark)]))
	var effects := LFStatusEffects.new()
	effects.apply(LFStatusEffectDef.new(&'burn', LFStatusEffectDef.Accumulation.INDEPENDENT, 3.0, 1,
		LFStatusEffectDef.Overflow.DROP, 1.0, spark))

	await machine.do(_Move.DIE)
	effects.tick(1.0, null)

	assert_eq(got.size(), 2)
	for entity: Node in got:
		assert_eq(entity.get_parent(), container)
	assert_engine_error_count(0)


func test_a_creation_function_returning_a_tracked_node_is_refused():
	var single := Node.new()
	factory.register('s', func(): return single)
	var first := factory.acquire('s')
	assert_not_null(first)
	assert_null(factory.acquire('s'), 'the same node is not handed out twice')
	assert_push_error('already')
	assert_eq(factory.tracked_count('s'), 1)


func test_a_creation_function_returning_a_node_already_in_the_tree_is_refused():
	var parented := Node.new()
	container.add_child(parented)
	factory.register('p', func(): return parented)
	assert_null(factory.acquire('p'))
	assert_push_error('already')
	assert_eq(factory.tracked_count('p'), 0)


func test_an_empty_creation_function_is_reported_as_invalid():
	factory.register('e', Callable())
	assert_null(factory.acquire('e'))
	assert_push_error('not valid')


func test_an_on_release_hook_that_frees_the_entity_leaves_nothing_pooled():
	factory.register('k', _node, Callable(), func(e: Node): e.free())
	var entity := factory.acquire('k')
	assert_false(factory.release(entity))
	assert_eq(factory.pooled_count('k'), 0)
	assert_eq(factory.tracked_count('k'), 0)


func test_an_on_release_hook_that_queues_the_entity_for_deletion_is_not_handed_out_again():
	factory.register('q', _node, Callable(), func(e: Node): e.queue_free())
	var entity := factory.acquire('q')
	assert_false(factory.release(entity))
	var next := factory.acquire('q')
	assert_ne(next, entity)
	assert_false(next.is_queued_for_deletion())


func _dormant_pool() -> Dictionary:
	var hooks := LFFactory.dormant_hooks()
	factory.register('body', func(): return Area2D.new(), hooks.on_acquire, hooks.on_release)
	return hooks


func test_dormant_hooks_name_both_hooks():
	var hooks := LFFactory.dormant_hooks()
	assert_true(hooks[LFFactory.DORMANT_ON_ACQUIRE].is_valid())
	assert_true(hooks[LFFactory.DORMANT_ON_RELEASE].is_valid())


func test_a_released_entity_with_dormant_hooks_is_hidden_idle_and_collisionless():
	_dormant_pool()
	var area: Area2D = factory.acquire('body')
	area.collision_layer = 5
	area.collision_mask = 6
	factory.release(area)
	await get_tree().process_frame
	assert_false(area.visible)
	assert_eq(area.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(area.collision_layer, 0)
	assert_eq(area.collision_mask, 0)
	assert_false(area.monitoring)


func test_acquiring_again_restores_the_original_values_not_defaults():
	_dormant_pool()
	var area: Area2D = factory.acquire('body')
	area.collision_layer = 5
	area.collision_mask = 6
	area.process_mode = Node.PROCESS_MODE_PAUSABLE
	area.monitoring = false
	factory.release(area)
	assert_same(factory.acquire('body'), area)
	await get_tree().process_frame
	assert_true(area.visible)
	assert_eq(area.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_eq(area.collision_layer, 5)
	assert_eq(area.collision_mask, 6)
	assert_false(area.monitoring, 'a node that started with monitoring off stays off')


func test_monitoring_comes_back_after_a_release_and_acquire_in_one_frame():
	_dormant_pool()
	var area: Area2D = factory.acquire('body')
	factory.release(area)
	factory.acquire('body')
	await get_tree().process_frame
	assert_true(area.monitoring)


func test_a_node_without_physics_properties_only_loses_visibility_and_processing():
	var hooks := LFFactory.dormant_hooks()
	factory.register('plain', func(): return Node2D.new(), hooks.on_acquire, hooks.on_release)
	var node: Node2D = factory.acquire('plain')
	factory.release(node)
	assert_false(node.visible)
	assert_eq(node.process_mode, Node.PROCESS_MODE_DISABLED)
	factory.acquire('plain')
	assert_true(node.visible)
	assert_eq(node.process_mode, Node.PROCESS_MODE_INHERIT)


func test_a_plain_node_is_made_idle_and_restored():
	var hooks := LFFactory.dormant_hooks()
	factory.register('n', _node, hooks.on_acquire, hooks.on_release)
	var node := factory.acquire('n')
	factory.release(node)
	assert_eq(node.process_mode, Node.PROCESS_MODE_DISABLED)
	factory.acquire('n')
	assert_eq(node.process_mode, Node.PROCESS_MODE_INHERIT)


func test_sleeping_twice_keeps_the_first_originals():
	var node := Node2D.new()
	add_child_autofree(node)
	LFFactory.sleep(node)
	LFFactory.sleep(node)
	LFFactory.wake(node)
	assert_eq(node.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_true(node.visible)


func test_wake_on_a_node_that_is_not_asleep_changes_nothing():
	var node := Node2D.new()
	add_child_autofree(node)
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	LFFactory.wake(node)
	assert_eq(node.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_sleep_and_wake_ignore_null_and_freed_nodes():
	var node := Node.new()
	node.free()
	LFFactory.sleep(null)
	LFFactory.sleep(node)
	LFFactory.wake(null)
	LFFactory.wake(node)
	assert_true(true, 'no error')


class _Emitter:
	extends Node
	signal done


func test_release_on_signal_releases_the_entity_when_it_emits():
	factory.register('a', _Emitter.new, factory.release_on_signal(&'done'))
	var entity := factory.acquire('a') as _Emitter
	entity.done.emit()
	assert_true(factory.is_pooled(entity))


func test_release_on_signal_connects_once_per_hand_out():
	factory.register('a', _Emitter.new, factory.release_on_signal(&'done'))
	var entity := factory.acquire('a') as _Emitter
	entity.done.emit()
	assert_eq(entity.done.get_connections().size(), 0)
	assert_eq(factory.acquire('a'), entity)
	assert_eq(entity.done.get_connections().size(), 1)
	entity.done.emit()
	assert_true(factory.is_pooled(entity))


func test_release_on_signal_with_an_unknown_signal_reports_and_connects_nothing():
	factory.register('a', _Emitter.new, factory.release_on_signal(&'nope'))
	var entity := factory.acquire('a')
	assert_push_error('no signal')
	assert_not_null(entity)
	assert_false(factory.is_pooled(entity))
