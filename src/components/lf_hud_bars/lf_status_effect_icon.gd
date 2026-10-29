## A `LFTimerIcon` that drains with one effect of an `LFStatusEffects` container.
##
## Call `track_effect(effects, id)`. A ticking effect shows the time to its next tick; any
## other finite effect shows its time left out of the time it had at `track_effect` or the
## last `refresh`. While the effect is not active the fraction stays as it was.
class_name LFStatusEffectIcon
extends LFTimerIcon

var _effects: LFStatusEffects
var _id: StringName
var _total := 0.0


## Follows effect `id` of `effects` from now on and takes the time left as the full length.
func track_effect(effects: LFStatusEffects, id: StringName) -> void:
	_effects = effects
	_id = id
	refresh()


## Takes the time left now as the full length, for when the effect is refreshed.
func refresh() -> void:
	if _effects != null:
		_total = _effects.remaining(_id)


func _process(_delta: float) -> void:
	if _effects == null:
		return
	var stacks := _effects.stacks(_id)
	if stacks.is_empty():
		return
	var stack := stacks[0]
	if stack.tick_interval > 0.0:
		set_fraction((stack.next_tick_at - _effects.now()) / stack.tick_interval)
	elif is_finite(_total) and _total > 0.0:
		set_fraction(_effects.remaining(_id) / _total)
