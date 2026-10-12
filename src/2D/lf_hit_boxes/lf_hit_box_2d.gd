## The dealing side of a 2D hit: an Area2D that an `LFHurtBox2D` reacts to when their
## shapes overlap.
##
## Give it collision shapes as children and put the attack's data (a damage number, an
## attack resource, anything) in `payload`; the hurt box hands the hit box back in its
## `hit_received` signal, so the receiver reads `payload`. With `behaviour = ONCE` one
## hit box hurts each hurt box at most once until `clear_hit_targets()` (a sword swing
## that must not land twice on the same enemy); with `REPEATED` it hits again whenever the
## hurt box's invulnerability gate allows (a flame on the floor).
class_name LFHitBox2D
extends Area2D

## Emitted when this hit box has landed on `hurt_box` (after the hurt box accepted it).
signal hit_landed(hurt_box: LFHurtBox2D)

## How often one hit box may hurt the same hurt box.
enum Behaviour {
	## Hits again whenever the hurt box's invulnerability gate is open.
	REPEATED,
	## Hits each hurt box at most once, until `clear_hit_targets()`.
	ONCE,
}

## Whether this hit box hurts a hurt box once or repeatedly.
@export var behaviour := Behaviour.REPEATED
## While true the hit box deals nothing and is not detectable by hurt boxes. Writing it is
## the same as `set_disabled`.
@export var disabled := false:
	set = set_disabled
## Anything the game wants to attach to the attack (damage, an attack resource, a
## dictionary). The library never reads it.
var payload: Variant = null
## The object that dealt the attack (the attacker, for example), for the receiver
## to read. The library never reads it.
var source: Variant = null

var _hit_target_ids: Dictionary = {}


func _ready() -> void:
	_apply_disabled()


## Enables (`false`) or disables (`true`) the hit box; the same as writing `disabled`.
## The physics change is deferred, so it is safe to call from a collision callback.
func set_disabled(state: bool) -> void:
	disabled = state
	if is_inside_tree():
		_apply_disabled()


## Whether this hit box may hurt `hurt_box` right now: enabled, and for `ONCE` not already
## landed on it. Has no side effects.
func can_hit(hurt_box: LFHurtBox2D) -> bool:
	if disabled:
		return false
	if behaviour == Behaviour.ONCE and _hit_target_ids.has(hurt_box.get_instance_id()):
		return false
	return true


## Records that this hit box landed on `hurt_box` and emits `hit_landed`. Called by the hurt
## box once it accepted the hit; you do not call it yourself.
func register_hit(hurt_box: LFHurtBox2D) -> void:
	_hit_target_ids[hurt_box.get_instance_id()] = true
	hit_landed.emit(hurt_box)


## Whether a `ONCE` hit box has already landed on `hurt_box`.
func has_hit(hurt_box: LFHurtBox2D) -> bool:
	return _hit_target_ids.has(hurt_box.get_instance_id())


## Forgets every hurt box this hit box landed on, so a `ONCE` hit box can hurt them again
## (call it when a new swing starts).
func clear_hit_targets() -> void:
	_hit_target_ids.clear()


func _apply_disabled() -> void:
	set_deferred("monitorable", not disabled)
