# Changelog

All notable changes to lf-godot-gd-utils are recorded here. Versions follow
[Semantic Versioning](https://semver.org/): a breaking change to a public class bumps the
major version.

## Unreleased

Six new modules, all experimental: `lf_grade_combo`, `lf_chunk_stream`, `lf_ratchet_follow`,
`lf_jump_physics`, `lf_particle_pool` and `lf_multimesh_scatter`.

Four more new modules, all experimental: `lf_experience_levels`, `lf_group_camera_2d`,
`lf_local_service` and `lf_auto_size_text_edit`.

### Added

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
- `LFOS` README: a note that the engine already answers the operating system and CPU
  architecture (`OS.get_name()`, `Engine.get_architecture_name()`), so there is no
  `detect_os` or `detect_arch`.

## 1.0.0 - 2026-10-09

First release: 82 modules in four groups under `src/` (`components/`, `2D/`, `3D/`,
`utils/`), each with a README and GUT tests; [`LF_INDEX.md`](LF_INDEX.md) listing every
class; the `lf-utils-first` agent skill; [`STABILITY.md`](STABILITY.md) with the
stable / experimental label of every module; [`SECURITY.md`](SECURITY.md) and
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Requires Godot 4.7 or newer.
