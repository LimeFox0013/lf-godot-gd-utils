## A short slow-motion (or fast-forward) pulse in real time: the game slows for a moment, then returns to the speed it had.
##
## `LFTimeScale.pulse(get_tree(), 0.3, 0.8)` runs the game at 30 % speed for 0.8 real seconds. The length is in real
## seconds, not game seconds, so a pulse always lasts as long as the player sees it. A new pulse while one is on takes
## over, and the speed from before the first pulse is the one that comes back.
class_name LFTimeScale
extends RefCounted

## The slowest speed a pulse can ask for (the engine misbehaves at 0).
const MIN_SCALE := 0.01

static var _usual := 1.0
static var _active := false
static var _token := 0


## Sets the game speed to `scale` for `real_seconds`, then puts back the speed it had. Does nothing for a null tree.
static func pulse(tree: SceneTree, scale: float, real_seconds: float) -> void:
	if tree == null:
		return
	if not _active:
		_usual = Engine.time_scale
		_active = true
	_token += 1
	var mine := _token
	Engine.time_scale = maxf(scale, MIN_SCALE)
	await tree.create_timer(maxf(real_seconds, 0.0), true, false, true).timeout
	if mine == _token:
		reset()


## Puts the speed back now, ending any pulse (call it when the scene that pulsed goes away).
static func reset() -> void:
	if _active:
		Engine.time_scale = _usual
		_active = false
	_token += 1


## Whether a pulse is on.
static func is_active() -> bool:
	return _active
