# Changelog

All notable changes to lf-godot-gd-utils are recorded here. Versions follow
[Semantic Versioning](https://semver.org/): a breaking change to a public class bumps the
major version.

## Unreleased

Six new modules, all experimental: `lf_grade_combo`, `lf_chunk_stream`, `lf_ratchet_follow`,
`lf_jump_physics`, `lf_particle_pool` and `lf_multimesh_scatter`.

Four more new modules, all experimental: `lf_experience_levels`, `lf_group_camera_2d`,
`lf_local_service` and `lf_auto_size_text_edit`.

Nine more new modules, all experimental: `lf_health`, `lf_countdown`, `lf_momentum`, `lf_hit_boxes`,
`lf_magnet_pull`, `lf_magnet_pull_3d`, `lf_confirm`, `lf_prompt_dialog` and `lf_hud_bars`.

One more, also experimental: `lf_shaders_2d`.

Three more, all experimental: `lf_property_patch`, `lf_follow_ring_3d` and `lf_ring_markers_3d`.

### Added

- **(experimental)** `LFPropertyPatch`: change an object property from a data entry (`add`, `multiply` or `set`, by dotted path, with a cap and a mirrored field).
- **(experimental)** `LFFollowRing3D`: a pulsing ground ring that follows a `Node3D` and hides without one.
- **(experimental)** `LFRingMarkers3D`: a pool of flat ground rings sharing one mesh and material, shown at the points you give.
- `LFTierRoller.tilt_weights`: move weight out of the first tier into the others, in proportion, down to a floor (a luck bonus).
- `LFUtils3D.ids_in_screen_rect`: the keys of a position map that fall inside a screen rectangle.
- `LFSpriteAtlasFrames.frame_region`: a manifest frame's atlas rect, optionally cropped to its opaque pixels.
- `LFBuild.on_commit`, `LFBuild.margin` and `LFBuild.spin_box`.
- `LFStyle.swatch`: a solid colour chip texture.
- **(experimental)** `LFStatusEffectIcon` (`lf_hud_bars`): an `LFTimerIcon` that drains with one `LFStatusEffects` effect.
- `LFFactory.release_on_signal(name)`: an `on_acquire` hook that releases the entity when it emits the signal.
- **(experimental)** `LFExperienceLevels`: an experience track with per-step thresholds,
  `gain` that carries left-over experience across several levels, `progress()`, `set_level`
  and the signals `leveled_up` and `experience_gained`.
- `LFUtils2D.random_point_in_circle`, `random_point_outside_rect`, `max_pairwise_distance`,
  `fit_sprite_to_size` and `shape_size` (a circle is 2 x radius on both axes), and the constant
  `DEFAULT_OUTSIDE_SCALE_RANGE`.
- **(experimental)** `LFGroupCamera2D`: a `Camera2D` that centres on a list of target nodes and
  zooms out as they spread apart; freed targets are skipped and the zoom easing does not depend
  on the frame rate.
- **(experimental)** `LFLocalService`: starts a bundled back-end program on a free port with
  `LFProcess`, polls its health URL with `LFHttp` until it answers, and gives its `http://` and
  `ws://` addresses. Tested on macOS only.
- **(experimental)** `LFAutoSizeTextEdit`: a `TextEdit` that sets its own minimum size from its
  text, between `min_size` and `max_size`.
- **(experimental)** `LFHealth`: a clamped health pool with `damage`, `heal`, `set_max`, `reset`, `ratio` and `percent`, and `damaged`, `healed`, `died` and `max_changed` signals.
- **(experimental)** `LFCountdown`: a countdown driven by `tick(delta)` with start, pause, resume, stop and restart, `ticked` and `finished` signals, and `text()` through `LFText.clock`.
- **(experimental)** `LFMomentum`: a bump-built value with caller-driven decay (`step(delta, slowing)`), `penalize` floored at the base, and `ratio()`.
- **(experimental)** `LFHurtBox2D` and `LFHitBox2D` (`lf_hit_boxes`): area-based damage with an invulnerability gate, once-per-target or repeated hits, and untyped payloads.
- **(experimental)** `LFMagnetPull2D`, `LFMagnetPullCore` and `LFMagnetPull3D` (`lf_magnet_pull`, `lf_magnet_pull_3d`): velocity pulled toward attractors with a power each.
- **(experimental)** `LFConfirm`, `LFPromptDialog`, `LFTimerIcon` and `LFValueBar` (`lf_confirm`, `lf_prompt_dialog`, `lf_hud_bars`): an awaitable yes/no popup, an awaitable text prompt, a timer-driven icon and a current/max bar.
- **(experimental)** `LFAnimate.slide_in` / `slide_out`, `LFAnimate.pulse` and `LFAnimate.arc_hop`, and `LFIdleDrift`, an endless pausable drift around a base position; the README now says what is safe to await on `LFAnimate.control` and `pulse`.
- `LFFactory.dormant_hooks()`, `sleep(node)` and `wake(node)`: pooled nodes are hidden, set to `PROCESS_MODE_DISABLED` and have collision and `monitoring` switched off; acquiring restores the original values.
- `LFAwait.retry(fn, attempts, delay_ms, backoff, accept)`.
- `LFEventBus.off_owner(owner)`: removes everything an object registered, self-capturing lambdas included.
- `LFUtils.append_unique` and `LFUtils.merge_arrays_deep`; `LFUtils.move_node` takes an optional `global_position` applied after the reparent; the `merge_arrays` docs now state that Resources and other Objects in the first array are shared, not copied.
- **(experimental)** `LFShaders2D` with four shaders: sprite outline, screen outline, dissolve and darken.
- `LFShaders2D.cross_reveal`: a plus-shaped reveal whose arms grow with `progress`.
- `LFUtils2D.alpha_click_mask`, `apply_alpha_click_mask` and `steer`.
- `LFFlowField.build_nav_grid`: the whole walkability grid (heights, walls, climbable steps) from a height function and wall rects.
- `LFFlowFieldService.version`: counts every `field_updated` and `field_dropped`, so a caller keeping a field can tell it went stale.
- **(experimental)** `LFTerrainFeatures` (`lf_terrain_features`): ground height, walls, cover, line of sight and straight-walk checks from platform, ramp, hill, wall and foliage dictionaries, and the flow-field nav grid.
- `LFUtils2D.knock_back`: an instant impulse on a `RigidBody2D` away from a point.
- `LFUtils.cycle_index`: the next accepted index round a list, wrapping.
- `LFControl.pin`: pin a Control to an edge, corner or centre, growing inward.
- `LFCarousel.instant`: a `slide_fn` that switches pages with no animation.
- **(experimental)** `LFSnapshotReceiver` (in `lf_replication`): the client side of the snapshot replicator, a checkpoint replaces and a delta changes the state.
- **(experimental)** `LFWireMessage` (`lf_wire_message`): `{type, payload}` encode and decode of typed messages, rejecting unknown or incomplete ones.
- `LFStatusEffectDef.interval_fn`, `LFStatusStack.interval_fn` and a new last `interval_fn` parameter of `LFStatusEffects.apply`: choose each tick's delay by callback. The fixed `tick_interval` is unchanged.
- `LFProc.fire_collect`, `LFTriggerSet.fire_all` and `LFTriggerSet.fire_any`: read and combine the values reactions return.
- `LFLogView.line_scene` and `line_factory` for custom line controls.
- `LFOS` README: a note that the engine already answers the operating system and CPU
  architecture (`OS.get_name()`, `Engine.get_architecture_name()`), so there is no
  `detect_os` or `detect_arch`.
- **(experimental)** `LFShortCode` (`lf_short_code`): short readable codes from your own alphabet, and a check for typed ones.
- `LFSocketServer.free_port_in_range`: the first free port in a range, skipping ports you have handed out.
- `LFOS.int_arg`: a parsed command-line argument as an int, with a fallback.
- **(experimental)** `LFPeerGrace` (`lf_peer_grace`): a time limit for each new peer to prove itself, and who ran out.
- **(experimental)** `LFServerLifetime` (`lf_server_lifetime`): why a server process should quit: job finished, nobody connected, or its launcher gone.
- **(experimental)** `LFCoalescedTick` (`lf_coalesced_tick`): runs an awaiting per-frame update one at a time and banks the time of the frames it skipped.
- `LFWireMessage.encode_text_once` and `splice_text`: encode a message once for many peers, or splice one pre-encoded field into it.
- `LFOrbitCamera.frame_points`: frame a group of 3D points, backing off by how far they spread.
- **(experimental)** `LFSeatAssigner` (`lf_seat_assigner`): gives connecting peers the next free seat or the one they claim, swapping with its holder.
- **(experimental)** `LFListCursor` (`lf_list_cursor`): a highlighted list row that stops at both ends, with a pointer-prefix helper.
- **(experimental)** `LFSettingDefinition` (`lf_setting_definition`): one options-menu setting (pick-one or whole number) with `sanitize` and `display`.
- **(experimental)** `LFWallet` (`lf_wallet`): an amount you add to and spend, with a `changed` signal.

### Changed

- **Breaking:** `LFLogView.append` returns `Control` instead of `Label` (a custom line can be any control). Write `log.append(text) as Label` where a typed `Label` is needed.

## 1.0.0 - 2026-10-09

First release: 82 modules in four groups under `src/` (`components/`, `2D/`, `3D/`,
`utils/`), each with a README and GUT tests; [`LF_INDEX.md`](LF_INDEX.md) listing every
class; the `lf-utils-first` agent skill; [`STABILITY.md`](STABILITY.md) with the
stable / experimental label of every module; [`SECURITY.md`](SECURITY.md) and
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Requires Godot 4.7 or newer.
