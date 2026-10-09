## Works out which side of a 2D character (front, back, left or right) the camera sees in a 3D world.
##
## A static helper: never instantiate it, call its functions on the class name.
## Pure angle math for directional billboard sprites (flat images that always face the
## camera): which of four views a viewer sees of a character, given the character's
## facing and the direction from the character to the viewer, both flattened to one 2D
## plane; and the animation name for a view and a state segment (`front_walk`,
## `side_run`).
## With mirrored sides one authored side serves both: the left view is the right one
## flipped. It takes plain vectors, so one character can be resolved for any number of
## viewers (a split screen, every client of a multiplayer game) from the same facing.
class_name LFDirectionalView

## The four views. SIDE_R is the authored side (the one drawn by the artist); SIDE_L
## reuses it flipped when sides are mirrored.
enum View {
	FRONT,
	SIDE_L,
	SIDE_R,
	BACK,
}

## Half the angle of the front wedge (and of the back wedge) in degrees: 45 splits the
## circle into four equal 90 degree quadrants.
const DEFAULT_FRONT_HALF_WIDTH_DEG := 45.0

## Slack in degrees on the wedge boundaries, so a direction rotated by exactly the half
## width still counts as front (or back) despite float rounding.
const _BOUNDARY_EPSILON_DEG := 0.001
## A half turn, in degrees: straight behind the facing.
const _HALF_TURN_DEG := 180.0
## `<view segment>_<state>`: how an animation name joins its two parts.
const _ANIMATION_NAME_FORMAT := "%s_%s"

## The name segment of the FRONT view.
const SEGMENT_FRONT := "front"
## The name segment of the BACK view.
const SEGMENT_BACK := "back"
## The name segment of both sides when they are mirrored.
const SEGMENT_SIDE := "side"
## The name segment of the left side when each side is authored.
const SEGMENT_SIDE_L := "side_l"
## The name segment of the right side when each side is authored.
const SEGMENT_SIDE_R := "side_r"


## Returns the view a viewer gets. `facing` is the character's heading and `to_viewer` points
## from the character toward the viewer, both in the same 2D plane (for a 3D world,
## usually XZ). FRONT when the viewer stands within `front_half_width_deg` of where the
## character looks, BACK within the same angle of straight behind, otherwise SIDE_R or
## SIDE_L by the sign of the angle from `facing` to `to_viewer`. Boundaries count as
## front and back. A zero vector counts as angle 0 (FRONT).
static func resolve(facing: Vector2, to_viewer: Vector2, front_half_width_deg := DEFAULT_FRONT_HALF_WIDTH_DEG) -> View:
	var signed_angle_deg: float = rad_to_deg(facing.angle_to(to_viewer))
	var abs_angle_deg: float = absf(signed_angle_deg)
	if abs_angle_deg <= front_half_width_deg + _BOUNDARY_EPSILON_DEG:
		return View.FRONT
	if abs_angle_deg >= _HALF_TURN_DEG - front_half_width_deg - _BOUNDARY_EPSILON_DEG:
		return View.BACK
	return View.SIDE_R if signed_angle_deg > 0.0 else View.SIDE_L


## Returns true when `view` is drawn by flipping the authored side: SIDE_L with mirrored
## sides. Use it for `flip_h`.
static func is_mirrored(view: View, mirror_sides := true) -> bool:
	return mirror_sides and view == View.SIDE_L


## Returns the view's name segment: `front`, `back`, and `side` for both sides when they are
## mirrored, or `side_l` / `side_r` when each side is authored.
static func segment(view: View, mirror_sides := true) -> String:
	match view:
		View.BACK:
			return SEGMENT_BACK
		View.SIDE_L:
			return SEGMENT_SIDE if mirror_sides else SEGMENT_SIDE_L
		View.SIDE_R:
			return SEGMENT_SIDE if mirror_sides else SEGMENT_SIDE_R
	return SEGMENT_FRONT


## Returns the animation to play: `<view segment>_<state>`, for example `front_idle`,
## `side_walk` (mirrored) or `side_l_run` (sides authored).
static func animation_name(view: View, state: StringName, mirror_sides := true) -> String:
	return _ANIMATION_NAME_FORMAT % [segment(view, mirror_sides), state]
