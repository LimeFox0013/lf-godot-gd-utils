# LFFileObserver, LFJsonFileObserver

> A value that lives in a file: change it and the file on disk updates at once, read it and it loads for you.

| | |
|---|---|
| **Files** | `lf_file_observer.gd`, `lf_json_file_observer.gd` |
| **Tests** | `tests/test_lf_file_observer.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFFile` (`read_text`, `save`), `LFDictionary` (JSON path helpers), `LFJson` (quiet parsing), `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFFileObserver` | Object: create it with `.new()` |
| `LFJsonFileObserver` | Object: create it with `.new()` |

## When to use it

Use it for a settings or profile file that the game reads and changes while it runs: the
options menu calls `settings.set_by_path("audio.volume", 0.5)` and the file on disk is
updated at once, with no separate "save" step to forget. `LFJsonFileObserver` is the one
you usually want; `LFFileObserver` with your own transforms covers other text formats. It
never overwrites a file it couldn't read, and moves a corrupt JSON file aside instead of
destroying it. For a one-off save or load, call `LFFile.save_json` / `LFFile.load_json`
directly; Godot's `ConfigFile` suits INI-style files.

## `res://` versus `user://`

Godot has two special folders you will see in every path. For a settings file you almost always want `user://`:

- **`res://`** is your project folder, the one shown in the FileSystem dock. It is where
  your scenes, scripts and art live. In the editor you can write there, but in an
  **exported game it is read-only** (it is packed inside the game file). Never save a
  player's progress to `res://`.
- **`user://`** is a folder Godot keeps for your game's data on the player's computer:
  save games, settings, downloads. An exported game can write there (unlike `res://`), and
  it survives updates of the game. Use it for anything the game creates while running.

To see the real folder on your disk, choose **Project → Open User Data Folder** in the
editor. By default it is:

| System | Where `user://` is |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\<project name>` (type that into the Explorer address bar) |
| macOS | `~/Library/Application Support/Godot/app_userdata/<project name>` |
| Linux | `~/.local/share/godot/app_userdata/<project name>` |

If the project turns on *Project Settings → Application → Config → Use Custom User Dir*, the
folder is named after *Custom User Dir Name* instead (and sits next to the `Godot` /
`godot` folder rather than inside it). *Open User Data Folder* always shows the real one.

## Step by step

1. Choose *Scene → New Scene*, click **Other Node** in the Scene dock and pick a plain
   **Node**. Save it (Ctrl+S) as `settings_demo.tscn`.
2. Right-click the Node and choose **Attach Script**, then **Create**.
3. Replace the script's contents with this:

```gdscript
extends Node

# The file this object keeps in sync. Make it once and keep it in a variable.
var settings := LFJsonFileObserver.new("user://settings.json")


func _ready() -> void:
	# A signal is an event other code can listen to. "saved" fires after each save.
	settings.saved.connect(_on_settings_saved)

	# Read a value. "audio.volume" means the "volume" entry inside "audio".
	# The second argument is used when the file has no such value yet.
	var volume: float = settings.get_by_path("audio.volume", 1.0)
	print("volume was: ", volume)

	# Change a value: the file is written right now. (0.5 is half volume.)
	settings.set_by_path("audio.volume", 0.5)


func _on_settings_saved() -> void:
	print("saved: ", settings.data)
```

4. Press **F6** (*Run Current Scene*). The Output panel shows `volume was: 1.0`, then
   `saved: { "audio": { "volume": 0.5 } }`.
5. Press F6 again. This time it prints `volume was: 0.5`: the value was remembered in the
   file. Open it with *Project → Open User Data Folder* and look for `settings.json`.
6. For your own game, change the file name and the path strings (`"audio.volume"`,
   `"video.fullscreen"`, ...) and the fallback value. Delete `settings.json` to start over.

## API

Everything the class offers; you only need the rows used in the steps above to get started.

### LFFileObserver

#### Signals

| Member | Signature | Description |
|---|---|---|
| `saved` | `signal saved` | Emitted after every successful write (once per `edit` or assignment, even when the value is unchanged). |

#### Properties

| Member | Signature | Description |
|---|---|---|
| `data` | `var data: Variant` (get/set) | **Get:** the first read loads the file through `LFFile.read_text` (a missing file reads as `""` and is not created) and runs `transform_out`; later reads return the cached value itself — change it through `edit` or by assigning, never in place. **Set:** saves `transform_in(new_data)` with `LFFile.save`; only when that succeeds does it cache the value and emit `saved`. Refused with a pushed error (nothing changes) when the file can't be read, changed on disk since it was read, or `transform_in` returned something other than a `String`. |

#### Methods

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFFileObserver.new(file_path: String = '', transform_out: Callable = <identity>, transform_in: Callable = <identity>)` | `transform_out(file_text) -> data` runs on load; `transform_in(data) -> String` runs on save. Both default to passing the value through (the data is the file's text). |
| `edit` | `edit(change: Callable) -> bool` | `change` receives a deep copy of the data and returns the new data, which is written once. If the file changed on disk since it was read, it is re-read first and `change` applies to that content, so another writer's change is kept. Returns whether it was written. `change` must not call back into this observer: such an inner write is overwritten by the outer result. |
| `reload` | `reload() -> bool` | Re-reads the file into the cache (no `saved`). `false` when it exists but can't be read. |

### LFJsonFileObserver

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFJsonFileObserver.new(file_path: String = '')` | Uses `JSON.stringify` on save and a quiet parse on load. Missing, empty or whitespace-only content becomes `{}`. Content that isn't a JSON object (unparseable, e.g. `[1]`, or a file of control bytes such as zero bytes, which is not read as empty) is moved to `<file>.corrupt-<unix time>` (with a pushed warning) and loads as `{}`; when it can't be moved, writes are refused. A value that isn't a `Dictionary` is refused on save. |
| `set_by_path` | `set_by_path(props_path: String, value: Variant) -> bool` | `edit` that sets `props_path` (e.g. `"a.b"`) via `LFDictionary.set_by_path`. |
| `erase_by_path` | `erase_by_path(props_path: String) -> bool` | `edit` that erases `props_path` via `LFDictionary.erase_by_path`; a missing path keeps the rest. |
| `get_by_path` | `get_by_path(props_path: String, fallback_value: Variant = null) -> Variant` | A copy of the value at `props_path` (changing it does not change the observer's data). `fallback_value` only when that value is `null`, so a stored `0`, `false` or `""` is returned as-is. |

## Usage

A script on any node (e.g. the options menu):

```gdscript
extends Node

var settings := LFJsonFileObserver.new("user://settings.json")


func _ready() -> void:
	settings.saved.connect(_on_settings_saved)

	var volume: float = settings.get_by_path("audio.volume", 1.0)
	print("volume: ", volume)
	settings.set_by_path("audio.volume", 0.5)   # written to disk, emits saved

	# Several changes, one write:
	settings.edit(func(d: Dictionary) -> Dictionary:
		d["muted"] = false
		d["language"] = "en"
		d.erase("legacy_flag")
		return d
	)


func _on_settings_saved() -> void:
	print("saved: ", settings.data)
```

## Notes

- Writes are synchronous and go through `LFFile.save` (a rename over the old file; see LFFile's Notes for what that does and does not survive). The file is written **before** the in-memory value changes, and a failed write changes nothing.
- A file that exists but can't be read (permissions, another process holding it) is never overwritten: `data` reads as for an empty file, writes are refused, and `edit` / `reload` pick it up once it is readable again.
- Several observers (or processes) may share a file: every write first compares the file with what this observer last read or wrote. `edit` (and the path helpers) re-read and re-apply; assigning `data` is refused instead of discarding the other change. The check and the write are not one atomic step, so two writes in the same instant can still race.
- Reads don't revalidate: after the first read, changes made outside the observer show up only on `reload` or the next `edit`.
- A transform (a function you pass in to convert text and data) written as a lambda (an inline function) that uses a variable holding the observer keeps the observer in memory forever: the observer holds the transform, which holds the observer. The same goes for a lambda that uses `self` when `self` is a RefCounted object (not a Node) holding the observer. Pass a method, or a lambda that uses neither; a method holds no reference, and Nodes are not reference-counted.
- `transform_in` must return a `String`; anything else is refused before the file is touched.
- Corrupt-file backups are never cleaned up by the observer; they sit beside the file for a human (or the program) to recover.
- The file path is only set in the constructor.
- `LFJsonFileObserver` returns numbers as `float` (decimal numbers) after a reload: `1` comes back as `1.0`, which is how JSON works.
