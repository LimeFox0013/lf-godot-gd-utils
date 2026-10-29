extends GutTest

const DIR := "user://lf_sprite_atlas_frames_test"
const MANIFEST := {
	"frameWidth": 4,
	"frameHeight": 4,
	"animations": {
		"idle": {"frames": 2, "fps": 8, "loop": true, "rows": {"down": 0, "right": 1, "up": 2, "left": 3}},
		"action_a": {"frames": 3, "fps": 14, "loop": false, "rows": {"down": 4, "right": 5, "up": 6, "left": 7}},
	},
}


func before_each():
	LFSpriteAtlasFrames.clear_cache()


## Tests that change the process-wide limit get it back here, even when they fail early.
func after_each():
	LFSpriteAtlasFrames.max_cached_images = LFSpriteAtlasFrames.DEFAULT_MAX_CACHED_IMAGES


func after_all():
	LFSpriteAtlasFrames.clear_cache()
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	DirAccess.remove_absolute(DIR)


func _atlas() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(12, 32, false, Image.FORMAT_RGBA8))


func _write_character(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join(name + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(MANIFEST))
	file.close()
	Image.create(12, 32, false, Image.FORMAT_RGBA8).save_png(DIR.path_join(name + ".png"))
	return path


func test_names_animations_after_views_and_states():
	var frames := LFSpriteAtlasFrames.build(MANIFEST, _atlas())
	for animation in ["front_idle", "side_r_idle", "back_idle", "side_l_idle", "front_action_a", "side_l_action_a"]:
		assert_true(frames.has_animation(animation), animation)
	assert_false(frames.has_animation("default"))


func test_names_match_the_directional_view_with_authored_sides():
	var frames := LFSpriteAtlasFrames.build(MANIFEST, _atlas())
	var name := LFDirectionalView.animation_name(LFDirectionalView.View.SIDE_L, &"action_a", false)
	assert_true(frames.has_animation(name))


func test_frames_slice_each_directions_row():
	var frames := LFSpriteAtlasFrames.build(MANIFEST, _atlas())
	assert_eq(frames.get_frame_count("side_r_action_a"), 3)
	var second: AtlasTexture = frames.get_frame_texture("side_r_action_a", 1)
	assert_eq(second.region, Rect2(4, 5 * 4, 4, 4))
	assert_eq(frames.get_animation_speed("front_action_a"), 14.0)
	assert_true(frames.get_animation_loop("front_idle"))
	assert_false(frames.get_animation_loop("front_action_a"))


func test_frame_counts_shorten_single_direction_rows():
	var manifest := MANIFEST.duplicate(true)
	manifest["animations"]["action_a"]["frameCounts"] = {"right": 2}
	var frames := LFSpriteAtlasFrames.build(manifest, _atlas())
	assert_eq(frames.get_frame_count("side_r_action_a"), 2)
	assert_eq(frames.get_frame_count("front_action_a"), 3)


func test_force_loop_loops_an_animation_the_manifest_plays_once():
	var frames := LFSpriteAtlasFrames.build(MANIFEST, _atlas(), LFSpriteAtlasFrames.DEFAULT_DIRECTION_SEGMENTS, ["action_a"])
	assert_true(frames.get_animation_loop("front_action_a"))


func test_custom_direction_segments_rename_and_skip_rows():
	var frames := LFSpriteAtlasFrames.build(MANIFEST, _atlas(), {"down": "south"})
	assert_true(frames.has_animation("south_idle"))
	assert_false(frames.has_animation("front_idle"))
	assert_false(frames.has_animation("back_idle"), "unmapped directions are skipped")


func test_from_manifest_loads_the_atlas_beside_it_and_caches_the_frames():
	var path := _write_character("character_a")
	var frames := LFSpriteAtlasFrames.from_manifest(path)
	assert_not_null(frames)
	assert_eq(frames.get_frame_count("front_action_a"), 3)
	assert_same(LFSpriteAtlasFrames.from_manifest(path), frames)


func test_from_manifest_builds_separately_per_options():
	var path := _write_character("looping")
	var plain := LFSpriteAtlasFrames.from_manifest(path)
	var looped := LFSpriteAtlasFrames.from_manifest(path, LFSpriteAtlasFrames.DEFAULT_DIRECTION_SEGMENTS, ["action_a"])
	assert_ne(plain, looped)
	assert_false(plain.get_animation_loop("front_action_a"))
	assert_true(looped.get_animation_loop("front_action_a"))


func test_a_missing_manifest_gives_null():
	assert_null(LFSpriteAtlasFrames.from_manifest("res://does-not-exist.json"))
	assert_eq(LFSpriteAtlasFrames.read_manifest("res://does-not-exist.json"), {})


func test_a_manifest_is_parsed_once_and_shared():
	var path := _write_character("shared")
	var manifest := LFSpriteAtlasFrames.read_manifest(path)
	assert_eq(int(manifest["frameWidth"]), 4)
	assert_same(LFSpriteAtlasFrames.read_manifest(path), manifest)


func test_atlas_shows_a_region_of_the_texture():
	var texture := _atlas()
	var region := LFSpriteAtlasFrames.atlas(texture, Rect2(4, 8, 4, 4))
	assert_eq(region.atlas, texture)
	assert_eq(region.region, Rect2(4, 8, 4, 4))


func test_frame_region_is_the_frames_rect_in_the_atlas():
	assert_eq(LFSpriteAtlasFrames.frame_region(MANIFEST, "idle", "right"), Rect2(0, 4, 4, 4))
	assert_eq(LFSpriteAtlasFrames.frame_region(MANIFEST, "action_a", "up", 2), Rect2(8, 24, 4, 4))


func test_frame_region_is_null_for_a_missing_animation_direction_or_frame_size():
	assert_null(LFSpriteAtlasFrames.frame_region(MANIFEST, "nope", "down"))
	assert_null(LFSpriteAtlasFrames.frame_region(MANIFEST, "idle", "diagonal"))
	assert_null(LFSpriteAtlasFrames.frame_region({}, "idle", "down"))
	assert_null(LFSpriteAtlasFrames.frame_region({"animations": {"idle": {"rows": {"down": 0}}}}, "idle", "down"))
	assert_null(LFSpriteAtlasFrames.frame_region({"frameWidth": 4, "frameHeight": 4, "animations": {"idle": {"rows": 3}}}, "idle", "down"))


func test_frame_region_is_null_for_a_manifest_of_the_wrong_shape():
	assert_null(LFSpriteAtlasFrames.frame_region({"frameWidth": 4, "frameHeight": 4, "animations": 5}, "idle", "down"))
	assert_null(LFSpriteAtlasFrames.frame_region({"frameWidth": 4, "frameHeight": 4, "animations": {"idle": 7}}, "idle", "down"))
	assert_null(LFSpriteAtlasFrames.frame_region({"frameWidth": 4, "frameHeight": 4, "animations": {"idle": {"rows": {"down": "x"}}}}, "idle", "down"))


func test_frame_region_with_a_texture_is_cropped_to_opaque_pixels():
	var image := Image.create(12, 32, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(1, 5, 2, 1), Color.WHITE)
	var texture := ImageTexture.create_from_image(image)

	assert_eq(LFSpriteAtlasFrames.frame_region(MANIFEST, "idle", "right", 0, texture), Rect2(1, 5, 2, 1))


func test_opaque_region_crops_a_frame_to_its_opaque_pixels():
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(10, 2, 3, 4), Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	assert_eq(LFSpriteAtlasFrames.opaque_region(texture, Rect2(8, 0, 8, 8)), Rect2(10, 2, 3, 4))


func test_opaque_region_of_an_empty_frame_is_the_whole_frame():
	var texture := ImageTexture.create_from_image(Image.create(16, 8, false, Image.FORMAT_RGBA8))
	assert_eq(LFSpriteAtlasFrames.opaque_region(texture, Rect2(8, 0, 8, 8)), Rect2(8, 0, 8, 8))
	assert_eq(LFSpriteAtlasFrames.opaque_region(null, Rect2(0, 0, 4, 4)), Rect2(0, 0, 4, 4))


func test_opaque_region_reads_a_compressed_texture():
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(4, 4, 8, 8), Color.WHITE)
	image.compress(Image.COMPRESS_S3TC)
	var texture := ImageTexture.create_from_image(image)
	var region := LFSpriteAtlasFrames.opaque_region(texture, Rect2(0, 0, 16, 16))
	assert_eq(region, Rect2(4, 4, 8, 8))


func test_fps_and_loop_have_defaults():
	var manifest := {"frameWidth": 4, "frameHeight": 4, "animations": {"walk": {"frames": 1, "rows": {"down": 0}}}}
	var frames := LFSpriteAtlasFrames.build(manifest, _atlas())
	assert_eq(frames.get_animation_speed("front_walk"), LFSpriteAtlasFrames.DEFAULT_FPS)
	assert_false(frames.get_animation_loop("front_walk"))


func test_a_frame_count_is_cut_to_the_frames_that_fit_the_atlas_width():
	var manifest := {"frameWidth": 4, "frameHeight": 4, "animations": {"walk": {"frames": 1000000000, "rows": {"down": 0}}}}
	var frames := LFSpriteAtlasFrames.build(manifest, _atlas())
	assert_eq(frames.get_frame_count("front_walk"), 3)


func test_without_an_atlas_the_total_frame_count_is_capped():
	var manifest := {"frameWidth": 4, "frameHeight": 4, "animations": {"walk": {"frames": 1000000000, "rows": {"down": 0, "up": 1}}}}
	var started := Time.get_ticks_msec()
	var frames := LFSpriteAtlasFrames.build(manifest, null)
	assert_push_error("asks for more than")
	var total := 0
	for animation in frames.get_animation_names():
		total += frames.get_frame_count(animation)
	assert_eq(total, LFSpriteAtlasFrames.MAX_FRAMES)
	assert_lt(Time.get_ticks_msec() - started, 2000)


func test_a_manifest_within_the_cap_is_not_reported():
	var frames := LFSpriteAtlasFrames.build(MANIFEST, _atlas())
	assert_eq(frames.get_frame_count("front_idle"), 2)


func test_a_non_positive_frame_size_builds_nothing():
	var manifest := {"frameWidth": 0, "frameHeight": 4, "animations": {"walk": {"frames": 2, "rows": {"down": 0}}}}
	var frames := LFSpriteAtlasFrames.build(manifest, _atlas())
	assert_push_error("frameWidth and frameHeight must be positive")
	assert_eq(frames.get_animation_names().size(), 0)


func test_a_manifest_of_the_wrong_shape_gives_null_and_an_error_instead_of_a_script_error():
	var bad_manifests := [
		{},
		{"frameWidth": 4},
		{"frameWidth": "wide", "frameHeight": 4, "animations": {}},
		{"frameWidth": 4, "frameHeight": 4, "animations": []},
		{"frameWidth": 4, "frameHeight": 4, "animations": {"walk": 5}},
		{"frameWidth": 4, "frameHeight": 4, "animations": {"walk": {"frames": 2}}},
		{"frameWidth": 4, "frameHeight": 4, "animations": {"walk": {"rows": {"down": 0}}}},
		{"frameWidth": 4, "frameHeight": 4, "animations": {"walk": {"frames": 2, "rows": [0]}}},
		{"frameWidth": 4, "frameHeight": 4, "animations": {"walk": {"frames": "two", "rows": {"down": 0}}}},
		{"frameWidth": 4, "frameHeight": 4, "animations": {"walk": {"frames": 2, "rows": {"down": "top"}}}},
		{"frameWidth": 4, "frameHeight": 4, "animations": {"walk": {"frames": 2, "rows": {"down": 0}, "frameCounts": 1}}},
	]
	for manifest: Dictionary in bad_manifests:
		assert_null(LFSpriteAtlasFrames.build(manifest, _atlas()), str(manifest))
		assert_push_error("invalid manifest")


func test_from_manifest_gives_null_for_a_manifest_of_the_wrong_shape_and_does_not_cache_it():
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("shapeless.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"frameWidth": 4}')
	file.close()
	Image.create(12, 32, false, Image.FORMAT_RGBA8).save_png(DIR.path_join("shapeless.png"))
	assert_null(LFSpriteAtlasFrames.from_manifest(path))
	assert_push_error("invalid manifest")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(MANIFEST))
	file.close()
	LFSpriteAtlasFrames.clear_cache()
	assert_not_null(LFSpriteAtlasFrames.from_manifest(path), "a fixed manifest is built once it is read again")


func test_opaque_region_gives_the_whole_frame_for_an_empty_frame():
	var texture := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	var frame := Rect2(2, 2, 0, 0)
	assert_eq(LFSpriteAtlasFrames.opaque_region(texture, frame), frame)


func test_a_manifest_without_its_atlas_gives_null():
	var path := _write_character("no_atlas")
	DirAccess.remove_absolute(DIR.path_join("no_atlas.png"))
	assert_null(LFSpriteAtlasFrames.from_manifest(path))


func test_opaque_region_clips_a_frame_reaching_past_the_texture():
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(10, 2, 3, 4), Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	assert_eq(LFSpriteAtlasFrames.opaque_region(texture, Rect2(8, 0, 16, 16)), Rect2(10, 2, 3, 4))
	assert_eq(LFSpriteAtlasFrames.opaque_region(texture, Rect2(40, 40, 4, 4)), Rect2(40, 40, 4, 4), "wholly outside: the frame itself")


func test_clear_cache_makes_the_next_call_read_the_files_again():
	var path := _write_character("cleared")
	var frames := LFSpriteAtlasFrames.from_manifest(path)
	var manifest := LFSpriteAtlasFrames.read_manifest(path)
	LFSpriteAtlasFrames.clear_cache()
	assert_not_same(LFSpriteAtlasFrames.from_manifest(path), frames, "rebuilt after the cache is cleared")
	assert_not_same(LFSpriteAtlasFrames.read_manifest(path), manifest, "re-read after the cache is cleared")


func test_two_rows_mapped_to_one_segment_keep_the_first():
	var manifest := {"frameWidth": 4, "frameHeight": 4, "animations": {"walk": {"frames": 2, "rows": {"right": 0, "left": 1}}}}
	var frames := LFSpriteAtlasFrames.build(manifest, _atlas(), {"right": "side", "left": "side"})
	assert_eq(frames.get_frame_count("side_walk"), 2, 'not both rows appended')
	var first: AtlasTexture = frames.get_frame_texture("side_walk", 0)
	assert_eq(first.region.position.y, 0.0, 'the right row, listed first')



## An AtlasTexture builds a new Image on every `get_image()` (an ImageTexture under the
## headless renderer hands back one stored copy), so it shows whether the read is cached.
func _region_texture() -> AtlasTexture:
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(10, 2, 3, 4), Color.WHITE)
	return LFSpriteAtlasFrames.atlas(ImageTexture.create_from_image(image), Rect2(0, 0, 16, 8))


func test_the_atlas_is_read_back_once_per_texture():
	var texture := _region_texture()
	assert_not_same(texture.get_image(), texture.get_image(), 'every read-back is a new copy')

	var first := LFSpriteAtlasFrames.atlas_image(texture)

	assert_same(LFSpriteAtlasFrames.atlas_image(texture), first, 'one shared copy, not a read-back per call')
	assert_eq(LFSpriteAtlasFrames.opaque_region(texture, Rect2(8, 0, 8, 8)), Rect2(10, 2, 3, 4))
	assert_same(LFSpriteAtlasFrames.atlas_image(texture), first)
	assert_null(LFSpriteAtlasFrames.atlas_image(null))


func test_a_changed_texture_is_read_again():
	var texture := _region_texture()
	var first := LFSpriteAtlasFrames.atlas_image(texture)

	texture.region = Rect2(8, 0, 8, 8)

	var second := LFSpriteAtlasFrames.atlas_image(texture)
	assert_not_same(second, first, 'the texture emitted changed')
	assert_eq(second.get_size(), Vector2i(8, 8))
	assert_eq(LFSpriteAtlasFrames.opaque_region(texture, Rect2(0, 0, 8, 8)), Rect2(2, 2, 3, 4))


func test_clear_cache_drops_the_atlas_images():
	var texture := _region_texture()
	var first := LFSpriteAtlasFrames.atlas_image(texture)

	LFSpriteAtlasFrames.clear_cache()

	assert_not_same(LFSpriteAtlasFrames.atlas_image(texture), first)


func test_at_most_max_cached_images_are_kept_while_the_textures_live():
	var textures: Array[Texture2D] = []
	var images: Array[Image] = []
	for i in 5:
		textures.append(_region_texture())
		images.append(LFSpriteAtlasFrames.atlas_image(textures[i]))

	assert_eq(LFSpriteAtlasFrames.max_cached_images, 2)
	assert_same(LFSpriteAtlasFrames.atlas_image(textures[4]), images[4], 'the newest is still shared')
	assert_same(LFSpriteAtlasFrames.atlas_image(textures[3]), images[3])
	assert_not_same(LFSpriteAtlasFrames.atlas_image(textures[0]), images[0], 'the oldest was dropped although its texture lives')
	assert_not_same(LFSpriteAtlasFrames.atlas_image(textures[4]), images[4], 'reading the oldest again pushed the least recent out')


func test_a_cache_limit_of_zero_keeps_no_image():
	LFSpriteAtlasFrames.max_cached_images = 0
	var texture := _region_texture()

	var first := LFSpriteAtlasFrames.atlas_image(texture)

	assert_not_null(first)
	assert_not_same(LFSpriteAtlasFrames.atlas_image(texture), first)
	assert_eq(LFSpriteAtlasFrames.opaque_region(texture, Rect2(8, 0, 8, 8)), Rect2(10, 2, 3, 4))


func test_a_missing_manifest_is_not_cached_so_it_is_found_once_written():
	var path := DIR.path_join("late.json")
	DirAccess.remove_absolute(path)
	assert_eq(LFSpriteAtlasFrames.read_manifest(path), {})
	assert_null(LFSpriteAtlasFrames.from_manifest(path))

	_write_character("late")

	assert_eq(int(LFSpriteAtlasFrames.read_manifest(path).get("frameWidth", 0)), 4, 'no clear_cache needed')
	assert_not_null(LFSpriteAtlasFrames.from_manifest(path))


func test_from_manifest_uses_an_atlas_the_resource_loader_knows():
	var path := _write_character("loaded")
	DirAccess.remove_absolute(DIR.path_join("loaded.png"))
	var texture := _atlas()
	texture.take_over_path(DIR.path_join("loaded.png"))

	var frames := LFSpriteAtlasFrames.from_manifest(path)

	assert_not_null(frames, 'found through the resource loader, though no file is on disk')
	var first: AtlasTexture = frames.get_frame_texture("front_idle", 0)
	assert_same(first.atlas, texture, 'the loaded texture itself, not a copy read from disk')


func test_a_manifest_that_is_not_a_json_object_reads_as_empty():
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("array.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[1, 2, 3]")
	file.close()
	Image.create(12, 32, false, Image.FORMAT_RGBA8).save_png(DIR.path_join("array.png"))

	assert_eq(LFSpriteAtlasFrames.read_manifest(path), {})
	assert_null(LFSpriteAtlasFrames.from_manifest(path), 'the atlas alone is no art')


func test_an_atlas_file_that_is_not_an_image_gives_null():
	var path := _write_character("broken")
	var file := FileAccess.open(DIR.path_join("broken.png"), FileAccess.WRITE)
	file.store_string("not a png")
	file.close()
	assert_null(LFSpriteAtlasFrames.from_manifest(path))
	assert_engine_error_count(4, "Godot's image loader reports the corrupt file")


func test_a_texture_whose_pixels_cannot_be_read_gives_no_image_and_the_whole_frame():
	var unreadable := PlaceholderTexture2D.new()
	assert_null(LFSpriteAtlasFrames.atlas_image(unreadable))
	assert_eq(LFSpriteAtlasFrames.opaque_region(unreadable, Rect2(2, 2, 4, 4)), Rect2(2, 2, 4, 4))


func test_a_freed_texture_gives_up_its_place_in_the_cache():
	var kept := _region_texture()
	var kept_image := LFSpriteAtlasFrames.atlas_image(kept)
	var dropped := _region_texture()
	LFSpriteAtlasFrames.atlas_image(dropped)
	dropped = null # the last reference: the texture is freed

	LFSpriteAtlasFrames.atlas_image(_region_texture())

	assert_same(LFSpriteAtlasFrames.atlas_image(kept), kept_image, 'the freed one was pruned, so the older live one stayed')


func test_lowering_max_cached_images_takes_effect_at_the_next_read():
	var a := _region_texture()
	var b := _region_texture()
	var a_image := LFSpriteAtlasFrames.atlas_image(a)
	var b_image := LFSpriteAtlasFrames.atlas_image(b)
	LFSpriteAtlasFrames.max_cached_images = 1
	var c := _region_texture()
	var c_image := LFSpriteAtlasFrames.atlas_image(c)

	assert_same(LFSpriteAtlasFrames.atlas_image(c), c_image)
	assert_not_same(LFSpriteAtlasFrames.atlas_image(b), b_image, 'dropped down to the new limit')
	assert_not_same(LFSpriteAtlasFrames.atlas_image(a), a_image)


func test_lowering_the_limit_to_zero_empties_the_cache_at_the_next_read_even_a_hit():
	var a := _region_texture()
	var b := _region_texture()
	LFSpriteAtlasFrames.atlas_image(a)
	var b_image := LFSpriteAtlasFrames.atlas_image(b)
	assert_eq(LFSpriteAtlasFrames._images.size(), 2)
	LFSpriteAtlasFrames.max_cached_images = 0

	assert_same(LFSpriteAtlasFrames.atlas_image(b), b_image, 'the copy it still had is handed out')

	assert_eq(LFSpriteAtlasFrames._images.size(), 0, 'and then nothing is kept')


func test_lowering_the_limit_below_the_cached_count_evicts_on_a_cache_hit():
	var a := _region_texture()
	var b := _region_texture()
	var a_image := LFSpriteAtlasFrames.atlas_image(a)
	var b_image := LFSpriteAtlasFrames.atlas_image(b)
	LFSpriteAtlasFrames.max_cached_images = 1

	assert_same(LFSpriteAtlasFrames.atlas_image(a), a_image, 'a hit on the older one')

	assert_eq(LFSpriteAtlasFrames._images.size(), 1)
	assert_same(LFSpriteAtlasFrames.atlas_image(a), a_image, 'the one just read is the one kept')
	assert_not_same(LFSpriteAtlasFrames.atlas_image(b), b_image, 'the least recently used was dropped')


func test_clear_cache_leaves_max_cached_images_alone():
	LFSpriteAtlasFrames.max_cached_images = 7
	LFSpriteAtlasFrames.clear_cache()
	assert_eq(LFSpriteAtlasFrames.max_cached_images, 7)
	assert_eq(LFSpriteAtlasFrames.DEFAULT_MAX_CACHED_IMAGES, 2)


func test_a_texture_dropped_from_the_cache_and_changed_later_is_read_again():
	var texture := _region_texture()
	LFSpriteAtlasFrames.atlas_image(texture)
	LFSpriteAtlasFrames.atlas_image(_region_texture())
	LFSpriteAtlasFrames.atlas_image(_region_texture())
	var again := LFSpriteAtlasFrames.atlas_image(texture)

	texture.region = Rect2(8, 0, 8, 8)

	assert_eq(LFSpriteAtlasFrames.atlas_image(texture).get_size(), Vector2i(8, 8))
	assert_ne(again.get_size(), Vector2i(8, 8))
