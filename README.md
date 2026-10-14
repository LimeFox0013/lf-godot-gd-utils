<img width="1200" height="200" alt="lf-godot-gd-utils banner" src="https://raw.githubusercontent.com/LimeFox0013/lf-godot-gd-utils/main/.github/assets/banner.png" />

# lf-godot-gd-utils — tested GDScript building blocks for Godot 4.7+

![tests](https://github.com/LimeFox0013/lf-godot-gd-utils/actions/workflows/tests.yml/badge.svg)
![Godot 4.7+](https://img.shields.io/badge/Godot-4.7%2B-478cbf?logo=godotengine&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

**112 small GDScript modules, each with its own step-by-step guide and its own tests**:
cooldowns, screen shake, loot tables, state machines, save files, menus that slide between
screens, and more, for **Godot 4.7+**. Copy the library's folder into your project and use
the classes by name. Modules may use each other, so keep the folder whole.

Every class starts with the prefix `LF` (`LFCooldown`, `LFShaker`, `LFLootTable`), so it
never clashes with names of your own.

- **Nothing to set up.** No plugin to enable and no project settings. Once Godot has
  imported the folder, every class is available by name, like Godot's own.
- **No dependencies.** It needs only Godot. (Its own tests need
  [GUT](https://github.com/bitwes/Gut); the release zip leaves the tests out.)
- **Tested.** Over 3,100 GUT tests, an install check and an HTTP smoke test (`LFHttp`
  against a local server) are configured to run in CI on every push and pull request, on
  Godot 4.7.2, on Ubuntu, macOS and Windows runners. All three checks passed on the three
  runners on GitHub Actions on Godot 4.7.2 (run 37976288657); some tests are skipped or
  adjusted on Windows (see [Platforms](#platforms)).
- **No editor warnings.** With the GDScript warnings Godot 4.7.2 enables by default, the
  library loads without a single one (`ci/check_install.sh` checks this, headless, on 4.7.2;
  it is part of the CI workflow).
- **Explained.** Each module has a page that starts with *When to use it* and a
  *Step by step* guide written for beginners, and every class and public function has a
  description in Godot's built-in help (press F1).
- **Easy for AI assistants to look up.** An index of every class and an agent skill point
  your coding assistant at what the library already has before it writes a new helper.

## Getting started

You need Godot 4.7 or newer (only 4.7.2 has been tested) and a project (a new empty one is fine).

1. **Download.** Open the [releases page](https://github.com/LimeFox0013/lf-godot-gd-utils/releases),
   and under *Assets* of the newest release, click the `lf-godot-gd-utils-<tag>.zip`
   file (not *Source code (zip)*, which has no `addons` folder).
2. **Unzip it.** You get a folder named `addons` with the library's folder inside.
3. **Copy it into your project.** Put the `addons` folder next to your project's
   `project.godot` file. If your project already has an `addons` folder, put just the
   library's folder inside it.
4. **Open your project in Godot.** Wait for the import progress bar to finish. In the
   *FileSystem* dock (bottom left) you now see the library's folder inside `addons`.
5. **Try it.** Make a scene that uses a cooldown:
   - *Scene → New Scene*, then click *Other Node*, pick **Node** and click *Create*.
   - Right-click the node in the *Scene* dock, choose *Attach Script*, click *Create*.
   - Replace the script's text with this, then save (Ctrl+S, or Cmd+S on macOS):

   ```gdscript
   extends Node

   # A dash you can use once every 1.5 seconds (1500 milliseconds).
   var dash := LFCooldown.new(1500)


   func _process(_delta: float) -> void:
   	# "ui_accept" is the Space or Enter key in every new Godot project.
   	if Input.is_action_just_pressed("ui_accept"):
   		if dash.try_use():
   			print("Dash!")
   		else:
   			print("Still cooling down: %d ms left" % dash.remaining_ms())
   ```

6. **Run it.** Press **F6** (*Run Current Scene*), then press Space a few times. The
   *Output* panel at the bottom of the editor shows `Dash!`, or how long is left. That's
   the library working.

**Next:** open the *[Find it by task](LF_INDEX.md#find-it-by-task)* table in `LF_INDEX.md`
("I need to… → use …"). Click through to the module you need: each module's page starts
with *When to use it* and a *Step by step* guide.

## Installing as a git submodule

To follow updates (this includes the tests):

```
git submodule add https://github.com/LimeFox0013/lf-godot-gd-utils.git addons/<folder>
```

where `<folder>` is any name you like. Then exclude the tests from exports: in
*Project → Export*, *Resources* tab, *Filters to exclude files*, enter
`addons/<folder>/*/tests/*, addons/<folder>/tests/*`.

The library works from any folder: nothing in it names where it is installed, and its scenes find
their scripts next to them.

## How LF classes work

Once the library is installed, you use its classes by name in any script, like Godot's own. You
never need to `preload` anything. Every class is one of four kinds, and each module's page
says which:

- **Static helper.** Call it on the class name, no setup: `LFText.plural(3, "coin")`
  gives `"3 coins"`.
- **Object.** Create one with `.new()` and keep it in a variable:
  `var dash := LFCooldown.new(1500)`. Godot frees it when nothing uses it any more, unless
  it is caught in a reference cycle (for example a lambda stored on it that uses `self`;
  a method such as `_on_done` doesn't keep it alive).
- **Node.** Add it to a scene like any Godot node, in the editor (*Add Child Node*, then
  type "LF" to search) or from code with `add_child(...)`. It works once it is in the
  scene.
- **Resource.** A data file you create in the *FileSystem* dock and fill in the
  *Inspector*, like an `LFLootTable`.

**Help inside the editor:** press **F1** (*Search Help*) and type a class name such as
`LFCooldown`. Every LF class and function has a description there. Ctrl+click (Cmd+click
on macOS) a class name in your script to jump to it.

## Glossary

The module pages use these words. You don't need them all to get started.

| Word | Meaning |
|---|---|
| Node, scene | A node is one building block in Godot (a sprite, a button, a camera). A scene is a tree of nodes saved as a `.tscn` file. |
| Script | A `.gd` file attached to a node that tells it what to do. |
| `_ready()`, `_process(delta)` | Functions Godot calls for you: `_ready` once when the node enters the scene, `_process` every frame. |
| `delta` | The seconds since the last frame (about 0.016 at 60 frames per second). |
| ms | Milliseconds: 1000 ms = 1 second. The library says in each name or doc whether it wants ms or seconds. |
| Signal | An event a node or object announces ("connected", "finished") that other code can listen to with `.connect(...)`. |
| `await` | "Wait here until this finishes", for things that take time, like a timer or a web request. |
| Callable, `func(): ...` | A function passed around as a value, so the library can call it for you later. |
| Dictionary, Array | `{"key": value}` pairs, and `[a, b, c]` lists. |
| Inspector, FileSystem, Output | Editor panels: the node's settings (right), your project's files (bottom left), and printed messages (bottom). |
| `res://`, `user://` | Your project folder (read-only in an exported game), and a per-player folder for saves and settings (*Project → Open User Data Folder* shows where). |
| Seed | A number that makes "random" results repeat exactly, for replays and testing. |

## What's inside

112 modules in four groups. Each module is one folder, `src/<group>/lf_<name>/`, with its own
page (`README.md`); the `utils/` table groups them by area.

Most modules are small, general helpers. A few are larger and made for particular kinds of
game; read their pages before adopting them:

- crowd movement: `lf_crowd_body`, `lf_ring_slots`, `lf_flow_field`;
- roguelike upgrades with caps: `lf_modifier_levels`, `lf_capped_level_tracker`,
  `lf_modifier_grant_service`;
- online services: `lf_accounts`, `lf_strike_guard`, `lf_replication`, `lf_llm`. They suit
  a small game server you run yourself; each page states the limits the maintainers know of
  (not every page covers all of security, scale and platforms).

### `components/` — UI

| Module | What it does |
|---|---|
| `lf_auto_size_text_edit` | A multi-line text field that grows as you type, between a smallest and a largest size |
| `lf_bar_chart` | Draws a small bar chart from a list of numbers |
| `lf_confirm` | A yes/no popup you wait for (`await LFConfirm.ask(...)`) |
| `lf_build` | Creates labels, buttons, text fields and scrolling boxes from code in one line |
| `lf_carousel` | Switches between screens or pages with a slide (or any) animation |
| `lf_components` | Creates one of the library's ready-made UI scenes by its short name |
| `lf_control` | Finds a UI element from anywhere by an id you give it; orders elements for keyboard browsing; places a popup beside something |
| `lf_control_2d` | Keeps a 2D node on top of a UI element's position |
| `lf_control_out` | A label whose text any script can set by id |
| `lf_hud_bars` | Bars for the HUD: an icon that drains with a timer, and a health-style bar with easing |
| `lf_help_tip` | Rich tooltips (title, text, pictures) on any UI element, and a key to browse every tip on screen |
| `lf_input_manager` | Lets an open menu or dialog take input first, so the game underneath ignores it |
| `lf_layout_control` | An invisible area for layout that never blocks clicks |
| `lf_log_view` | A scrolling message log, and a ready chat box |
| `lf_option_picker` | Fills a dropdown (OptionButton) from your data, with icons, and reads back the chosen value |
| `lf_prompt_dialog` | A popup that asks the player for a line of text, such as a name, and returns it |
| `lf_parallax_control` | Background layers in a menu that move at different speeds for depth |
| `lf_style` | Makes button and panel styles (colours, borders, corners) in one call |
| `lf_table` | A table of rows and columns: scoreboards, inventories, lists with buttons |
| `lf_tracker` | A marker on screen for a 3D object, or an arrow at the screen edge pointing to it |
| `lf_video_player` | Plays part of a video for a set time, then holds the frame |

### `2D/`

| Module | What it does |
|---|---|
| `lf_group_camera_2d` | A 2D camera that keeps several players or units in view: it centres on them and zooms out as they spread |
| `lf_hit_boxes` | Hit boxes and hurt boxes that turn overlaps into damage, with a short invulnerability gate |
| `lf_infinite_scroll_sprite` | Endless scrolling and parallax backgrounds that follow the camera |
| `lf_magnet_pull` | Pulls pickups toward nearby magnets, each with its own power |
| `lf_shaders_2d` | Ready-made materials: sprite outline, screen outline, dissolve and darken |
| `lf_utils_2d` | Helpers for what a 2D camera sees, pinning things to the screen edge, random points around a spot, and sizing sprites |
| `lf_viewport_leave` | Tells you when a node has been off-screen for a while (to free bullets, despawn enemies) |
| `lf_virtual_grid` | Shows only the rows of a huge 2D list that are on screen, so it builds only the rows you can see |

### `3D/`

| Module | What it does |
|---|---|
| `lf_crowd_body` | Units in a crowd push apart, get knocked back, and walk round walls |
| `lf_directional_sprite` | 2D sprite characters in a 3D world that show the right side to the camera (Doom-style) |
| `lf_floating_text_3d` | Damage numbers and pop-up text that rise, fade and disappear |
| `lf_follow_ring_3d` | A pulsing ring on the ground that follows a 3D node and hides without one: a selection marker |
| `lf_heightmap` | Hills and terrain (mesh and collision) from a height formula |
| `lf_magnet_pull_3d` | The 3D version of `lf_magnet_pull` |
| `lf_orbit_camera` | A strategy-game camera: pan, zoom and orbit |
| `lf_ring_markers_3d` | Flat rings on the ground at the points you give it, reused between calls |
| `lf_multimesh_scatter` | Scatter grass, pebbles or flowers over a flat area with one cheap draw call |
| `lf_terrain_features` | A level made of platforms, ramps, hills, walls and bushes: ground height, line of sight, and straight-walk checks |
| `lf_shaker` | Screen shake (and shaking anything else) for hits and explosions |
| `lf_utils_3d` | Click on the 3D world, find screen positions of 3D points, and ground-plane math |
| `lf_viewport_leave_3d` | The 3D version of `lf_viewport_leave` |

### `utils/` — everything that isn't drawn

| Area | Modules |
|---|---|
| Everyday helpers | `lf_utils` (wait, find the closest, clear children…), `lf_dictionary` (read nested data, with a default when a key is missing), `lf_json`, `lf_text` (plurals, countdown clocks), `lf_graph` (tree layouts), `lf_uuid` (random ids, UUID v4), `lf_short_code` (readable codes players type), `lf_logger` (tidy log messages) |
| Input | `lf_drag_tracker` (tell a click from a drag), `lf_input_keys` (keyboard as a gamepad, button names for hints) |
| Timing and events | `lf_await` (wait for several things), `lf_debounce` and `lf_throttle` (limit how often something runs), `lf_cooldown`, `lf_interval_timer` (every N seconds), `lf_coalesced_tick` (a slow update that never runs twice at once), `lf_turn_cycle` (timed turns), `lf_thread` (run heavy work on a worker thread), `lf_animate` (simple animations), `lf_event_emitter` and `lf_event_bus` (send messages between parts of the game) |
| Objects and data | `lf_factory` (reuse bullets and effects instead of creating new ones), `lf_particle_pool` (reuse one particle effect, recoloured per copy), `lf_chunk_stream` (an endless level of equal pieces, built around the player), `lf_object_id_registry`, `lf_invert_index` (find things by tag), `lf_spatial_index` (find what's nearby), `lf_ring_slots` (units stand side by side at a destination), `lf_slot_inventory` (hotbar and backpack) |
| Gameplay systems | `lf_state_machine` (enemy modes like patrol and chase), `lf_grade_combo` (Good / Great / Perfect streaks into a multiplier), `lf_jump_physics` (platformer jump feel), `lf_ratchet_follow` (a camera that follows a climb), `lf_status_effects` (buffs, poison), `lf_procs` (chance-on-hit effects), `lf_layered_stats` (base stats plus bonuses), `lf_modifier_levels`, `lf_capped_level_tracker` and `lf_modifier_grant_service` (upgrades with limits), `lf_experience_levels` (experience points and level-ups), `lf_health` (a health pool with damage and healing), `lf_countdown` (a round timer or fuse), `lf_property_patch` (apply data like "+20 max health" to an object), `lf_momentum` (a value that builds up and fades), `lf_unlock_tree` (skill trees), `lf_loot_table`, `lf_tier_roller` (rarity), `lf_pity_tracker` (bad-luck protection), `lf_weighted_pick`, `lf_random` (repeatable randomness), `lf_grid_2d`, `lf_flow_field` (move big crowds to a goal) |
| Files | `lf_file` (read and save files; a save writes a checked temporary file, then renames it over the old one), `lf_file_observer` (settings that save themselves), `lf_zip` (unzip mods and downloads) |
| Network and system | `lf_http` (talk to web servers), `lf_socket` and `lf_socket_server` (live online connections), `lf_peer_grace` (a time limit for new connections to prove themselves), `lf_server_lifetime` (when a server process should quit), `lf_url`, `lf_os` (system info, launch a server), `lf_process` (run other programs), `lf_local_service` (start a bundled back end on a free port and wait until it answers), `lf_wire_message` (typed messages as `{type, payload}`), `lf_seat_assigner` (give connecting players the next free seat, or the one they claim) |
| Online services | `lf_llm` (call a language model that can use tools, e.g. for AI players), `lf_accounts` (player log-in), `lf_strike_guard` (lock out repeated failed log-ins), `lf_replication` (keep online players in sync) |

## Platforms

**What CI is configured to run.** The workflow `.github/workflows/tests.yml` runs the GUT
suite, the clean install check and the HTTP smoke test with **Godot 4.7.2** (the standard
build, not the .NET one) on GitHub's `ubuntu-latest`, `macos-latest` and `windows-latest`
runners, on every push and pull request. All three jobs passed in run 37976288657 (Godot 4.7.2).
On Windows the `/bin/sh` tests of `lf_process` are skipped (a few `cmd.exe` tests run
instead) and the tests of refused connections are skipped or adjusted (see below).

**What is not verified.**

- Any Godot version other than 4.7.2. The library is written for 4.7 or newer; no other
  version, newer or older, has been run, so "4.7+" is a requirement, not a tested range.
- Web exports, Android and iOS: no test of the library has run on any of them.
- Rendering and feel: the tests run headless, so how a UI module, camera or shader looks
  on screen is not checked by CI.

**Known limits per platform** (each module's page has the details):

- `lf_socket`, `lf_socket_server`: desktop (Windows, macOS, Linux) only, not a web export.
- `lf_http`: tested on desktop only; in a browser export the browser makes the request.
- Windows, refused connections: in the Windows CI run Godot 4.7.2 never reported a refused loopback connection (still connecting after 25 s). `lf_socket` then reports no `error` and schedules no reconnect, and `lf_http` ends such a request with `Connect timeout` instead of `Cannot connect`. The tests of the refusal behaviour are skipped (`lf_socket`) or adjusted (`lf_http`) on Windows.
- macOS 26, refused connections: with Godot 4.7.2 on macOS 26.7.1 (a local run; the CI run above used GitHub's `macos-latest` runner), dialling a closed loopback port makes the engine itself log `Unable to set TCP no delay option`, and `lf_http` reports such a request as `Connection lost` rather than `Cannot connect`. The tests that dial closed ports accept the engine message and that text on macOS only; the library's own behaviour is unchanged.
- `lf_thread`, `lf_zip`: on a build without thread support (a web export with *Thread
  Support* off) there is no worker thread; the work runs on the main thread and blocks it.
  `lf_zip` is tested on macOS desktop; `lf_thread` in the editor on desktop.
- `lf_process`: desktop. On Windows only a few `cmd.exe` tests run (start, output, exit
  code, stop, refusing `.bat`); restarts, `terminate` and stdin are tested on Linux and macOS only; the web has no processes to start; Android and iOS are untested.
- `lf_os`: written for desktop. `LFOS.is_pid_alive` reads `/proc/<pid>` where `/proc`
  exists (Linux, and Android, whose behaviour is not verified), runs `kill -0` on macOS and
  other Unix, runs `tasklist` on Windows, and on web and iOS answers only for the
  process's own id. On macOS and Windows it launches a command and blocks the caller
  (`LFOS.pid_check_runs_command()` tells). `resolve_executable`'s Windows `PATHEXT` handling
  is not covered by tests.
- `lf_file`: on Windows a save replaces the file by removing it and moving the new one in,
  so a crash in that instant can leave only the temporary file (see its page).

## Troubleshooting

- **"Identifier "LF…" not declared in the current scope".** Godot hasn't picked up the library's
  classes yet. Close and reopen the project. If it persists, check that the `.uid` files
  inside the library's folder were copied along with the `.gd` files.
- **Nothing is printed when I press F6.** Check the script is attached to a node in the
  scene you are running (the node shows a scroll icon) and that you saved it. Messages
  appear in the *Output* panel at the bottom of the editor.
- **"Could not find base class "GutTest"".** You installed with the git submodule, which
  includes the library's tests, but not GUT, the testing tool they need. Install
  [GUT](https://github.com/bitwes/Gut), or use the release zip, which has no tests.
- **A headless run never ends.** When a script error stops the code that would call
  `get_tree().quit()`, Godot keeps running. Add `--quit-after <frames>` to the command
  line of automated runs.
- **Errors mentioning functions that don't exist in Godot.** The library is written for Godot 4.7 or newer (only 4.7.2 is tested).
  *Help → About Godot* shows your version.
- **Something doesn't behave as you expect.** Read the *Notes* section of that module's
  page, where special cases are explained. Still stuck? Open an issue with a small
  example.

## Using it with an AI coding assistant

AI assistants are good at writing a helper and bad at remembering that one already
exists, so a project slowly fills with duplicates. The library ships two files that help the
assistant look first:

- [`LF_INDEX.md`](LF_INDEX.md) lists every class with what it's for, starting with a *Find it
  by task* table.
- [`skills/lf-utils-first`](skills/lf-utils-first/SKILL.md) is an
  [Agent Skill](https://agentskills.io) (a `SKILL.md` folder, an open format many
  assistants read). It asks the assistant, before it writes GDScript, to find
  `LF_INDEX.md`, check it, and reuse a class from the library when one fits. Whether the assistant
  loads and follows the skill depends on the tool and the model.

**1. Install the skill.** Copy the folder `skills/lf-utils-first` (inside the library's
folder, for example `addons/<folder>/skills/lf-utils-first`) into the skills folder your assistant reads, in your
project's root:

| Assistant | Put the `lf-utils-first` folder in |
|---|---|
| Claude Code | `.claude/skills/` |
| Other tools that support Agent Skills | the skills folder named in that tool's docs (several read `.agents/skills/`) |

Create the folder if it doesn't exist; you end up with, for example,
`.claude/skills/lf-utils-first/SKILL.md`. To use more than one assistant, copy it into
each one's folder. On macOS or Linux you can link instead of copying, so the skill updates with the library:
`ln -s ../../addons/<folder>/skills/lf-utils-first .claude/skills/lf-utils-first`.

**2. Add a reminder to the project's instructions.** Paste these lines into the file your
assistant always reads (`CLAUDE.md` for Claude Code, `AGENTS.md` for Codex and most
others, `GEMINI.md`, `.github/copilot-instructions.md`, `.cursor/rules`; create it if it
doesn't exist):

```markdown
## lf-godot-gd-utils library
This project uses lf-godot-gd-utils, a library of tested GDScript helpers. Before writing any new
GDScript class, helper, component or system, use the `lf-utils-first` skill: find
the file `LF_INDEX.md` in the project, read it, and reuse an existing class from it when
one fits.
```

An assistant without skill support can still follow this paragraph; point it at the library's
`skills/lf-utils-first/SKILL.md` for the full routine.

## For developers

### Conventions

- Every class is a global `class_name`: use it by name, never `preload` it.
- Every gameplay system that rolls dice takes its random generator from you (a seeded
  `RandomNumberGenerator` or an `LFRandom`), so one seed replays it. A few cosmetic
  helpers (such as `LFUtils.random_point_in_rect`) take one optionally and use Godot's
  global generator without it; their pages say so.
- Time is explicit. `LFDebounce`, `LFThrottle` and `LFCooldown`'s default clock count
  real time (engine ticks, ignoring `Engine.time_scale`); `LFUtils.timeout` and `LFUtils.create_timer` follow
  `Engine.time_scale` unless asked for real time. Simulation classes
  (`LFIntervalTimer`, `LFStatusEffects`, `LFTurnCycle`, `LFFlowFieldService`,
  `LFSnapshotReplicator`, …) advance only on the `delta` you pass to `tick`, or read a
  clock you supply.
- Time units are in the name: anything ending in `_ms` is milliseconds; every other
  duration is in seconds, and its description says so.
- Bad input is reported through `LFLogger` and answered with a documented fallback
  (`null`, `-1`, `false`, an empty value) rather than a script error, except where a
  page lists preconditions it doesn't check (for example `LFJson.vec3`). `LFLogger`'s
  warnings and errors go to Godot's log, and a few constructors and builders (`LFStrikeGuard`,
  `LFAwait`, `LFSpriteAtlasFrames`) call `push_error` themselves (not every page says so).
- The library's informational log lines (connection and process lifecycle) are off by default; set
  `LFLogger.enable_print_logs = true` once at startup to see them. Warnings and errors
  print unless you turn them off with `LFLogger.enable_print_warnings` /
  `enable_print_errors`.
- A RefCounted object you drop cleans up after itself: a socket closes, a process is
  killed, a server stops listening.
- Most state is per instance. [`LF_INDEX.md`](LF_INDEX.md) → Conventions lists the few
  process-wide exceptions (the event bus, the control registry, logger switches, …) and
  how to reset each.
- Style follows the [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html):
  `lf_snake_case` files, `LFPascalCase` classes (two-letter acronyms stay uppercase, as in
  `LFOS`; longer ones are PascalCase, as in `LFHttp`), past-tense signal names.

### Running the tests

The tests, `ci/` and `.github/` live only in the repository: the release zip leaves them
out. Clone the repository (or install it as a git submodule) to run them.

The tests use [GUT](https://github.com/bitwes/Gut) 9.7 or newer. Add the library's folder (with
subdirectories) to your `.gutconfig.json` `dirs`, then run, from the project root:

```
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json -gexit
# one test file, by name (each module's README lists its test files in its info table):
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json -gselect=test_lf_uuid.gd -gexit
```

Or run the suite on its own, in a throwaway project, the way CI does (from a clone of the
repository). The scripts are bash, run by CI on Ubuntu, macOS and Windows
under Git Bash, where `GODOT` must be the `..._console.exe` build. They need Python 3 (`python3`, or `python`);
`check_install.sh` also needs `git`):

```
GODOT=/path/to/godot ci/run_tests.sh             # uses the copy of GUT in ci/gut
GODOT=/path/to/godot ci/run_tests.sh path/to/gut # or yours
GODOT=/path/to/godot ci/check_install.sh         # the release contents load cleanly, with no warnings
GODOT=/path/to/godot ci/http_smoke.sh            # LFHttp against a local HTTP server (limit, redirect, frames)
```

### Contributing

Issues and pull requests are welcome; [`CONTRIBUTING.md`](CONTRIBUTING.md) lists what a
change needs. The library is developed with AI coding agents, under review, test-first.
Versioning, the deprecation policy and which modules are stable or experimental are in
[`STABILITY.md`](STABILITY.md); report a vulnerability as [`SECURITY.md`](SECURITY.md)
says; everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE): free to use in any project, commercial or not.
