# Stability and versioning

What you can rely on when you update lf-godot-gd-utils, and which modules are still settling.

## Versions

lf-godot-gd-utils follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

- **Patch** (1.0.1): bug fixes and documentation. No API change.
- **Minor** (1.1.0): new classes, members and options, and anything in an **experimental**
  module (see below).
- **Major** (2.0.0): a breaking change to a **stable** module, or raising the minimum
  Godot version (for example from 4.7 to 4.8).

**What counts as public API:** a class name, and every member (function, signal, constant,
property, enum) that the module's `README.md` lists and that does not start with `_`.
Anything starting with `_`, the files in `tests/`, `ci/` and the exact text of log
messages and error strings are not API. A change in documented behaviour (a different
return value, a different default, a signal that fires at another moment) is a breaking
change even when the signature stays the same.

## Deprecation

A stable module's public member is not removed or changed incompatibly in a minor or patch
release. Instead:

1. A minor release marks it deprecated: a `## @deprecated: use X` line in its doc comment
   (Godot shows this in the editor help; this relies on a Godot version that understands
   the tag, which is not verified for every 4.x), a note in the module's `README.md`, and a
   `Deprecated` entry in [`CHANGELOG.md`](CHANGELOG.md) that names the replacement and the
   major version that removes it.
2. It keeps working, unchanged, for at least one full minor release after that.
3. The next major release may remove it.

An experimental module can change or remove a member in a minor release without the
waiting period. It still gets a CHANGELOG entry.

## How breaking changes are flagged

[`CHANGELOG.md`](CHANGELOG.md) has one section per release, with the headings *Added*,
*Changed*, *Deprecated*, *Removed*, *Fixed* and *Security* where they apply. An entry
that breaks a caller starts with **Breaking:**, names the module, and says in one line
what to write instead. A release that has such an entry in a stable module is a major
release. Entries for experimental modules are marked **(experimental)**.

## Stability of each module

- **stable**: the API above applies in full. The module is small or self-contained, its
  behaviour is covered by its tests, and the maintainers do not know of a change they
  intend to make to its public API.
- **experimental**: usable, tested, and documented, but its API may change in a minor
  release. The reason is given in the last column. Pin the exact version you tested with.

These labels are the maintainers' judgment at version 1.0.0, based on each module's
README and tests; they are not measurements, and a "stable" label is a commitment about
how the API will change, not a promise that the module has no bugs. Modules move from
experimental to stable in a minor release, with a CHANGELOG entry.

### `components/` (UI)

| Module | Stability | Why |
|---|---|---|
| [`lf_auto_size_text_edit`](src/components/lf_auto_size_text_edit/README.md) | experimental | layout; tests cannot judge how it looks |
| [`lf_bar_chart`](src/components/lf_bar_chart/README.md) | stable | - |
| [`lf_build`](src/components/lf_build/README.md) | stable | - |
| [`lf_carousel`](src/components/lf_carousel/README.md) | stable | - |
| [`lf_components`](src/components/lf_components/README.md) | stable | - |
| [`lf_control`](src/components/lf_control/README.md) | stable | - |
| [`lf_control_2d`](src/components/lf_control_2d/README.md) | stable | - |
| [`lf_control_out`](src/components/lf_control_out/README.md) | stable | - |
| [`lf_help_tip`](src/components/lf_help_tip/README.md) | experimental | large UI surface; tests cannot judge how it looks |
| [`lf_input_manager`](src/components/lf_input_manager/README.md) | experimental | depends on how Godot routes input |
| [`lf_layout_control`](src/components/lf_layout_control/README.md) | stable | - |
| [`lf_log_view`](src/components/lf_log_view/README.md) | stable | - |
| [`lf_option_picker`](src/components/lf_option_picker/README.md) | stable | - |
| [`lf_parallax_control`](src/components/lf_parallax_control/README.md) | stable | - |
| [`lf_style`](src/components/lf_style/README.md) | stable | - |
| [`lf_table`](src/components/lf_table/README.md) | stable | - |
| [`lf_tracker`](src/components/lf_tracker/README.md) | experimental | HUD layout; tests cannot judge how it looks |
| [`lf_video_player`](src/components/lf_video_player/README.md) | experimental | depends on Godot's video backends |

### `2D/`

| Module | Stability | Why |
|---|---|---|
| [`lf_infinite_scroll_sprite`](src/2D/lf_infinite_scroll_sprite/README.md) | experimental | rendering; tests cannot judge how it looks |
| [`lf_group_camera_2d`](src/2D/lf_group_camera_2d/README.md) | experimental | camera feel; tests cannot judge it |
| [`lf_utils_2d`](src/2D/lf_utils_2d/README.md) | stable | - |
| [`lf_viewport_leave`](src/2D/lf_viewport_leave/README.md) | stable | - |
| [`lf_virtual_grid`](src/2D/lf_virtual_grid/README.md) | experimental | newer, view-dependent |

### `3D/`

| Module | Stability | Why |
|---|---|---|
| [`lf_crowd_body`](src/3D/lf_crowd_body/README.md) | experimental | large, game-shaped surface (crowds) |
| [`lf_directional_sprite`](src/3D/lf_directional_sprite/README.md) | experimental | rendering; tests cannot judge how it looks |
| [`lf_floating_text_3d`](src/3D/lf_floating_text_3d/README.md) | stable | - |
| [`lf_multimesh_scatter`](src/3D/lf_multimesh_scatter/README.md) | experimental | newer, extracted from a game |
| [`lf_heightmap`](src/3D/lf_heightmap/README.md) | experimental | rendering and physics geometry |
| [`lf_orbit_camera`](src/3D/lf_orbit_camera/README.md) | experimental | input feel; tests cannot judge it |
| [`lf_shaker`](src/3D/lf_shaker/README.md) | experimental | camera feel; tests cannot judge it |
| [`lf_utils_3d`](src/3D/lf_utils_3d/README.md) | stable | - |
| [`lf_viewport_leave_3d`](src/3D/lf_viewport_leave_3d/README.md) | stable | - |

### `utils/`

| Module | Stability | Why |
|---|---|---|
| [`lf_accounts`](src/utils/lf_accounts/README.md) | experimental | security-sensitive; under active review |
| [`lf_animate`](src/utils/lf_animate/README.md) | experimental | tween behaviour on live nodes; the pop animations are cosmetic |
| [`lf_await`](src/utils/lf_await/README.md) | stable | - |
| [`lf_capped_level_tracker`](src/utils/lf_capped_level_tracker/README.md) | experimental | game-shaped (roguelike upgrades); the shape may still change |
| [`lf_cooldown`](src/utils/lf_cooldown/README.md) | stable | - |
| [`lf_jump_physics`](src/utils/lf_jump_physics/README.md) | experimental | newer, extracted from a game |
| [`lf_ratchet_follow`](src/utils/lf_ratchet_follow/README.md) | experimental | newer, extracted from a game |
| [`lf_grade_combo`](src/utils/lf_grade_combo/README.md) | experimental | newer, extracted from a game |
| [`lf_particle_pool`](src/utils/lf_particle_pool/README.md) | experimental | newer, extracted from a game |
| [`lf_chunk_stream`](src/utils/lf_chunk_stream/README.md) | experimental | newer, extracted from a game |
| [`lf_debounce`](src/utils/lf_debounce/README.md) | stable | - |
| [`lf_dictionary`](src/utils/lf_dictionary/README.md) | stable | - |
| [`lf_drag_tracker`](src/utils/lf_drag_tracker/README.md) | stable | - |
| [`lf_event_bus`](src/utils/lf_event_bus/README.md) | stable | - |
| [`lf_event_emitter`](src/utils/lf_event_emitter/README.md) | stable | - |
| [`lf_factory`](src/utils/lf_factory/README.md) | stable | - |
| [`lf_experience_levels`](src/utils/lf_experience_levels/README.md) | experimental | newer, extracted from a game |
| [`lf_file`](src/utils/lf_file/README.md) | stable | - |
| [`lf_file_observer`](src/utils/lf_file_observer/README.md) | stable | - |
| [`lf_flow_field`](src/utils/lf_flow_field/README.md) | experimental | large, game-shaped surface (crowds); thresholds are tuned by feel |
| [`lf_graph`](src/utils/lf_graph/README.md) | stable | - |
| [`lf_grid_2d`](src/utils/lf_grid_2d/README.md) | stable | - |
| [`lf_http`](src/utils/lf_http/README.md) | experimental | network client; under active review |
| [`lf_input_keys`](src/utils/lf_input_keys/README.md) | stable | - |
| [`lf_interval_timer`](src/utils/lf_interval_timer/README.md) | stable | - |
| [`lf_invert_index`](src/utils/lf_invert_index/README.md) | experimental | under active review |
| [`lf_json`](src/utils/lf_json/README.md) | stable | - |
| [`lf_layered_stats`](src/utils/lf_layered_stats/README.md) | stable | - |
| [`lf_llm`](src/utils/lf_llm/README.md) | experimental | talks to third-party model APIs that change; under active review |
| [`lf_local_service`](src/utils/lf_local_service/README.md) | experimental | platform-dependent; starts and stops programs; tested on macOS only |
| [`lf_logger`](src/utils/lf_logger/README.md) | stable | - |
| [`lf_loot_table`](src/utils/lf_loot_table/README.md) | stable | - |
| [`lf_modifier_grant_service`](src/utils/lf_modifier_grant_service/README.md) | experimental | game-shaped (roguelike upgrades); the shape may still change |
| [`lf_modifier_levels`](src/utils/lf_modifier_levels/README.md) | experimental | game-shaped (roguelike upgrades); the shape may still change |
| [`lf_object_id_registry`](src/utils/lf_object_id_registry/README.md) | stable | - |
| [`lf_os`](src/utils/lf_os/README.md) | experimental | platform-dependent (launching, pids, ports); parts untested on Windows |
| [`lf_pity_tracker`](src/utils/lf_pity_tracker/README.md) | stable | - |
| [`lf_process`](src/utils/lf_process/README.md) | experimental | platform-dependent; spawns and kills programs |
| [`lf_procs`](src/utils/lf_procs/README.md) | stable | - |
| [`lf_random`](src/utils/lf_random/README.md) | stable | - |
| [`lf_replication`](src/utils/lf_replication/README.md) | experimental | networking protocol shapes may still change |
| [`lf_ring_slots`](src/utils/lf_ring_slots/README.md) | experimental | game-shaped crowd helper |
| [`lf_slot_inventory`](src/utils/lf_slot_inventory/README.md) | stable | - |
| [`lf_socket`](src/utils/lf_socket/README.md) | experimental | network client; under active review |
| [`lf_socket_server`](src/utils/lf_socket_server/README.md) | experimental | network server; under active review |
| [`lf_spatial_index`](src/utils/lf_spatial_index/README.md) | stable | - |
| [`lf_state_machine`](src/utils/lf_state_machine/README.md) | stable | - |
| [`lf_status_effects`](src/utils/lf_status_effects/README.md) | stable | - |
| [`lf_strike_guard`](src/utils/lf_strike_guard/README.md) | experimental | security-sensitive; under active review |
| [`lf_text`](src/utils/lf_text/README.md) | stable | - |
| [`lf_thread`](src/utils/lf_thread/README.md) | experimental | behaviour differs where Godot has no threads |
| [`lf_throttle`](src/utils/lf_throttle/README.md) | stable | - |
| [`lf_tier_roller`](src/utils/lf_tier_roller/README.md) | stable | - |
| [`lf_turn_cycle`](src/utils/lf_turn_cycle/README.md) | stable | - |
| [`lf_unlock_tree`](src/utils/lf_unlock_tree/README.md) | stable | - |
| [`lf_url`](src/utils/lf_url/README.md) | experimental | URL parsing that the network modules rely on; under active review |
| [`lf_utils`](src/utils/lf_utils/README.md) | stable | - |
| [`lf_uuid`](src/utils/lf_uuid/README.md) | stable | - |
| [`lf_weighted_pick`](src/utils/lf_weighted_pick/README.md) | stable | - |
| [`lf_zip`](src/utils/lf_zip/README.md) | experimental | threads plus untrusted archives |

52 modules are stable and 40 are experimental.
