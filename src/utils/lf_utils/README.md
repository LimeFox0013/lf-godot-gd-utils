# LFUtils

> Small static helpers for everyday chores: wait some milliseconds, pick the best item from a list, group items, clear and refill a container, move a node, merge data, and more.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_utils.gd` |
| **Tests** | `tests/test_lf_timer.gd`, `tests/test_lf_merge.gd`, `tests/test_lf_deep_equal.gd`, `tests/test_lf_node_reparent.gd`, `tests/test_lf_viewport_size.gd`, `tests/test_lf_random_point.gd`, `tests/test_lf_property_names.gd`, `tests/test_lf_free_children.gd`, `tests/test_lf_disconnect_all.gd`, `tests/test_lf_array_queries.gd`, `tests/test_lf_sync_children.gd`, `tests/test_lf_poll_each_frame.gd`, `tests/test_lf_main_loop.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` (reports from `free_children` and `sync_children`) |

## When to use it

Reach for it for the small chores that otherwise get rewritten in every script: wait
250 ms (`await LFUtils.timeout(250)`), clear and refill a list of UI rows
(`free_children`, `sync_children`), find the closest enemy (`min_by`), group units by team
(`group_by`), move a node to a new parent at the end of the frame (`move_node`), or pick a random spawn
point in a rectangle. Everything is a static function: no instance, no node. For a
repeating timer on your own delta use `LFIntervalTimer`; for seeded randomness beyond one
point use `LFRandom`; for waiting on several coroutines use `LFAwait`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock (top left) click
   *Other Node*, pick *Node*, and press *Create*.
2. Right-click the new node and choose *Attach Script*. Keep the defaults in the dialog
   and press *Create*. The script editor opens.
3. Select everything in the script and replace it with this code (the list is made-up data; use your own):

```gdscript
extends Node

func _ready() -> void:
	# A list of units; each unit is a Dictionary (a bag of named values).
	var units := [
		{"name": "Ann", "team": "red", "power": 7},
		{"name": "Bob", "team": "blue", "power": 9},
		{"name": "Cid", "team": "red", "power": 4},
	]

	# Pick the unit with the biggest "power". The `func(u): ...` part is a small
	# function (a Callable) that says what to compare.
	var strongest: Dictionary = LFUtils.max_by(units, func(u): return u["power"])
	print("Strongest: ", strongest["name"])

	# Sort the units into teams: {"red": [Ann, Cid], "blue": [Bob]}.
	var by_team := LFUtils.group_by(units, func(u): return u["team"])
	print("Red team has ", by_team["red"].size(), " units")

	# `await` means "wait here until this finishes". 2000 is milliseconds (2 s).
	print("Waiting 2 seconds...")
	await LFUtils.timeout(2000)
	print("Two seconds later")
```
4. Press *Ctrl+S* (*Cmd+S* on macOS) and save the scene, then *F6* (*Run Current Scene*).
5. Look at the *Output* panel at the bottom of the editor. You should see
   `Strongest: Bob` and `Red team has 2 units` at once, then `Two seconds later` after
   two seconds.
6. To use it in your game, change the list to your own data and the `"power"` / `"team"`
   keys to the values you want to compare. Every other helper below is called the same
   way: `LFUtils.name(...)`.

## API

Everything the class offers; you only need the rows used above to get started.

### Properties

| Member | Signature | Description |
|---|---|---|
| `main_loop` | `static var main_loop: MainLoop` (getter) | `Engine.get_main_loop()`, read fresh on every access. |
| `tree_root` | `static var tree_root: SceneTree` (getter) | `main_loop as SceneTree` — the running SceneTree, or `null` under a custom MainLoop. Used by the timers, `move_node` and `LFAwait.next_tick`; needs no node in the tree. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `create_timer` | `static create_timer(delay_ms: float, callback := func(): pass, real_time := false) -> SceneTreeTimer` | Creates a `SceneTreeTimer` of `delay_ms` milliseconds and connects `callback` to `timeout` with `CONNECT_ONE_SHOT`. It runs while the tree is paused; it follows `Engine.time_scale` unless `real_time` is true. |
| `poll_each_frame` | `static poll_each_frame(owner: Object, step: StringName) -> void` | Calls `owner.call(step)` now and once every process frame after, until it returns anything but the bool `true` or `owner` is freed. Holds `owner` weakly. Fire and forget. |
| `timeout` | `static timeout(delay_ms: float, callback := func(): pass) -> void` | Coroutine: `await`s a `create_timer(delay_ms, callback)` timeout (game time: follows `Engine.time_scale`, runs while paused). |
| `merge_arrays` | `static merge_arrays(target_array: Array, ...arrays: Array) -> Array` | Returns `target_array.duplicate(true)` with every source `append_array`ed onto it. Inputs untouched. Nested arrays and dictionaries of the first array are copied; Objects in it (Resources, Nodes) are the same instances, not copies (see `merge_arrays_deep`). |
| `merge_arrays_deep` | `static merge_arrays_deep(target_array: Array, ...arrays: Array) -> Array` | `merge_arrays`, but the Resources in the first array (at any depth) are copied too (`duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL)`): each Resource element is copied, with its built-in or path-less sub-resources, while sub-resources saved in their own file stay shared. Nodes are never copied. |
| `cycle_index` | `static cycle_index(current: int, count: int, direction: int, accept := Callable()) -> int` | The next index going `direction` (1 or -1) round `count` entries, wrapping, that `accept(index)` takes (unset takes any); -1 when none does. `current` -1 starts before the first entry going forward, after the last going back. |
| `append_unique` | `static append_unique(base: Array, extra: Array) -> Array` | A new array: `base` plus each item of `extra` that nothing before it `deep_equal`s (Objects by identity). Repeats within `extra` are added once; duplicates already in `base` stay. Inputs untouched; added items shared. Compares every pair: for up to a few thousand items. |
| `merge_resource` | `static merge_resource(target_object: Resource, ...dictionaries: Array) -> Resource` | Returns `target_object.duplicate(true)` with every key/value of each dictionary `set()` on it, in order. A key that is not a property of the resource is ignored and reported through `LFLogger` as a warning naming it. |
| `are_resources_equal` | `static are_resources_equal(props: Array[String], target: Resource, ...resources: Array) -> bool` | True if every resource matches `target` (via `deep_equal`) on the listed props only. A prop missing from a resource's property list compares as `null`. A `null` resource returns false; no resources returns true. |
| `property_names` | `static property_names(resource: Resource) -> Array[String]` | Names from `resource.get_property_list()`. |
| `deep_equal` | `static deep_equal(a: Variant, b: Variant) -> bool` | Recursive structural equality for Arrays and Dictionaries; other values compare as `same_value` does, except that NaN equals NaN (in a float, and in a component of a Vector2/3/4, Color, Quaternion or packed float array). Exact up to `DEEP_EQUAL_MAX_DEPTH` (100) nested Arrays/Dictionaries; see Notes. |
| `DEEP_EQUAL_MAX_DEPTH` | `const DEEP_EQUAL_MAX_DEPTH: int` | `100`: how many nested Arrays/Dictionaries the element walk of `deep_equal` descends before it stops with a warning and answers `false`. |
| `move_node` | `static move_node(node: Node, new_parent: Node, set_owner := true, global_position: Variant = null) -> void` | Coroutine. Moves `node` under `new_parent` at the end of the frame as one deferred step, then returns; sets `owner` unless `set_owner` is false. A `global_position` (Vector2 for a Node2D or Control, Vector3 for a Node3D) is set right after the reparent, so a moved, rotated or scaled parent does not shift the node; it is also applied when the node already is a child of `new_parent`; the wrong kind of value is reported and ignored. If either is freed meanwhile nothing happens (the node stays where it was); of several moves requested in one frame the last wins; a no-op when already the parent (without a `global_position`); a move under the node itself or one of its descendants is refused with an error. |
| `sync_children` | `static sync_children(parent: Node, count: int, create: Callable) -> void` | Leaves exactly `count` children: keeps the first ones, grows with `create.call(index)` (a returned parentless Node is added to `parent`), trims the tail with `remove_child` + `queue_free` (also the surplus when `create` adds more children than asked for). |
| `free_children` | `static free_children(parent: Node, filter := Callable()) -> void` | Detaches (`remove_child`) and `queue_free`s every child, or only those `filter.call(child)` accepts. Detached at once, so a rebuild in the same frame never sits beside stale children. An empty `Callable()` is no filter; a filter whose object was freed frees nothing and reports an error. |
| `disconnect_all` | `static disconnect_all(sig: Signal, only_object: Object = null) -> void` | Disconnects every connection of `sig`, or only those whose callable's object is `only_object`. |
| `min_by` | `static min_by(items: Array, key: Callable) -> Variant` | The item with the smallest `key.call(item)`; the first wins a tie (all-`INF` keys return the first item); a NaN key never beats a number; null when empty. |
| `max_by` | `static max_by(items: Array, key: Callable) -> Variant` | The item with the largest `key.call(item)`; the first wins a tie; a NaN key never beats a number; null when empty. |
| `group_by` | `static group_by(items: Array, key: Callable) -> Dictionary` | `{ key: [items...] }`; keys in the order first met, items in their order. |
| `count_by` | `static count_by(items: Array, key: Callable) -> Dictionary` | `{ key: count }`; keys in the order first met. |
| `find_by` | `static find_by(items: Array, key: Variant, value: Variant) -> Variant` | The first item whose `item.get(key)` (Dictionary entry or Object property) is `same_value` as `value`, or null. Null and freed items are skipped. |
| `index_by` | `static index_by(items: Array, key: Variant) -> Dictionary` | `{ item.get(key): item }`; a later item wins a repeated key. Null and freed items are skipped. |
| `lower_median` | `static lower_median(values: Array) -> Variant` | The lower of the two middle values for an even count; null when empty; `values` untouched. |
| `same_value` | `static same_value(a: Variant, b: Variant) -> bool` | `==` that is false (never an error) across types — except an int and a float (compared as numbers) and a String and a StringName (compared by content). |
| `get_project_screen_size` | `static get_project_screen_size() -> Vector2` | `display/window/size/viewport_width/height` from ProjectSettings (configured size, not the live window). |
| `random_point_in_rect` | `static random_point_in_rect(rect: Rect2, rng: RandomNumberGenerator = null) -> Vector2` | Uniform point inside `rect`, edges inclusive; drawn from `rng` when given (reproducible). Without `rng` it uses Godot's global generator (not reproducible), with no error: it is meant for cosmetic placement; pass a generator for anything that must replay. |

## Usage

```gdscript
# arena.gd — on a Node2D that holds the units, with a VBoxContainer for the score list
extends Node2D

@onready var score_list: VBoxContainer = $UI/ScoreList

var units: Array = [
	{"name": "Ann", "team": "red", "power": 7, "pos": Vector2(10, 0)},
	{"name": "Bob", "team": "blue", "power": 9, "pos": Vector2(50, 20)},
	{"name": "Cid", "team": "red", "power": 4, "pos": Vector2(-30, 5)},
]

func _ready() -> void:
	await LFUtils.timeout(250)                         # wait 250 ms (game time)
	LFUtils.create_timer(1000, func(): print("1 s"))   # fire and forget

	var by_team := LFUtils.group_by(units, func(u): return u["team"])   # {"red": [Ann, Cid], "blue": [Bob]}
	var strongest: Dictionary = LFUtils.max_by(units, func(u): return u["power"])   # Bob
	var closest: Dictionary = LFUtils.min_by(units, func(u): return u["pos"].length())   # Ann
	var bob: Dictionary = LFUtils.find_by(units, "name", "Bob")
	print(by_team.keys(), strongest["name"], closest["name"], bob["power"])

	# One Label per unit; existing rows are kept, extras removed at once.
	LFUtils.sync_children(score_list, units.size(), func(_i: int): return Label.new())
	for i in units.size():
		(score_list.get_child(i) as Label).text = units[i]["name"]

	var spawn := LFUtils.random_point_in_rect(Rect2(Vector2.ZERO, LFUtils.get_project_screen_size()))
	print("spawn at ", spawn)

	LFUtils.poll_each_frame(self, &"_poll")   # calls _poll() every frame while it returns true

var _frames := 0

func _poll() -> bool:
	_frames += 1
	return _frames < 60                       # stop after 60 frames
```

More one-liners (inside any function; `base_stats` is a Resource, `unit`, `new_parent` and `score_list` Nodes, `button` a Button):

```gdscript
var merged := LFUtils.merge_arrays([1, 2], [3], [4, 5])                  # [1, 2, 3, 4, 5]
var faster: Resource = LFUtils.merge_resource(base_stats, {"speed": 2.0})  # a copy; base_stats untouched
var same := LFUtils.deep_equal({"a": [1, 2]}, {"a": [1.0, 2.0]})      # true
await LFUtils.move_node(unit, new_parent)                             # reparent at the end of the frame
LFUtils.free_children(score_list)                                     # empty a container right now
LFUtils.disconnect_all(button.pressed)                                # drop every listener of a signal
var middle = LFUtils.lower_median([5, 1, 4, 2])                       # 2
```

## Notes
- **Deeply nested values.** `deep_equal` is exact for values nested up to `DEEP_EQUAL_MAX_DEPTH` (100) Arrays/Dictionaries deep. For speed it asks Godot's own `==` first at each level (the element walk is far slower). That comparison gives up after 100 recursion steps (51 nested containers in Godot 4.7, each takes two), logs "Max recursion reached" and counts everything below as equal, so an equal answer from `==` also needs equal `hash()` values (which look about 101 levels deep); a pair failing either is walked element by element. This costs extra time on equal values (a 500-entry snapshot diff measured about 0.37 ms against 0.23 ms without the hash check, once, on an Apple-silicon Mac) and prints the engine's "Max recursion reached" lines for values nested more than about 50 deep. The element-by-element walk stops at `DEEP_EQUAL_MAX_DEPTH` (100), pushes a warning and answers `false`, so a deeply nested input from outside (a 1,000-level JSON document) does not overflow the script stack. `LFDictionary.diff` has the same exactness.
- Timers, `timeout`, and `move_node` need a running `SceneTree` (the tree of nodes of the running game; any normal game or *F6* run has one). `new_parent` itself doesn't have to be in the tree.
- `merge_resource` makes its copy with `Resource.duplicate(true)`, which only copies properties marked `@export`; other variables of the resource go back to their defaults on the copy.
- `move_node` assigns `owner = new_parent` by default (pass `set_owner = false` to keep it), which changes what gets saved if the node is packed into a scene.
- `find_by` / `index_by` skip null and freed items; `find_by(nodes, 'name', 'Enemy')` works with a plain String.
- `merge_arrays` copies only the first array, with `Array.duplicate(true)`: arrays and dictionaries nested in it are copied, but every Object in it (a Resource, a Node) is the same instance in the result, so editing a Resource from the merged array edits the original. Items taken from the other arrays are shared too. `merge_arrays_deep` also copies the first array's Resources, (sub-resources saved in their own file, such as a texture, stay shared).
- `append_unique` compares with `deep_equal` (content for arrays and dictionaries, identity for Objects, `1` equals `1.0`) and checks every added item against every kept one, so it costs items squared.
- `create_timer(..., real_time = true)` counts real-world time, for waits that must not stretch when the game runs in slow motion (`Engine.time_scale`).
- `poll_each_frame` stops on any return value other than the bool `true` (a step that returns nothing stops after the first call). Its first call runs synchronously, before `poll_each_frame` returns.
- `sync_children` reports an error and stops if `create` neither returns a parentless Node nor adds a child itself.
