extends GutTest

## Overlaps are driven by emitting `area_entered` / `area_exited` directly and the gate by
## calling `tick`, so no test waits for physics or real time.

## Gate length used by most tests, in seconds.
const GATE_SECONDS := 0.5
## Part of the gate that leaves it closed, in seconds.
const PARTIAL_SECONDS := 0.2
## The rest of the gate after `PARTIAL_SECONDS`, with a margin, in seconds.
const REST_SECONDS := 0.4
## A payload value the tests attach.
const PAYLOAD_DAMAGE := 7

var _hurt: LFHurtBox2D
var _hits: Array[LFHitBox2D] = []


func before_each() -> void:
	_hits.clear()
	_hurt = add_child_autofree(LFHurtBox2D.new())
	_hurt.invulnerability_seconds = GATE_SECONDS
	_hurt.hit_received.connect(func(hit_box: LFHitBox2D) -> void: _hits.append(hit_box))


func _make_hit(behaviour := LFHitBox2D.Behaviour.REPEATED) -> LFHitBox2D:
	var hit_box: LFHitBox2D = add_child_autofree(LFHitBox2D.new())
	hit_box.behaviour = behaviour
	return hit_box


func _enter(hit_box: LFHitBox2D) -> void:
	_hurt.area_entered.emit(hit_box)


func test_overlap_emits_hit_received_with_the_hit_box() -> void:
	var hit_box := _make_hit()
	hit_box.payload = PAYLOAD_DAMAGE
	_enter(hit_box)
	assert_eq(_hits.size(), 1)
	assert_eq(_hits[0], hit_box)
	assert_eq(_hits[0].payload, PAYLOAD_DAMAGE)


func test_source_and_payload_are_untyped() -> void:
	var token := RefCounted.new()
	_hurt.source = token
	var hit_box := _make_hit()
	hit_box.source = {"attacker": 1}
	assert_eq(_hurt.source, token)
	assert_eq(hit_box.source["attacker"], 1)


func test_hit_landed_is_emitted_on_the_hit_box() -> void:
	var hit_box := _make_hit()
	watch_signals(hit_box)
	_enter(hit_box)
	assert_signal_emitted_with_parameters(hit_box, "hit_landed", [_hurt])


func test_gate_ignores_hits_while_closed() -> void:
	_enter(_make_hit())
	_enter(_make_hit())
	assert_eq(_hits.size(), 1)
	assert_true(_hurt.is_gate_closed())
	assert_almost_eq(_hurt.gate_time_left(), GATE_SECONDS, 0.0001)


func test_gate_counts_down_and_opens() -> void:
	var hit_box := _make_hit()
	_enter(hit_box)
	_hurt.area_exited.emit(hit_box)
	_hurt.tick(PARTIAL_SECONDS)
	assert_true(_hurt.is_gate_closed())
	watch_signals(_hurt)
	_hurt.tick(REST_SECONDS)
	assert_false(_hurt.is_gate_closed())
	assert_signal_emitted(_hurt, "gate_opened")


func test_hit_arriving_after_the_gate_opened_is_accepted() -> void:
	_enter(_make_hit())
	_hurt.tick(GATE_SECONDS)
	_enter(_make_hit())
	assert_eq(_hits.size(), 2)


func test_overlap_during_gate_is_applied_when_the_gate_opens() -> void:
	var first := _make_hit()
	var second := _make_hit()
	_enter(first)
	_enter(second)
	assert_eq(_hits.size(), 1)
	_hurt.tick(GATE_SECONDS)
	assert_eq(_hits.size(), 2)
	assert_eq(_hits[1], second, "the most recent overlapping box is tried first")
	assert_true(_hurt.is_gate_closed(), "the re-applied hit closes the gate again")


func test_box_that_left_during_the_gate_is_not_applied() -> void:
	var first := _make_hit()
	var second := _make_hit()
	_enter(first)
	_enter(second)
	_hurt.area_exited.emit(second)
	_hurt.tick(GATE_SECONDS)
	assert_eq(_hits.size(), 2, "the first box still overlaps and is applied")
	assert_eq(_hits[1], first)


func test_freed_overlapping_box_is_skipped_when_the_gate_opens() -> void:
	var first := _make_hit()
	var second := _make_hit()
	_enter(first)
	_enter(second)
	second.free()
	_hurt.tick(GATE_SECONDS)
	assert_eq(_hits.size(), 2)
	assert_eq(_hits[1], first)


func test_gate_opens_without_a_reapply_when_nothing_overlaps() -> void:
	var hit_box := _make_hit()
	_enter(hit_box)
	_hurt.area_exited.emit(hit_box)
	_hurt.tick(GATE_SECONDS)
	assert_eq(_hits.size(), 1)
	assert_false(_hurt.is_gate_closed())


func test_zero_invulnerability_means_no_gate() -> void:
	_hurt.invulnerability_seconds = 0.0
	_enter(_make_hit())
	assert_false(_hurt.is_gate_closed())
	_enter(_make_hit())
	assert_eq(_hits.size(), 2)


func test_nan_invulnerability_is_rejected() -> void:
	_hurt.invulnerability_seconds = NAN
	assert_eq(_hurt.invulnerability_seconds, GATE_SECONDS)
	assert_push_error_count(1)


func test_default_invulnerability() -> void:
	var fresh: LFHurtBox2D = autofree(LFHurtBox2D.new())
	assert_eq(fresh.invulnerability_seconds, LFHurtBox2D.DEFAULT_INVULNERABILITY_SECONDS)


func test_disabled_hurt_box_takes_no_hits() -> void:
	_hurt.disabled = true
	_enter(_make_hit())
	assert_eq(_hits.size(), 0)
	assert_false(_hurt.try_hit(_make_hit()))


func test_enabling_opens_the_gate_and_disabling_forgets_overlaps() -> void:
	_enter(_make_hit())
	assert_true(_hurt.is_gate_closed())
	_hurt.disabled = true
	_hurt.disabled = false
	assert_false(_hurt.is_gate_closed())
	var pending := _make_hit()
	_enter(pending)
	_hurt.disabled = true
	_hurt.disabled = false
	_hurt.try_hit(_make_hit())
	_hurt.tick(GATE_SECONDS)
	assert_eq(_hits.size(), 3, "pending was not remembered across the disable")


func test_reset_disables_and_opens_the_gate() -> void:
	_enter(_make_hit())
	_hurt.reset()
	assert_true(_hurt.disabled)
	assert_false(_hurt.is_gate_closed())


func test_disabled_hit_box_deals_nothing() -> void:
	var hit_box := _make_hit()
	hit_box.disabled = true
	_enter(hit_box)
	assert_eq(_hits.size(), 0)
	assert_false(hit_box.can_hit(_hurt))


func test_hit_box_disabled_while_overlapping_is_not_applied_when_the_gate_opens() -> void:
	var first := _make_hit()
	var second := _make_hit()
	_enter(first)
	_enter(second)
	second.disabled = true
	_hurt.tick(GATE_SECONDS)
	assert_eq(_hits[1], first)


func test_once_hits_each_hurt_box_a_single_time() -> void:
	var hit_box := _make_hit(LFHitBox2D.Behaviour.ONCE)
	_enter(hit_box)
	_hurt.tick(GATE_SECONDS)
	_enter(hit_box)
	assert_eq(_hits.size(), 1)
	assert_true(hit_box.has_hit(_hurt))


func test_once_is_not_spent_by_a_hit_refused_during_the_gate() -> void:
	_enter(_make_hit())
	var sword := _make_hit(LFHitBox2D.Behaviour.ONCE)
	_enter(sword)
	assert_false(sword.has_hit(_hurt))
	_hurt.tick(GATE_SECONDS)
	assert_eq(_hits[1], sword, "it lands when the gate opens")
	assert_true(sword.has_hit(_hurt))


func test_once_hits_a_second_hurt_box() -> void:
	var other: LFHurtBox2D = add_child_autofree(LFHurtBox2D.new())
	var hit_box := _make_hit(LFHitBox2D.Behaviour.ONCE)
	_enter(hit_box)
	assert_true(other.try_hit(hit_box))


func test_clear_hit_targets_allows_a_second_swing() -> void:
	var hit_box := _make_hit(LFHitBox2D.Behaviour.ONCE)
	_enter(hit_box)
	_hurt.tick(GATE_SECONDS)
	hit_box.clear_hit_targets()
	assert_true(_hurt.try_hit(hit_box))


func test_repeated_hits_again_when_the_gate_allows() -> void:
	var hit_box := _make_hit()
	assert_true(_hurt.try_hit(hit_box))
	assert_false(_hurt.try_hit(hit_box))
	_hurt.tick(GATE_SECONDS)
	assert_true(_hurt.try_hit(hit_box))


func test_standing_in_a_repeated_hit_box_keeps_hurting_at_the_gate_rhythm() -> void:
	var fire := _make_hit()
	_enter(fire)
	_hurt.tick(GATE_SECONDS)
	_hurt.tick(GATE_SECONDS)
	assert_eq(_hits.size(), 3)


func test_non_hit_box_areas_are_ignored() -> void:
	var other: Area2D = add_child_autofree(Area2D.new())
	_hurt.area_entered.emit(other)
	assert_eq(_hits.size(), 0)


func test_physics_process_runs_only_while_the_gate_is_closed() -> void:
	assert_false(_hurt.is_physics_processing())
	var hit_box := _make_hit()
	_enter(hit_box)
	assert_true(_hurt.is_physics_processing())
	_hurt.area_exited.emit(hit_box)
	_hurt.tick(GATE_SECONDS)
	assert_false(_hurt.is_physics_processing())


func test_monitoring_follows_disabled() -> void:
	_hurt.disabled = true
	var hit_box := _make_hit()
	hit_box.disabled = true
	await get_tree().process_frame
	assert_false(_hurt.monitoring)
	assert_false(_hurt.monitorable)
	assert_false(hit_box.monitorable)
	hit_box.disabled = false
	await get_tree().process_frame
	assert_true(hit_box.monitorable)


func test_register_hit_records_the_target_for_any_behaviour() -> void:
	var hit_box := _make_hit()
	assert_false(hit_box.has_hit(_hurt))
	hit_box.register_hit(_hurt)
	assert_true(hit_box.has_hit(_hurt))
	assert_true(hit_box.can_hit(_hurt), "REPEATED still hits again")
