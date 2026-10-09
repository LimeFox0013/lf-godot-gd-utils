# LFFile

> Save, load, copy and delete files and folders on any path, with saves that replace the file by rename, so a game crash mid-save leaves the old content (Windows: see Notes).

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_file.gd` |
| **Tests** | `tests/test_lf_file.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` (error reporting), `LFJson` (quiet parsing), `LFText` (quiet UTF-8 decoding) |

## When to use it

Use it for save files, settings, downloaded content and caches: `LFFile.save_json` and
`LFFile.load_json` are one line each, a game that
crashes mid-save does not leave a half-written file at the path (the new content replaces
the old in one rename, called "atomic"; see Notes for the limits), and a missing file simply reads as empty.
`join_inside` keeps a file name that came from a player, a mod or the network from escaping
its folder (`../../`). `remove_recursive` clears a cache folder without following links out
of it. Godot's `FileAccess` and `DirAccess` are fine for one-off reads; Godot's
`ConfigFile` or `ResourceSaver` suit engine types. To keep a value in memory and on disk in
sync, use `LFJsonFileObserver`.

## `res://` versus `user://`

Godot has two special folders you will see in every path:

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

1. In Godot, choose *Scene → New Scene*, then click **Other Node** in the Scene dock and pick
   a plain **Node**. Save it with *Scene → Save Scene* (Ctrl+S) as `file_demo.tscn`.
2. Right-click the Node in the Scene dock and choose **Attach Script**. Leave the defaults
   (language GDScript) and click **Create**. The script editor opens.
3. Replace the script's contents with this:

```gdscript
extends Node


func _ready() -> void:
	# Write a small piece of data to a file in the game's save folder.
	# save_json returns true when the file was written.
	var saved := LFFile.save_json("user://profile.json", {"name": "Ann", "coins": 12})
	print("saved: ", saved)

	# Read it back. A Dictionary is a set of named values; a missing or broken
	# file gives an empty one ({}), so this line never crashes.
	var profile := LFFile.load_json("user://profile.json")
	print(profile)
	print("coins: ", profile.get("coins", 0))
```

4. Press **F6** (*Run Current Scene*). The Output panel at the bottom shows `saved: true`,
   then `{ "coins": 12.0, "name": "Ann" }` and `coins: 12.0`. Numbers always come back with a decimal point
   after a round trip through JSON (the text format files are written in); that is normal.
5. Choose **Project → Open User Data Folder**. You will find `profile.json` there; open it
   in any text editor to see the saved text.
6. Change `"user://profile.json"` to a name of your choice, and the dictionary to your
   own data (text in quotes, numbers, `true`/`false`, lists in `[...]`, nested dictionaries
   in `{...}`). Run again: the new file appears.
7. To start fresh, call `LFFile.remove("user://profile.json")` (one file) or
   `LFFile.remove_recursive("user://some_folder")` (a folder and everything in it).

## API

Everything the class offers; you only need the rows used in the steps above to get started.

### Enums and inner classes

| Member | Signature | Description |
|---|---|---|
| `PathTarget` | `enum { MISSING, FILE, DIR }` | Result of `path_leads_to`. |
| `TextRead` | `class TextRead { text: String, error: Error }` | Result of `read_text`. `error` is `OK`, `ERR_FILE_NOT_FOUND` (no file at the path: nothing, or a directory), `ERR_FILE_CANT_READ` (a file is there but could not be read) or `ERR_OUT_OF_MEMORY` (larger than `max_bytes`). `text` is `""` unless `error` is `OK`. |

### Writing

| Member | Signature | Description |
|---|---|---|
| `save` | `static save(path: String, content: String, ensure_file := true) -> bool` | Replaces the file atomically: writes a hidden `.lf-tmp-*` file in the same folder, checks every byte arrived, then renames it over the file. A save that fails leaves the previous content intact and removes its temporary file; a crash mid-save leaves the previous content (on Windows there is an instant with no file at all, see Notes) and may leave the `.lf-tmp-*` file behind. A missing file (and its directories) is created only when `ensure_file`; otherwise nothing is written and it returns `false`. A path ending in `/` or `\` names a directory and is refused. A failure pushes an error. |
| `save_bytes` | `static save_bytes(path: String, bytes: PackedByteArray, ensure_file := true) -> bool` | `save` for binary content. |
| `save_json` | `static save_json(path: String, value: Variant) -> bool` | `save(path, JSON.stringify(value))`, for any JSON value. |
| `ensure_dir` | `static ensure_dir(path: String) -> Error` | Creates the **parent** directory of `path` (a path ending in `/` names the directory itself). `OK` when it exists afterwards. |
| `copy_to_dir` | `static copy_to_dir(src_path: String, dst_dir_path: String, overwrite := true) -> bool` | Copies a file into a directory (created if missing), keeping its name. The copy goes to a temporary name and is renamed into place, so a failed copy leaves an existing destination as it was. Copying a file onto itself — through any spelling of its directory (case, link) — is a successful no-op. `false` with a pushed error on a missing or unreadable source, a file as destination, an existing target with `overwrite = false`, or a failed copy. |
| `remove` | `static remove(path: String) -> Error` | Removes one file, one empty directory or one symbolic link (never what it points at). Nothing there is `OK`. An empty path is refused (`ERR_INVALID_PARAMETER`). |
| `move_aside` | `static move_aside(path: String, tag: String) -> String` | Renames the file at `path` to a free sibling `<file>.<tag>-<unix time>` (`tag` is a plain name, not checked) (adding `-1`, `-2`… when taken), keeping its content while a fresh file takes its place. Returns the new absolute path, or `""` when there is no file or the rename failed. Quiet. |
| `remove_recursive` | `static remove_recursive(path: String) -> Error` | Removes a file or a whole directory tree, hidden entries included. Links are removed, never followed. Nothing there is `OK`; an empty path and a filesystem root (`/`, `C:/`) are refused (`ERR_INVALID_PARAMETER`). Stops at the first entry it can't remove. |

### Reading

| Member | Signature | Description |
|---|---|---|
| `read_text` | `static read_text(path: String, max_bytes := 0) -> TextRead` | Reads through `readable_path`. Tells a missing file from one it can't read; refuses a file larger than `max_bytes` (when above 0) without reading it. Quiet: no engine errors, and bytes that aren't valid UTF-8 become U+FFFD. |
| `load_file` | `static load_file(path: String, ensure_file := false) -> String` | The file's text. A missing file reads as `""` quietly (and is created empty only with `ensure_file = true`, never inside an exported game's read-only `res://`). An unreadable file reads as `""` with a pushed error. |
| `load_json` | `static load_json(path: String, ensure_file := false) -> Dictionary` | Parses `load_file(...)` as a JSON object; `{}` when it isn't one. |
| `load_json_value` | `static load_json_value(path: String, ensure_file := false) -> Variant` | Any parsed JSON value (Dictionary, Array, number…); `null` when missing, empty or invalid. |

### Paths

| Member | Signature | Description |
|---|---|---|
| `readable_path` | `static readable_path(input_path: String) -> String` | The path `FileAccess` should open: `res://` and `user://` stay (simplified), relative → `res://`-relative, absolute unchanged. A `res://` or `user://` path never resolves outside its root, whatever the spelling: `..` stops at the root, and an embedded scheme or drive (`user://res://../..`, `user://C:/..`), backslashes and repeated slashes are plain segments (see Notes). |
| `to_absolute` | `static to_absolute(input_path: String) -> String` | Normalizes `\` to `/`, then: absolute (POSIX or `C:/`) → simplified as-is; everything else → `readable_path`, globalized. Agrees with `readable_path`, so a save and a load of one path touch one file. `""` → the project directory. |
| `path_leads_to` | `static path_leads_to(path: String) -> PathTarget` | `FILE` / `DIR` / `MISSING`, checked through `readable_path`, so files inside an exported pack count. |
| `path_exists` | `static path_exists(path: String) -> bool` | `path_leads_to(path) != MISSING`. |
| `is_blank` | `static is_blank(path: String) -> bool` | True when the file holds only whitespace bytes or nothing. A file of control bytes (which `read_text` shows as empty) is not blank. |
| `is_inside` | `static is_inside(root: String, path: String) -> bool` | `path` is `root` or below it (both absolutized, `..` resolved), and nothing that exists below `root` on the way to `path` (`path` itself included) is a symbolic link; `root` itself may be one. An empty `root` contains nothing. |
| `join_inside` | `static join_inside(root: String, name: String, portable_only := false) -> String` | `root` joined with the relative `name` (backslashes and `..` resolved, a leading `/` ignored), or `""` when the result is not `is_inside(root, …)`. Also `""` when a segment of `name` fails `is_portable_name` and either this runs on Windows (where `CON`, `a.txt:stream` or `notes.` would open a device, write an NTFS stream or land on another file) or `portable_only` is set, so a name accepted on Linux is accepted on Windows too (`LFZipExtractor` sets it). On Linux, macOS and other systems, without `portable_only`, names the system allows (`12:30.log`, `notes.`) are kept. For names that come from outside (archives, network, user input). |
| `is_portable_name` | `static is_portable_name(segment: String) -> bool` | One file or folder name that Windows can create as written: not empty, no `:` (a drive or an NTFS stream), not ending in `.` or a space (Windows drops those), not a device name (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`, any case, with or without an extension). Other characters Windows refuses (`<>"\|?*`, control characters) are not checked; creating such a file fails there. |

## Usage

A script on any node:

```gdscript
extends Node


func _ready() -> void:
	# Save and load a JSON file in the player's save folder.
	if not LFFile.save_json("user://settings/profile.json", {"volume": 0.8}):
		push_warning("settings not saved; the old ones are still on disk")
	var profile := LFFile.load_json("user://settings/profile.json")  # {"volume": 0.8}
	print(profile)

	# Tell "no file yet" from "a file I can't read" (and refuse files over 1 MiB).
	var read := LFFile.read_text("user://settings/profile.json", 1024 * 1024)
	if read.error == ERR_FILE_CANT_READ:
		push_warning("the profile exists but can't be read; leave it alone")

	# A name from outside (a mod, a download) must stay inside its folder.
	save_mod("cool-mod", "{}")
	save_mod("../../escape", "{}")   # refused: join_inside returns ""

	LFFile.remove_recursive("user://cache")


func save_mod(mod_name: String, mod_text: String) -> void:
	var dest := LFFile.join_inside("user://mods", "%s/mod.json" % mod_name)
	if dest != "":
		LFFile.save(dest, mod_text)
```

## Notes

- How `res://` and `user://` paths are resolved, so no spelling leaves the root: backslashes become `/`, empty segments (`//`) and `.` are dropped, `..` removes the segment before it and is dropped at the root, and a segment made only of dots and spaces with two or more dots (`...`, `.. `, which Windows trims to `..`) counts as `..`. Anything else after the scheme is a plain name, even `res:` or `C:`, so `user://res://../../x` is `user://x`. Percent-encoding is not decoded (`%2e%2e` is a name). This holds for every entry point (`save*`, `ensure_dir`, `copy_to_dir`, `remove*`, `move_aside`, the reads), all of which resolve through `readable_path` / `to_absolute`. Absolute paths are not confined: they are the caller's choice; use `join_inside` for names from outside.
- Relative paths resolve against `res://` (the project folder), not `user://`. Writing to `res://` in an exported build fails; use `user://` for data created while playing.
- `save*`, `copy_to_dir` and `remove*` work on real disk paths ("globalized": `user://x` turned into the full path on your drive), so they can't reach a `res://` file packed inside an exported game; only `read_text`, `load_*`, `path_leads_to` and `path_exists` see the pack.
- An atomic save needs to create a file in the target's directory: a writable file in a read-only directory can't be saved. A save replaces a symbolic link (a shortcut-like file that points elsewhere) at the path with a regular file (the file the link pointed at is left as it was), and the new file gets default permissions.
- On Windows the engine replaces a file by removing it and then moving the new one in; a crash in that instant leaves no file at the path and the new content in a `.lf-tmp-*` file in the same folder. A crash mid-save on any platform can leave such a file behind; it is never read. The temporary name has a fixed length, so it does not push a long file name over the name-length limit.
- A save is not forced to the disk (no `fsync`): it survives the game crashing, but a power loss or an operating-system crash right after a save can lose it, or on some file systems leave an empty file.
- Reads never create anything by default (`ensure_file := false`). Reads are unbounded except through `read_text(path, max_bytes)`.
- JSON is lossy: numbers come back as `float` (`{"a": 1}` loads as `{"a": 1.0}`, and integers past 2^53 lose precision), `NaN` becomes `null`, `INF` is written as `1e99999`, and a `Vector3`, `Color` or Object is written as its `String`. Use Godot's `JSON.from_native` / `JSON.to_native` (they keep engine types as plain data) before `save_json` / after `load_json_value` to keep engine types.
- `load_json` returns `{}` for an empty file, invalid JSON, or JSON that isn't an object, without logging an engine error.
- Errors go through `LFLogger`, so `LFLogger.enable_print_errors = false` silences them; the return values still report the failure.
- All calls are synchronous, blocking I/O. They keep no state beyond a logger and a counter for temporary names (which also carry the thread id); `LFZipExtractor` calls `save_bytes`, `join_inside` and `remove_recursive` from its worker thread, and no other threading is tested.
