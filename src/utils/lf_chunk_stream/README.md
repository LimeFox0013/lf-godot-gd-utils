# LFChunkStream

> Keeps a window of numbered level chunks alive around the one the player is in: builds the ones ahead, removes the ones far behind.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_chunk_stream.gd` |
| **Tests** | `tests/test_lf_chunk_stream.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it for a level built from equal pieces laid end to end that goes on for ever or for
longer than you want in memory: a tower you climb, a road, a side-scrolling corridor. You say
which piece the player is in (`focus(index)`); it asks you to build the missing ones near it
and to remove the ones that are left behind. It never touches a node itself: you give it two
functions, so the chunks can be scenes from an `LFFactory` pool, generated meshes, or plain
data. To show only the visible rows of a long 2D list under a `Camera2D` use `LFVirtualGrid`.

## Step by step

This prints which chunks exist as you move along.

1. In the editor choose *Scene → New Scene*, click *Other Node*, pick **Node** and press *Create*.
2. Right-click the node, choose *Attach Script*, keep the defaults and press *Create*.
3. Replace the script's text with this:

```gdscript
extends Node

var _stream := LFChunkStream.new(_build, _remove, 2, 1)   # 2 chunks ahead, 1 behind
var _position := 0

func _ready() -> void:
	_stream.min_index = 0             # nothing exists below chunk 0
	_stream.focus(_position)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		_position += 1
		_stream.focus(_position)
		print("chunks: ", _stream.indices())

func _build(index: int) -> Variant:
	print("build ", index)
	return "chunk %d" % index         # a real game returns a Node here

func _remove(index: int, _chunk: Variant) -> void:
	print("remove ", index)
```
4. Save the scene and press **F6**. The output shows `build 0`, `build 1`, `build 2`.
5. Press the Right arrow repeatedly: each press builds one chunk ahead; after the first
   few it also removes the chunk two behind.
6. Return a `Node` from `_build` (add it to your level yourself) and free or hide it in `_remove`.

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_AHEAD` / `DEFAULT_BEHIND` | `const … := 3` | Window sizes used when none are given. |
| `UNBOUNDED` | `const UNBOUNDED := 1 << 62` | The "no limit" value of `min_index` / `max_index`. |
| `_init` | `LFChunkStream.new(initial_spawn: Callable, initial_despawn: Callable, initial_ahead := 3, initial_behind := 3)` | Builds nothing until `focus`. |
| `spawn_fn` | `var spawn_fn: Callable` | `func(index: int) -> Variant`: builds a chunk and returns it (null is reported and leaves the index empty). |
| `despawn_fn` | `var despawn_fn: Callable` | `func(index: int, chunk: Variant) -> void`: removes a chunk that left the window. |
| `ahead` / `behind` | `var ahead: int`, `var behind: int` | Chunks kept after / before the focused one; below 0 counts as 0. |
| `min_index` / `max_index` | `var … := ±UNBOUNDED` | The window never reaches outside these. |
| `chunk_spawned` / `chunk_despawned` | `signal …(index: int, chunk: Variant)` | After a chunk is built / removed. |
| `focus` | `focus(index: int) -> void` | Moves the window: removes outside (lowest first), builds missing inside (lowest first). Clamps `index` to the bounds; with `min_index` above `max_index` it reports an error, removes every chunk and builds none. A call from inside `spawn_fn` / `despawn_fn` waits; the last one wins. |
| `focused_index` | `focused_index() -> Variant` | The clamped index of the last `focus`; null before it. |
| `chunk_at` / `has_chunk` / `index_of` | `chunk_at(index)`, `has_chunk(index) -> bool`, `index_of(chunk) -> Variant` | Look chunks up either way; null when absent. |
| `indices` / `count` | `indices() -> Array[int]`, `count() -> int` | The tracked indices, lowest first / how many. |
| `clear` | `clear() -> void` | Removes every chunk and forgets the focus. A `focus` from inside `despawn_fn` during it is dropped; a `clear` from inside a running `focus`'s callbacks is reported and ignored. |

## Usage

A tower made of pooled scenes, six units tall each, driven by the chunk the player enters:

```gdscript
const CHUNK_HEIGHT := 6.0
var _pool := LFFactory.new()
var _stream: LFChunkStream

func _ready() -> void:
	_pool.set_container($Chunks)
	_pool.register(&"chunk", CHUNK_SCENE.instantiate)
	_stream = LFChunkStream.new(_build, _remove, 3, 2)
	_stream.min_index = 0
	_stream.focus(0)

func _build(index: int) -> Node3D:
	var chunk: Node3D = _pool.acquire(&"chunk")
	chunk.position.y = index * CHUNK_HEIGHT
	return chunk

func _remove(_index: int, chunk: Node3D) -> void:
	_pool.release(chunk)

# Connected to each chunk's "player entered" signal:
func _on_chunk_entered(chunk: Node3D) -> void:
	_stream.focus(_stream.index_of(chunk))
```

## Notes

- Place chunks from their index (`index * CHUNK_HEIGHT`), not from a neighbour: after the player goes back down, chunks behind are rebuilt and their neighbour may not exist.
- Connect a chunk's "player entered" signal once, when the chunk is first created, not on every `spawn_fn` call, or a reused chunk collects duplicate connections.
- `focus` with the index already focused only fills gaps; it is cheap to call every frame.
- The stream holds the chunks it was given; it frees nothing. `clear()` calls `despawn_fn` for each.
- If `min_index` is greater than `max_index` the range is empty: `focus` logs an error, removes all chunks, builds none and leaves `focused_index()` null.
