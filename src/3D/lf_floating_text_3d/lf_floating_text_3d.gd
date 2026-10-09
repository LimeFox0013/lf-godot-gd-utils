## Floating text in the 3D world that rises, fades out and then deletes itself.
##
## Call `spawn`; you never create or free one yourself. The text is a billboard
## (it always faces the camera), spawned above a point; it rises while it fades out,
## outline included, then frees itself. Use it for numbers, a short label, a single word
## and any short feedback over a 3D position.
class_name LFFloatingText3D
extends Label3D

## Default `rise`: how far the label rises while it fades, in world units.
const DEFAULT_RISE := 1.0
## Default `duration`: how long the label rises and fades, in seconds.
const DEFAULT_DURATION := 0.8
## Default `height`: how far above `at` the label starts, in world units.
const DEFAULT_HEIGHT := 1.2
## Default `label_font_size`, in pixels.
const DEFAULT_FONT_SIZE := 48
## Default `outline`: the outline thickness, in pixels.
const DEFAULT_OUTLINE_SIZE := 8

## The animated property path of the label's height.
const _PROPERTY_POSITION_Y := "position:y"
## The animated property path of the label's fade (0 opaque, 1 invisible).
const _PROPERTY_TRANSPARENCY := "transparency"


## Adds a label reading `label_text`, tinted `color`, to `parent`,
## `height` units above `at` (a position in the parent's space). The label
## always faces the camera and draws over all other geometry. It rises `rise` units
## while fading out over `duration` seconds, then frees itself.
## `label_font_size` is the font size in pixels, `outline` the outline
## thickness in pixels.
## Returns the label, still animating; leave its position and transparency to it.
## `parent` must be a valid node; the label lives and dies with it, and animates only
## while `parent` is in the scene tree.
static func spawn(parent: Node, at: Vector3, label_text: String, color: Color, rise := DEFAULT_RISE, duration := DEFAULT_DURATION, height := DEFAULT_HEIGHT, label_font_size := DEFAULT_FONT_SIZE, outline := DEFAULT_OUTLINE_SIZE) -> Label3D:
	var label := LFFloatingText3D.new()
	label.text = label_text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = label_font_size
	label.outline_size = outline
	label.position = at + Vector3(0.0, height, 0.0)
	parent.add_child(label)
	# `transparency`, not `modulate:a`: it fades the outline too, and a Label3D rebuilds
	# its text mesh on every modulate change, which adds up with many labels.
	LFAnimate.one_shot(label, {_PROPERTY_POSITION_Y: label.position.y + rise, _PROPERTY_TRANSPARENCY: 1.0}, duration)
	return label
