## Plays the right idle/walk/run animation of a 2D character in 3D for where the camera stands.
##
## Drives an AnimatedSprite3D from a character's facing, a viewer's position and a state
## name: plays `<view>_<state>` (see LFDirectionalView), flipping the sprite for a
## mirrored side, and only touches the sprite when the view, the state or the frames
## change (while the wanted animation is missing it looks it up again on every update, so
## an animation added to the frames later is played). A one-shot death animation (`<view>_<die_segment>`) holds the view the
## character died in. It never reads a camera or a body itself: the caller pushes the
## facing, the state and each viewer's position. With no sprite, no frames or a missing
## animation it leaves the sprite alone, so it can be attached before the art exists;
## the one exception is `set_dying(true)` without a death animation, which stops the
## sprite on its current frame.
class_name LFDirectionalSprite3D
extends Node3D

## Default `die_segment`: the state segment of the one-shot death animation.
const DEFAULT_DIE_SEGMENT: StringName = &"die"
## Default `state`: the state segment of the looping animation played first.
const DEFAULT_STATE: StringName = &"idle"

## Squared ground-plane distance (world units squared) below which the viewer counts as
## standing on the character, where no view can be resolved.
const _MIN_VIEWER_DISTANCE_SQUARED := 0.0001

## The sprite to drive. Null makes every call a no-op.
@export var sprite: AnimatedSprite3D
## True: one side is authored and the left view plays it flipped (`side_<state>`).
## False: both sides are authored (`side_l_<state>`, `side_r_<state>`).
@export var mirror_sides: bool = true
## Half the angle of the front and back wedges, in degrees (45 gives four equal views).
@export var front_half_width_deg: float = LFDirectionalView.DEFAULT_FRONT_HALF_WIDTH_DEG
## The state segment of the one-shot death animation (`front_die`, `side_die`, ...).
@export var die_segment: StringName = DEFAULT_DIE_SEGMENT

## The character's heading on the ground plane (x is world X, y is world Z), pushed in by
## whatever steers it. `Vector2.UP` faces -Z. Takes effect on the next `update_view`; any
## length works, but a zero vector reads as facing straight at every viewer.
var facing_xz := Vector2.UP
## The state segment of the looping animation to play (`idle`, `walk`, `run`, ...).
## Takes effect on the next `update_view`.
var state: StringName = DEFAULT_STATE

## True while the death animation plays; set through `set_dying`. Read-only: assigning it
## does nothing.
var dying: bool:
	get:
		return _dying
	set(_value):
		pass

var _dying := false
## The last resolved view, so `set_dying` can play in the current facing without a viewer.
var _last_view: LFDirectionalView.View = LFDirectionalView.View.FRONT
## The view, state and frames last applied; nothing is redone until one of them changes.
## Left as they were when the wanted animation is missing.
var _applied_view := -1
var _applied_state: StringName = &""
var _applied_frames: SpriteFrames


## Call every frame (`_process`): resolves the view for one viewer and plays its
## animation. `unit_position` is the character's world position. `viewer_position` is that
## viewer's camera position; call it per viewer to give each its own view. No-op when
## the viewer stands on the character (on XZ) or while dying (a dying character keeps
## the view it died in, so an orbiting camera never restarts the death animation).
func update_view(unit_position: Vector3, viewer_position: Vector3) -> void:
	var to_viewer := Vector2(viewer_position.x - unit_position.x, viewer_position.z - unit_position.z)
	if to_viewer.length_squared() < _MIN_VIEWER_DISTANCE_SQUARED:
		return
	if _dying:
		return
	_apply_view(LFDirectionalView.resolve(facing_xz, to_viewer, front_half_width_deg))


## Starts (`value` true) or ends (false) the death animation.
## Entering always restarts `<view>_<die_segment>` from its first frame in the
## last resolved view, even when the sprite still holds a finished death animation from
## an earlier use (pooled reuse). Without that animation the sprite is stopped on its
## current frame. Leaving (false) goes straight back to the state's loop.
func set_dying(value: bool) -> void:
	_dying = value
	_applied_view = -1
	if sprite == null:
		return
	if _dying:
		sprite.stop()
		var animation := LFDirectionalView.animation_name(_last_view, die_segment, mirror_sides)
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation):
			sprite.flip_h = LFDirectionalView.is_mirrored(_last_view, mirror_sides)
			sprite.play(animation)
	else:
		_apply_view(_last_view, true)


## Returns the seconds the death animation of the last resolved view takes to play once at
## the sprite's `speed_scale` (frame count / fps when every frame has the default
## duration); 0 when there is no sprite, no frames, no such animation, no fps or a zero
## `speed_scale`, so the caller can fall back to its own delay.
func dying_duration() -> float:
	if sprite == null or sprite.sprite_frames == null:
		return 0.0
	var frames := sprite.sprite_frames
	var animation := LFDirectionalView.animation_name(_last_view, die_segment, mirror_sides)
	if not frames.has_animation(animation):
		return 0.0
	var rate := frames.get_animation_speed(animation) * absf(sprite.speed_scale)
	if rate <= 0.0:
		return 0.0
	var length := 0.0
	for i in frames.get_frame_count(animation):
		length += frames.get_frame_duration(animation, i)
	return length / rate


## `restart` plays the animation even when the sprite already holds its name: a death
## with no death animation stopped the sprite without changing it. Only an applied view is
## recorded; a missing animation is looked up again on every call.
func _apply_view(view: LFDirectionalView.View, restart := false) -> void:
	_last_view = view
	if sprite == null:
		return
	if view == _applied_view and state == _applied_state and sprite.sprite_frames == _applied_frames:
		return
	var animation := LFDirectionalView.animation_name(view, state, mirror_sides)
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation):
		# Not recorded: the next update looks again, so art added later is picked up.
		return
	_applied_view = view
	_applied_state = state
	_applied_frames = sprite.sprite_frames
	sprite.flip_h = LFDirectionalView.is_mirrored(view, mirror_sides)
	if restart or sprite.animation != animation:
		sprite.play(animation)
