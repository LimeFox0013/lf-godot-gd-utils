## The receiving side of a 2D hit: an Area2D that reports `hit_received` when an
## `LFHitBox2D` overlaps it, at most once per invulnerability gate.
##
## Give it collision shapes as children. When a hit box starts overlapping, the hurt box
## accepts it if it is not disabled, the gate is open and the hit box allows it (see
## `LFHitBox2D.can_hit`); accepting emits `hit_received(hit_box)` and closes the gate for
## `invulnerability_seconds`. Hit boxes that arrive while the gate is closed are
## remembered: when the gate opens, the hurt box checks the ones still overlapping and
## accepts the most recent usable one (a fire you stand in keeps hurting at the gate's
## rhythm without leaving and re-entering).
##
## The gate is counted in `tick(delta)`, which the node calls itself every physics frame
## while the gate is closed; tests and simulations can call `tick` directly instead of
## waiting.
class_name LFHurtBox2D
extends Area2D

## Emitted when a hit is accepted. Read the attack from `hit_box.payload` and `hit_box.source`.
signal hit_received(hit_box: LFHitBox2D)
## Emitted when the invulnerability gate opens again after a hit.
signal gate_opened

## Default `invulnerability_seconds`.
const DEFAULT_INVULNERABILITY_SECONDS := 0.05
## Upper end of the Inspector slider for `invulnerability_seconds` (larger typed values are
## allowed).
const _INVULNERABILITY_HINT_MAX := 5.0
## Step of the Inspector slider for `invulnerability_seconds`.
const _INVULNERABILITY_HINT_STEP := 0.01

static var _log := LFLogger.new()

## Seconds after an accepted hit during which further hits are ignored; 0 or less means no
## gate. A NaN is rejected: reported through `LFLogger` as an error, and the value is kept.
@export_range(0.0, _INVULNERABILITY_HINT_MAX, _INVULNERABILITY_HINT_STEP, "or_greater", "suffix:s") var invulnerability_seconds := DEFAULT_INVULNERABILITY_SECONDS:
	set(value):
		if is_nan(value):
			_log.error("LFHurtBox2D: a NaN invulnerability_seconds is rejected; keeping %s" % invulnerability_seconds)
			return
		invulnerability_seconds = value
## While true the hurt box takes no hits and forgets the hit boxes it was overlapping.
## Writing it is the same as `set_disabled`.
@export var disabled := false:
	set = set_disabled
## Anything the game wants to attach to this hurt box (the object it belongs to, for
## example), for the receiver of `hit_received` to read. The library never reads it.
var source: Variant = null

var _gate_remaining := 0.0
var _overlapping: Array[LFHitBox2D] = []


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	_apply_disabled()
	set_physics_process(_gate_remaining > 0.0)


func _physics_process(delta: float) -> void:
	tick(delta)


## Seconds left until the gate opens; 0 when it is open.
func gate_time_left() -> float:
	return _gate_remaining


## Whether the gate is closed, so hits are ignored.
func is_gate_closed() -> bool:
	return _gate_remaining > 0.0


## Enables (`false`) or disables (`true`) the hurt box; the same as writing `disabled`.
## Enabling opens the gate at once; disabling forgets the overlapping hit boxes. The
## physics change is deferred, so it is safe to call from a collision callback.
func set_disabled(state: bool) -> void:
	disabled = state
	if not state:
		_gate_remaining = 0.0
	else:
		_overlapping.clear()
	if is_inside_tree():
		_apply_disabled()
		set_physics_process(_gate_remaining > 0.0)


## Disables the hurt box and forgets the overlapping hit boxes and any closed gate.
func reset() -> void:
	set_disabled(true)
	_gate_remaining = 0.0


## Tries to take a hit from `hit_box` as if it had just started overlapping. Returns true
## when the hit was accepted (`hit_received` emitted); false when the hurt box is disabled,
## the gate is closed or the hit box refuses (see `LFHitBox2D.can_hit`). Overlaps call this
## themselves; call it directly for a hit that has no shape (an explosion by distance).
func try_hit(hit_box: LFHitBox2D) -> bool:
	if disabled or _gate_remaining > 0.0 or not is_instance_valid(hit_box):
		return false
	if not hit_box.can_hit(self):
		return false
	_close_gate()
	hit_box.register_hit(self)
	hit_received.emit(hit_box)
	return true


## Advances the gate by `delta` seconds. When it opens, accepts the most recent
## still-overlapping hit box that is usable (which closes the gate again), otherwise
## emits `gate_opened`. Called every physics frame by the node itself while the gate is
## closed; call it yourself to drive the gate without waiting.
func tick(delta: float) -> void:
	if _gate_remaining <= 0.0:
		return
	_gate_remaining -= delta
	if _gate_remaining > 0.0:
		return
	_gate_remaining = 0.0
	gate_opened.emit()
	_accept_overlapping()
	if _gate_remaining <= 0.0:
		set_physics_process(false)


func _close_gate() -> void:
	_gate_remaining = maxf(invulnerability_seconds, 0.0)
	set_physics_process(_gate_remaining > 0.0)


func _accept_overlapping() -> void:
	# Latest first: earlier ones are the likelier to be on their way out.
	for index in range(_overlapping.size() - 1, -1, -1):
		var candidate := _overlapping[index]
		if not is_instance_valid(candidate):
			_overlapping.remove_at(index)
			continue
		if try_hit(candidate):
			return


func _on_area_entered(area: Area2D) -> void:
	var hit_box := area as LFHitBox2D
	if hit_box == null or disabled:
		return
	_overlapping.append(hit_box)
	try_hit(hit_box)


func _on_area_exited(area: Area2D) -> void:
	var hit_box := area as LFHitBox2D
	if hit_box != null:
		_overlapping.erase(hit_box)


func _apply_disabled() -> void:
	set_deferred("monitoring", not disabled)
	set_deferred("monitorable", not disabled)
