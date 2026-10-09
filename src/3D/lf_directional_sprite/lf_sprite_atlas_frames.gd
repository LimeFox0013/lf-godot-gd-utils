## Turns one big sprite-sheet image plus a small JSON file into ready-to-play SpriteFrames.
##
## A static helper: never instantiate it, call its functions on the class name.
## Builds SpriteFrames at runtime from a character atlas (the sprite sheet) and its JSON
## manifest (one row per animation and direction, fixed-size frames), named for LFDirectionalSprite3D with
## sides authored (`front_walk`, `side_l_walk`, ...). Built frames are cached per path
## and options and parsed manifests per path, so every instance of a character asking
## with the same options shares one SpriteFrames. Also
## crops a frame to its opaque pixels, for icons and portraits cut from the same atlas.
class_name LFSpriteAtlasFrames

## Manifest direction -> view segment: `down` faces the camera (front), `up` faces away
## (back), `right` and `left` are the two authored sides.
const DEFAULT_DIRECTION_SEGMENTS := {
	"down": LFDirectionalView.SEGMENT_FRONT,
	"up": LFDirectionalView.SEGMENT_BACK,
	"right": LFDirectionalView.SEGMENT_SIDE_R,
	"left": LFDirectionalView.SEGMENT_SIDE_L,
}

## Frames per second for an animation whose manifest entry has no `fps`.
const DEFAULT_FPS := 5.0

## Manifest key: the width of one frame, in pixels.
const _KEY_FRAME_WIDTH := "frameWidth"
## Manifest key: the height of one frame, in pixels.
const _KEY_FRAME_HEIGHT := "frameHeight"
## Manifest key: the object of animations, by animation name.
const _KEY_ANIMATIONS := "animations"
## Animation key: its direction -> atlas row (0-based) map.
const _KEY_ROWS := "rows"
## Animation key: its frame count per row.
const _KEY_FRAMES := "frames"
## Animation key (optional): direction -> frame count, overriding `frames` for that row.
const _KEY_FRAME_COUNTS := "frameCounts"
## Animation key (optional): its frames per second.
const _KEY_FPS := "fps"
## Animation key (optional): whether it loops.
const _KEY_LOOP := "loop"
## The atlas image's extension, replacing the manifest's.
const _ATLAS_EXTENSION := ".png"
## The cache key of built frames: manifest path, direction segments, forced loops.
const _CACHE_KEY_FORMAT := "%s|%s|%s"
## `<segment>_<animation>`: how an animation name joins its two parts.
const _ANIMATION_NAME_FORMAT := "%s_%s"
## The animation every new SpriteFrames starts with, removed by `build`.
const _BUILT_IN_ANIMATION := &"default"

## The most frames one `build` call adds, over all its animations; the rest are left out
## with one reported error.
const MAX_FRAMES := 16384

## Default `max_cached_images`.
const DEFAULT_MAX_CACHED_IMAGES := 2

## Most decompressed atlas images `atlas_image` keeps at once (process-wide). Each costs
## width x height x bytes per pixel of CPU memory: a 4096 x 4096 RGBA8 atlas is 64 MiB.
## Past it the least recently used image is dropped; 0 or less keeps none (every call
## reads the texture back). Lowering it drops the extra images at the next `atlas_image`
## call, one answered from the cache included.
static var max_cached_images := DEFAULT_MAX_CACHED_IMAGES

static var _frames_cache := {}
static var _manifests := {}
## Texture instance id -> [WeakRef to the texture, its readable Image], for `atlas_image`,
## least recently used first.
static var _images := {}


## Returns the SpriteFrames for the manifest at `manifest_path` and the atlas image beside it
## (same path, `.png`), built once per path and options and then shared. Null when the
## manifest or the atlas cannot be loaded, which callers can treat as "no art yet"; that
## null is not cached, so art added later is found by the next call. A manifest of the
## wrong shape (see `build`) also gives null, with an error. See `build` for
## `direction_segments` and `force_loop`.
static func from_manifest(manifest_path: String, direction_segments: Dictionary = DEFAULT_DIRECTION_SEGMENTS, force_loop: Array = []) -> SpriteFrames:
	var key := _CACHE_KEY_FORMAT % [manifest_path, direction_segments, force_loop]
	if _frames_cache.has(key):
		return _frames_cache[key]
	var manifest := read_manifest(manifest_path)
	if manifest.is_empty():
		return null
	var texture := _load_atlas(manifest_path.get_basename() + _ATLAS_EXTENSION)
	if texture == null:
		return null
	var frames := build(manifest, texture, direction_segments, force_loop)
	if frames != null:
		_frames_cache[key] = frames
	return frames


## Returns the parsed manifest at `manifest_path`, read once and then shared (treat it as
## read-only); empty when the file is missing or is not a JSON object. An empty result is
## not cached, so a manifest written later is found by the next call (and every call for
## a missing file checks the file again).
static func read_manifest(manifest_path: String) -> Dictionary:
	if _manifests.has(manifest_path):
		return _manifests[manifest_path]
	var manifest := LFFile.load_json(manifest_path, false)
	if not manifest.is_empty():
		_manifests[manifest_path] = manifest
	return manifest


## Builds SpriteFrames from a parsed `manifest` and its `atlas_texture`: one animation
## `<segment>_<animation>` per animation and per direction row whose direction is in
## `direction_segments` (other rows are skipped; when two rows map to the same segment,
## the first in the manifest wins). Animations named in `force_loop` loop
## whatever the manifest says (a motion the character repeats, for example). The
## `default` animation is removed. Not cached: every call builds new frames. A manifest
## missing a required key (`frameWidth`, `frameHeight`, `animations`, `rows`, `frames`) or
## holding a value of the wrong type (a number where an object belongs, a string where a
## number belongs) reports an error and returns null. A frame size that is not positive
## reports an error and builds no animations. With an `atlas_texture`, a row's frame count
## is cut to the frames that fit across the texture's width. At most `MAX_FRAMES` frames are
## built in all (one error is reported when the manifest asks for more), so a manifest
## cannot ask for an unbounded number, with or without a texture.
static func build(manifest: Dictionary, atlas_texture: Texture2D, direction_segments: Dictionary = DEFAULT_DIRECTION_SEGMENTS, force_loop: Array = []) -> SpriteFrames:
	var problem := _manifest_problem(manifest)
	if not problem.is_empty():
		push_error("LFSpriteAtlasFrames.build: invalid manifest: " + problem)
		return null
	var frames := SpriteFrames.new()
	frames.remove_animation(_BUILT_IN_ANIMATION)
	var frame_size := Vector2(float(manifest[_KEY_FRAME_WIDTH]), float(manifest[_KEY_FRAME_HEIGHT]))
	if not (frame_size.x > 0.0 and frame_size.y > 0.0):
		push_error("LFSpriteAtlasFrames.build: frameWidth and frameHeight must be positive")
		return frames
	var fit := 0x7fffffff
	if atlas_texture != null:
		fit = int(atlas_texture.get_width() / frame_size.x)
	var added := 0
	var over_cap := false
	var animations: Dictionary = manifest[_KEY_ANIMATIONS]
	for animation_name: Variant in animations:
		var animation: Dictionary = animations[animation_name]
		var rows: Dictionary = animation[_KEY_ROWS]
		var frame_counts: Dictionary = animation.get(_KEY_FRAME_COUNTS, {})
		for direction: Variant in rows:
			if not direction_segments.has(direction):
				continue
			var name := _ANIMATION_NAME_FORMAT % [direction_segments[direction], animation_name]
			if frames.has_animation(name):
				continue
			frames.add_animation(name)
			frames.set_animation_speed(name, float(animation.get(_KEY_FPS, DEFAULT_FPS)))
			frames.set_animation_loop(name, bool(animation.get(_KEY_LOOP, false)) or force_loop.has(animation_name))
			var row_y: float = float(rows[direction]) * frame_size.y
			var count := mini(int(frame_counts.get(direction, animation[_KEY_FRAMES])), fit)
			if added + maxi(count, 0) > MAX_FRAMES:
				if not over_cap:
					push_error("LFSpriteAtlasFrames.build: the manifest asks for more than %d frames; the rest are left out" % MAX_FRAMES)
					over_cap = true
				count = MAX_FRAMES - added
				added = MAX_FRAMES
			else:
				added += maxi(count, 0)
			for i in count:
				frames.add_frame(name, atlas(atlas_texture, Rect2(Vector2(i * frame_size.x, row_y), frame_size)))
	return frames


## Returns what is wrong with `manifest`'s shape, or an empty string when `build` can read it.
static func _manifest_problem(manifest: Dictionary) -> String:
	for key: Variant in [_KEY_FRAME_WIDTH, _KEY_FRAME_HEIGHT]:
		if not _is_number(manifest.get(key)):
			return '"%s" must be a number' % key
	if not manifest.get(_KEY_ANIMATIONS) is Dictionary:
		return '"%s" must be an object' % _KEY_ANIMATIONS
	var animations: Dictionary = manifest[_KEY_ANIMATIONS]
	for animation_name: Variant in animations:
		var animation: Variant = animations[animation_name]
		if not animation is Dictionary:
			return 'animation "%s" must be an object' % animation_name
		if not animation.get(_KEY_ROWS) is Dictionary:
			return 'animation "%s": "%s" must be an object' % [animation_name, _KEY_ROWS]
		if not _is_number(animation.get(_KEY_FRAMES)):
			return 'animation "%s": "%s" must be a number' % [animation_name, _KEY_FRAMES]
		if animation.has(_KEY_FRAME_COUNTS) and not animation[_KEY_FRAME_COUNTS] is Dictionary:
			return 'animation "%s": "%s" must be an object' % [animation_name, _KEY_FRAME_COUNTS]
		if animation.has(_KEY_FPS) and not _is_number(animation[_KEY_FPS]):
			return 'animation "%s": "%s" must be a number' % [animation_name, _KEY_FPS]
		for direction: Variant in animation[_KEY_ROWS]:
			if not _is_number(animation[_KEY_ROWS][direction]):
				return 'animation "%s": row "%s" must be a number' % [animation_name, direction]
			if animation.has(_KEY_FRAME_COUNTS) and animation[_KEY_FRAME_COUNTS].has(direction) and not _is_number(animation[_KEY_FRAME_COUNTS][direction]):
				return 'animation "%s": frame count of "%s" must be a number' % [animation_name, direction]
	return ""


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## Returns a new AtlasTexture showing the `region` (in pixels) of `texture`.
static func atlas(texture: Texture2D, region: Rect2) -> AtlasTexture:
	var region_texture := AtlasTexture.new()
	region_texture.atlas = texture
	region_texture.region = region
	return region_texture


## Returns `frame` (a region of `texture`, in pixels) cropped to its opaque pixels, so a
## character fills an icon instead of floating in the frame's empty padding. The whole
## `frame` when it is empty, the pixels cannot be read or the frame is fully transparent. Reads the
## pixels through `atlas_image`, so cropping several frames of one atlas in a row reads it
## back once.
static func opaque_region(texture: Texture2D, frame: Rect2) -> Rect2:
	if not (frame.size.x > 0.0 and frame.size.y > 0.0):
		return frame
	var image := atlas_image(texture)
	if image == null:
		return frame
	var used := image.get_region(Rect2i(frame)).get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return frame
	return Rect2(frame.position + Vector2(used.position), Vector2(used.size))


## Returns the pixels of `texture` as a decompressed Image (treat it as read-only), read
## back with `get_image()` unless one of the last `max_cached_images` textures read was
## this one, whose copy is shared instead. A copy is dropped when its texture emits
## `changed` (for example `ImageTexture.set_image`), when it becomes the least recently
## used past `max_cached_images`, when its texture is freed (dropped the next time this
## reads a texture back), and
## by `clear_cache()`; a change that emits nothing (such as `ImageTexture.update`) needs
## `clear_cache()`. Null for a null texture or one whose pixels cannot be read.
static func atlas_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var id := texture.get_instance_id()
	var cached: Array = _images.get(id, [])
	if not cached.is_empty() and (cached[0] as WeakRef).get_ref() == texture:
		# Re-inserted, so it becomes the most recently used.
		_images.erase(id)
		_images[id] = cached
		_trim_images()
		return cached[1]
	var image := texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	_prune_images()
	if max_cached_images <= 0:
		_images.clear()
		return image
	_images[id] = [weakref(texture), image]
	_trim_images()
	var forget := _forget_image.bind(id)
	if not texture.changed.is_connected(forget):
		texture.changed.connect(forget, CONNECT_ONE_SHOT)
	return image


## Forgets every cached manifest, SpriteFrames and atlas image, so the next call reads
## the files again (after the files changed, or between tests). Leaves
## `max_cached_images` as it is.
static func clear_cache() -> void:
	_frames_cache.clear()
	_manifests.clear()
	_images.clear()


## Drops the least recently used images until at most `max_cached_images` are left (none
## when it is 0 or less).
static func _trim_images() -> void:
	while not _images.is_empty() and _images.size() > max_cached_images:
		_images.erase(_images.keys()[0])


static func _forget_image(id: int) -> void:
	_images.erase(id)


static func _prune_images() -> void:
	for id: int in _images.keys():
		if (_images[id][0] as WeakRef).get_ref() == null:
			_images.erase(id)


static func _load_atlas(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			return ImageTexture.create_from_image(image)
	return null
