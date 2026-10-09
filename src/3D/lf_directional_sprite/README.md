# LFDirectionalView, LFDirectionalSprite3D, LFSpriteAtlasFrames

> Flat 2D characters in a 3D world that show the right drawing (front, back, left or right) for where the camera stands, with animations built from one sprite sheet and a small JSON file.

| | |
|---|---|
| **Files** | `lf_directional_view.gd`, `lf_directional_sprite_3d.gd`, `lf_sprite_atlas_frames.gd` |
| **Tests** | `tests/test_lf_directional_view.gd`, `tests/test_lf_directional_sprite_3d.gd`, `tests/test_lf_sprite_atlas_frames.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFFile` (manifest reading) |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFDirectionalView` | Static: call it on the class name |
| `LFDirectionalSprite3D` | Node: add it to a scene |
| `LFSpriteAtlasFrames` | Static: call it on the class name |

## When to use it

Use it for 2D characters in a 3D world (RTS billboards, 2D-sprites-in-3D, "paper" characters, a
retro-shooter enemy): the artist draws each animation from the front, back and side, and the
game must show the right one for where the camera stands, flip the side for the other
direction, and not restart the animation every frame or when the camera orbits round a
dying unit. The three classes split those jobs so each can be used alone:
`LFDirectionalView` is the math (it works for any number of viewers, such as a split
screen, from the same facing), `LFDirectionalSprite3D` drives an `AnimatedSprite3D`, and
`LFSpriteAtlasFrames` slices a sprite-sheet into hundreds of frames from a JSON file
instead of a hand-kept `.tres` file. "Mirrored sides" means you draw only one side and the other is the same image flipped. For a character drawn from one angle only, a plain
`AnimatedSprite3D` with `billboard` enabled is enough; for 3D models use
`AnimationPlayer`.

## Step by step

Before you start: you need a **sprite sheet** (one PNG with every frame of every animation) and a
small text file describing it. Here the sheet is `res://art/hero.png`, 256 × 256 pixels:
four rows (top to bottom: the hero facing the camera, facing right, facing away, facing
left) of four 64 × 64 frames of an idle animation. Any placeholder art works to try it out.

1. Describe the sheet. In the FileSystem dock (bottom-left) right-click your `art` folder
   and choose *Create New → TextFile*, name it `hero.json` (it must sit beside
   `hero.png` and share its name), and paste:

   ```json
   {
     "frameWidth": 64,
     "frameHeight": 64,
     "animations": {
       "idle": { "frames": 4, "fps": 6, "loop": true,
                 "rows": { "down": 0, "right": 1, "up": 2, "left": 3 } }
     }
   }
   ```

   `frameWidth` and `frameHeight` are pixels per frame, `frames` is how many frames are in
   a row, `fps` is frames per second, and `rows` says which row of the sheet (counting
   from 0 at the top) shows each direction: `down` is facing the camera.
2. *Scene → New Scene*, click **3D Scene** under "Create Root Node", rename the root
   `Hero`.
3. Select `Hero`, click **+ Add Child Node**, search `LFDirectionalSprite3D`, press
   *Create* and rename it `Look`. With `Look` selected add a child `AnimatedSprite3D`.
   In the Inspector (the property panel on the right) set the sprite's *Pixel Size* to
   `0.015` (world units per image pixel) and, under *Flags*, set *Billboard* to
   **Enabled** (the image then always faces the camera).
4. Select `Look`. In the Inspector find *Sprite* and drag the `AnimatedSprite3D` node
   from the Scene dock onto it. Untick *Mirror Sides*: the sheet has both sides drawn.
5. Add a `Camera3D` as a child of `Hero` with *Position* `0, 0.5, 3`.
6. Select `Hero`, click **Attach Script** (above the Scene dock), *Create*, and replace the
   contents with:

   ```gdscript
   extends Node3D

   @onready var look: LFDirectionalSprite3D = $Look

   var _turn := 0.0  # how far the hero has turned, in radians


   func _ready() -> void:
   	# Read hero.json and hero.png and build all the animations (front_idle, side_r_idle...).
   	look.sprite.sprite_frames = LFSpriteAtlasFrames.from_manifest("res://art/hero.json")


   func _process(delta: float) -> void:
   	# `delta` is the seconds since the last frame. Turn the hero slowly on the spot.
   	_turn += delta
   	# Which way the hero faces on the ground: x is world X, y is world Z.
   	look.facing_xz = Vector2.UP.rotated(_turn)
   	# Tell it where the camera stands; it plays the matching drawing.
   	look.update_view(global_position, $Camera3D.global_position)
   ```
7. Press **F6** (*Run Current Scene*) and save when asked. The hero spins slowly and the
   picture switches between your front, side, back and other side drawings. The first view
   you see is the back (the hero starts facing away from the camera).
8. In your own game: set `look.state = &"walk"` (or any animation name from the JSON; the `&` makes
   a StringName, a name used as an id) to change what plays, and push the real facing into `facing_xz` (see Usage).

## API

Everything the three classes offer; you only need the rows used above to get started.

### LFDirectionalView (static)

| Member | Signature | Description |
|---|---|---|
| `View` | `enum { FRONT, SIDE_L, SIDE_R, BACK }` | The four views. `SIDE_R` is the authored side; `SIDE_L` is it flipped when sides are mirrored. |
| `DEFAULT_FRONT_HALF_WIDTH_DEG` | `const DEFAULT_FRONT_HALF_WIDTH_DEG := 45.0` | Half the front (and back) wedge: 45 gives four equal quadrants. |
| `SEGMENT_FRONT`, `SEGMENT_BACK` | `const SEGMENT_FRONT := "front"`, `const SEGMENT_BACK := "back"` | The name segments of the front and back views. |
| `SEGMENT_SIDE` | `const SEGMENT_SIDE := "side"` | The name segment of both sides when they are mirrored. |
| `SEGMENT_SIDE_L`, `SEGMENT_SIDE_R` | `const SEGMENT_SIDE_L := "side_l"`, `const SEGMENT_SIDE_R := "side_r"` | The name segments of each side when both are authored. |
| `resolve` | `static resolve(facing: Vector2, to_viewer: Vector2, front_half_width_deg := DEFAULT_FRONT_HALF_WIDTH_DEG) -> View` | `facing` is the heading, `to_viewer` points from the character to the viewer, both in one 2D plane (XZ for 3D). FRONT/BACK within the half width of ahead/behind (boundaries included), else SIDE_R / SIDE_L by the sign of the angle. |
| `is_mirrored` | `static is_mirrored(view: View, mirror_sides := true) -> bool` | True for SIDE_L with mirrored sides. |
| `segment` | `static segment(view: View, mirror_sides := true) -> String` | `front`, `back`, `side` (mirrored) or `side_l` / `side_r`. |
| `animation_name` | `static animation_name(view: View, state: StringName, mirror_sides := true) -> String` | `<segment>_<state>`: `front_idle`, `side_walk`, `side_l_die`. |

### LFDirectionalSprite3D (Node3D)

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_DIE_SEGMENT` | `const DEFAULT_DIE_SEGMENT: StringName = &"die"` | Default `die_segment`. |
| `DEFAULT_STATE` | `const DEFAULT_STATE: StringName = &"idle"` | Default `state`. |
| `sprite` | `@export var sprite: AnimatedSprite3D` | The sprite to drive; null makes every call a no-op. |
| `mirror_sides` | `@export var mirror_sides: bool = true` | One authored side, flipped for the left view; false when both sides are authored. |
| `front_half_width_deg` | `@export var front_half_width_deg: float = LFDirectionalView.DEFAULT_FRONT_HALF_WIDTH_DEG` (45.0) | Passed to `LFDirectionalView.resolve`. |
| `die_segment` | `@export var die_segment: StringName = DEFAULT_DIE_SEGMENT` (`&"die"`) | State segment of the one-shot death animation. |
| `facing_xz` | `var facing_xz := Vector2.UP` | Heading on XZ (x = world x, y = world z); `Vector2.UP` faces -Z. Pushed in by the caller. |
| `state` | `var state: StringName = DEFAULT_STATE` (`&"idle"`) | State segment of the looping animation; applied on the next `update_view`. |
| `dying` | `var dying: bool` (read-only) | True while the death animation plays. |
| `update_view` | `update_view(unit_position: Vector3, viewer_position: Vector3) -> void` | Resolves the view for that viewer and plays `<view>_<state>` (flipping for a mirrored side). No-op when the viewer is on the character or while dying. |
| `set_dying` | `set_dying(value: bool) -> void` | true: restarts `<last view>_<die_segment>` from frame 0, or, when that animation is missing, stops the sprite on its current frame; false: back to the state's loop. |
| `dying_duration` | `dying_duration() -> float` | Seconds the death animation takes once at the sprite's `speed_scale` (frames / fps with default frame durations); 0 when it does not exist. |

### LFSpriteAtlasFrames (static)

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_DIRECTION_SEGMENTS` | `const DEFAULT_DIRECTION_SEGMENTS := {...}` | `{down: front, up: back, right: side_r, left: side_l}`. |
| `DEFAULT_FPS` | `const DEFAULT_FPS := 5.0` | Used when an animation has no `fps`. |
| `DEFAULT_MAX_CACHED_IMAGES` | `const DEFAULT_MAX_CACHED_IMAGES := 2` | Default `max_cached_images`. |
| `max_cached_images` | `static var max_cached_images := DEFAULT_MAX_CACHED_IMAGES` (2) | Most decompressed atlas images `atlas_image` keeps (least recently used dropped first); 0 or less keeps none. Lowering it drops the extra images at the next `atlas_image` call, one answered from the cache included. Process-wide. |
| `from_manifest` | `static from_manifest(manifest_path: String, direction_segments: Dictionary = DEFAULT_DIRECTION_SEGMENTS, force_loop: Array = []) -> SpriteFrames` | Builds from the manifest and the `.png` beside it (same base name), cached per path and options. Null when either cannot be loaded or the manifest is of the wrong shape (see `build`); a null is not cached. |
| `read_manifest` | `static read_manifest(manifest_path: String) -> Dictionary` | The parsed manifest, cached per path (read-only); empty when missing or not a JSON object. An empty result is not cached (the file is checked again on the next call). |
| `build` | `static build(manifest: Dictionary, atlas_texture: Texture2D, direction_segments: Dictionary = DEFAULT_DIRECTION_SEGMENTS, force_loop: Array = []) -> SpriteFrames` | One animation `<segment>_<animation>` per animation and mapped direction row (two rows mapped to one segment: the first wins); `force_loop` names loop whatever the manifest says. Removes `default`. Not cached. A missing key or a value of the wrong type (see *Manifest format*) reports an error and returns null. |
| `atlas` | `static atlas(texture: Texture2D, region: Rect2) -> AtlasTexture` | An AtlasTexture of `region`. |
| `opaque_region` | `static opaque_region(texture: Texture2D, frame: Rect2) -> Rect2` | `frame` cropped to its opaque pixels, read through `atlas_image` (several frames of one atlas in a row: one read-back); the whole frame when it is empty, unreadable or fully transparent. |
| `atlas_image` | `static atlas_image(texture: Texture2D) -> Image` | The texture's pixels as a decompressed Image (read-only), shared while the texture is among the last `max_cached_images` read, else read back. Dropped when the texture emits `changed`, when least recently used past `max_cached_images`, and by `clear_cache()`; null when unreadable. |
| `clear_cache` | `static clear_cache() -> void` | Forgets cached manifests, frames and atlas images. |

## Manifest format

```json
{
  "frameWidth": 128,
  "frameHeight": 128,
  "animations": {
    "idle":   { "frames": 6, "fps": 8,  "loop": true,  "rows": { "down": 0, "right": 1, "up": 2, "left": 3 } },
    "attack": { "frames": 9, "fps": 14, "loop": false, "rows": { "down": 4, "right": 5, "up": 6, "left": 7 },
                "frameCounts": { "left": 7 } }
  }
}
```

- `frameWidth`, `frameHeight` (required): the size of every frame in pixels.
- `animations` (required): animation name → entry. The name becomes the state segment (`front_idle`).
- `rows` (required): direction → row index in the atlas. Frame `i` of a row is at `(i * frameWidth, row * frameHeight)`. Directions missing from `direction_segments` are skipped.
- `frames` (required): frames per row (cut to the frames that fit across the atlas's width; `MAX_FRAMES` (16384) frames at most per `build`, one error reported beyond that). `frameCounts` (optional): direction → a shorter count for that row.
- `fps` (default 5) and `loop` (default false).
- Numbers must be JSON numbers and `animations`, each animation, `rows` and `frameCounts` must be objects; anything else makes `build` report an error and return null.
- Other keys (an anchor, a direction list) are ignored and can be read through `read_manifest`.
- The atlas is the `.png` with the manifest's base name (`hero.json` → `hero.png`): an imported resource when there is one, else the raw file.

## Usage

A more complete character: walking, idle, a looping attack and a death, on a `CharacterBody3D` (a physics-moved character node). Scene:

```
Hero (CharacterBody3D)      <- this script
├── CollisionShape3D
└── Look (Node3D with lf_directional_sprite_3d.gd; its `sprite` set to the child below)
    └── AnimatedSprite3D
```

`res://art/hero.json` is a manifest in the format above, with `res://art/hero.png` beside
it.

```gdscript
extends CharacterBody3D

@onready var look: LFDirectionalSprite3D = $Look


func _ready() -> void:
	# Build (or reuse) the frames; "attack" loops so a repeated swing keeps animating.
	var frames := LFSpriteAtlasFrames.from_manifest("res://art/hero.json", LFSpriteAtlasFrames.DEFAULT_DIRECTION_SEGMENTS, ["attack"])
	look.sprite.sprite_frames = frames
	look.mirror_sides = false  # the atlas has both sides drawn


func _process(_delta: float) -> void:
	var moving := velocity.length() > 0.1
	if moving:
		look.facing_xz = Vector2(velocity.x, velocity.z)
	look.state = &"walk" if moving else &"idle"
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		look.update_view(global_position, camera.global_position)


func die() -> void:
	look.set_dying(true)
	# `await` means "wait here until this finishes": the death animation (or half a
	# second when there is none), then remove the hero.
	await get_tree().create_timer(maxf(look.dying_duration(), 0.5)).timeout
	queue_free()
```

To work out a view without the sprite driver (for a minimap icon, or a server). These lines go inside a function of any script:

```gdscript
var view := LFDirectionalView.resolve(Vector2.UP, Vector2(1, 0))  # viewer to the right
print(LFDirectionalView.animation_name(view, &"walk"))             # "side_walk"
```

## Notes

- `LFDirectionalSprite3D` only calls `play()` when the animation changes, so a one-shot animation used as a repeated state (an attack swung again and again) freezes on its last frame after the first play: pass it in `force_loop`.
- `LFSpriteAtlasFrames` names animations with sides authored (`side_l_*`, `side_r_*`); set `mirror_sides = false` on the sprite for those frames, or pass `{"down": "front", "up": "back", "right": "side"}` as `direction_segments` to build mirrored ones (the `left` rows are then skipped).
- `.json` is not a Godot resource, so an exported game leaves it out by default. In *Project → Export*, open the *Resources* tab and add `*.json` to *Filters to export non-resource files/folders*.
- The frames and manifest caches are static and live for the process; call `clear_cache()` after changing a manifest on disk. A manifest that could not be read is not cached, so one written later is found without `clear_cache()`.
- Memory: `atlas_image` holds at most `max_cached_images` (default 2) decompressed atlas copies in CPU memory at once, each width × height × bytes per pixel (a 4096 × 4096 RGBA8 atlas is 64 MiB, so the default can hold 128 MiB). A copy is dropped when it is the least recently used past that limit, when its texture emits `changed`, when its texture is freed (dropped the next time `atlas_image` reads a texture back) or by `clear_cache()`. Cropping many frames of one atlas in a row reads it back once; alternating between more atlases than the limit reads each back every time. Changing pixels without `changed` (`ImageTexture.update`) needs `clear_cache()`.
- With no sprite, no frames or a missing animation the sprite driver leaves the sprite alone, so it can go in before the art does. The one exception: `set_dying(true)` without a death animation stops the sprite on its current frame. Frames assigned later, and an animation added later to the frames already assigned, are picked up on the next `update_view` (while the wanted animation is missing, every `update_view` looks it up again).
