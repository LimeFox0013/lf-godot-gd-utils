## One picture layer of an LFParallaxControl: a TextureRect with its own speed.
##
## Add it as a direct child of an LFParallaxControl. `motion_scale` sets how far this
## layer moves for the control's shared shift: small for far-away layers (sky), large for
## near ones.
class_name LFParallaxLayer
extends TextureRect

## How far this layer moves per unit of the shared shift, per axis: (0.2, 0.2) moves at a
## fifth of the speed, (1, 1) at full speed. Used by `LFParallaxControl.move` only.
@export var motion_scale := Vector2(1.0, 1.0)
