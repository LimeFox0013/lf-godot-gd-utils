# LFZip, LFZipExtractor

> Unpacks a ZIP file into a folder in the background, checking the archive first, and undoing a half-finished result if moving the files in fails.

| | |
|---|---|
| **Files** | `lf_zip.gd`, `lf_zip_extractor.gd` |
| **Tests** | `tests/test_lf_zip.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFThread` (worker), `LFFile` (`to_absolute`, `join_inside`, `save_bytes`, `remove_recursive`), `LFLogger`, `LFText` (lossy UTF-8 names), `LFUtils` (`tree_root`, `poll_each_frame`) |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFZip` | Static: call it on the class name |
| `LFZipExtractor` | Object: create it with `.new()` |

## When to use it

Use it to unpack a downloaded mod, level pack or content update into `user://` without
freezing the game (on builds with thread support; see Platforms below), with a progress
bar. An archive that breaks the rules below is refused whole before anything is written
to the target folder: no file written outside the target folder, no entry name
Windows cannot create, no "zip bomb" (a tiny file whose declared sizes are over your
limits). If moving the unpacked files into place fails partway, what was moved is undone,
so a failed install does not leave half a mod behind (see Notes for what this cannot
cover).
`await LFZip.extract(zip, folder)` is the one-line version; `LFZip.create_extractor` gives
you progress, limits and canceling.
Godot's `ZIPReader` reads single files out of an archive and `ZIPPacker` creates
archives; neither runs in the background or checks entry paths for you.

## `res://` versus `user://`

Godot has two special folders you will see in every path. Extract into `user://`:

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

**Platforms:** tested on desktop (macOS). On a build without thread support (a web
export with *Thread Support* off, the default since Godot 4.3) there is no background
thread: `LFThread` runs the whole extraction on the main thread, blocking the game for its
whole length in one frame, `entry_processed` arrives all at once afterwards, and `cancel` cannot
interrupt it. Not tested on an actual web export.

## Step by step

1. Choose *Scene → New Scene*, click **Other Node** in the Scene dock and pick a plain
   **Node**. Save it (Ctrl+S) as `zip_demo.tscn`.
2. Right-click the Node and choose **Attach Script**, then **Create**.
3. Replace the script's contents with this. It first makes a tiny ZIP file to practise on
   (with Godot's own `ZIPPacker`); with your own ZIP, skip that part and use its path.

```gdscript
extends Node


func _ready() -> void:
	# Start clean so you can run this scene again and again.
	LFFile.remove_recursive("user://unzipped")

	# Make a ZIP file with one file inside, "hello.txt".
	var packer := ZIPPacker.new()
	if packer.open("user://demo.zip") != OK:
		push_error("could not create the zip")
		return
	packer.start_file("hello.txt")
	packer.write_file("Hello from a zip!".to_utf8_buffer())
	packer.close_file()
	packer.close()

	# "await" means: wait here until the unzipping has finished, then continue.
	# It gives two true/false answers: [success, canceled].
	var result: Array = await LFZip.extract("user://demo.zip", "user://unzipped/")
	print("result: ", result)
	print("hello.txt says: ", LFFile.load_file("user://unzipped/hello.txt"))
```

4. Press **F6** (*Run Current Scene*). The Output panel shows `result: [true, false]`
   (it worked, it was not canceled) and `hello.txt says: Hello from a zip!`.
5. Open *Project → Open User Data Folder*: it now holds `demo.zip` and an `unzipped` folder
   with `hello.txt`.
6. For your own ZIP, put it in the user folder (or give its full path) and change the two
   paths in `LFZip.extract(zip_file, target_folder)`. The target folder is created if it is
   missing. By default a file that already exists in the target makes the whole archive be
   refused (`result` is `[false, false]`); pass `true` as a third argument
   (`LFZip.extract(zip, folder, true)`) to let files be replaced.
7. For a progress bar, a size limit or a Cancel button, use `LFZip.create_extractor(...)`
   as shown under Usage below.

## API

Everything the class offers; you only need the rows used in the steps above to get started.

### LFZip

| Member | Signature | Description |
|---|---|---|
| `create_extractor` | `static create_extractor(path_to_zip: String, path_to_extract: String) -> LFZipExtractor` | A configured extractor, not started, with the default limits and `overwrite = false`. `path_to_extract` is the output directory (`res://`, `user://` or absolute; with or without a trailing slash). |
| `extract` | `static extract(path_to_zip: String, path_to_extract: String, overwrite: bool = false) -> Array` (await) | Creates and starts an extractor, awaits it and returns `[success, canceled]`. A target `start` refuses returns `[false, false]` at once. |

### LFZipExtractor

#### Constants

| Member | Value | Description |
|---|---|---|
| `DEFAULT_MAX_ENTRIES` | `10000` | Default `max_entries`. |
| `DEFAULT_MAX_ENTRY_BYTES` | `256 MiB` | Default `max_entry_bytes`. |
| `DEFAULT_MAX_TOTAL_BYTES` | `1 GiB` | Default `max_total_bytes`. |

#### Signals

| Member | Signature | Description |
|---|---|---|
| `entry_processed` | `entry_processed(percent: float, file: String, index: int, total: int)` | Once per archive entry as it is decompressed into the staging folder (also for an entry that fails there), on the main thread, a frame or so after the worker got there. `percent` is `index / total * 100`; `index` counts from 1. |
| `finished` | `finished(success: bool, canceled: bool)` | On the main thread when the run ends. `success`: every entry is now in the target (an empty archive succeeds and only creates the target). `canceled`: `cancel` stopped it before anything was moved into the target. |

#### Properties

All are read once, when `start` is called; changing them during a run has no effect on it.

| Member | Signature | Description |
|---|---|---|
| `path_to_zip` | `var path_to_zip: String` | The archive (any path `LFFile` resolves). |
| `path_to_extract` | `var path_to_extract: String` | Destination directory, created if missing. Must be absolute, `res://` or `user://`; empty or relative is refused by `start`. |
| `max_entries` | `var max_entries: int = DEFAULT_MAX_ENTRIES` | Most entries the archive may hold. `0` means unlimited. |
| `max_entry_bytes` | `var max_entry_bytes: int = DEFAULT_MAX_ENTRY_BYTES` | Largest uncompressed size one entry may **declare**. Checked before the entry is decompressed, so it bounds memory as well as disk. `0` means unlimited. |
| `max_total_bytes` | `var max_total_bytes: int = DEFAULT_MAX_TOTAL_BYTES` | Largest declared uncompressed size of all entries together. `0` means unlimited. |
| `overwrite` | `var overwrite: bool = false` | Whether an entry may replace a file already in the target. |
| `failed_entries` | `var failed_entries: PackedStringArray` | Set before `finished`: the entries that made the run fail (refused, corrupt, or the entry whose move into the target failed). Empty on success, on cancel, and when the archive as a whole was refused (unreadable, too many entries, over `max_total_bytes`). |
| `failure_reason` | `var failure_reason: String` | Set before `finished`: why the archive as a whole was refused (unreadable directory, a limit, a file listed twice…), or why moving into the target failed and whether that was undone. Empty on success, and when the failure is only individual entries (refused before staging, or failed while staging), which `failed_entries` names. |

#### Methods

| Member | Signature | Description |
|---|---|---|
| `start` | `start() -> bool` | Starts the worker. `false` (nothing starts) while a run is in progress, or with a pushed error when `path_to_zip` is empty, `path_to_extract` is empty or relative, or the main loop is not a `SceneTree`. |
| `cancel` | `cancel() -> void` | Stops before the next entry, or before anything is moved into the target: `finished(false, true)`. A run already moving entries into place completes. |

## Usage

A script on any node:

```gdscript
extends Node

var extractor: LFZipExtractor   # keep the reference until finished


func _ready() -> void:
	# One-shot: unzip and wait for the result.
	var result: Array = await LFZip.extract("user://downloads/levels.zip", "user://levels/")
	if result[0]:
		print("extracted")

	# With progress and limits.
	extractor = LFZip.create_extractor("user://downloads/mod.zip", "user://mods/my_mod/")
	extractor.max_entry_bytes = 16 * 1024 * 1024   # no single file over 16 MiB
	extractor.overwrite = true
	extractor.entry_processed.connect(_on_unzip_progress)
	extractor.finished.connect(_on_unzip_finished)
	extractor.start()


func _on_unzip_progress(percent: float, file: String, _index: int, _total: int) -> void:
	print("%d%% %s" % [percent, file])


func _on_unzip_finished(success: bool, canceled: bool) -> void:
	if not success and not canceled:
		print("refused or failed: ", extractor.failure_reason, " ", extractor.failed_entries)
```

## Notes

- **Refused before writing.** The archive is refused whole — nothing written — when any entry would land outside `path_to_extract` (`../x`, `..\x`, `a/../../x`, or through a symbolic link, a shortcut-like file pointing elsewhere, inside the target), has a name segment Windows cannot create or would silently change (a `:`, a trailing `.` or space, or a device name such as `CON`, `aux.txt`, `COM1`; on every platform, see `LFFile.is_portable_name`), declares more than `max_entry_bytes`, would replace an existing file while `overwrite` is false, would put a file where a directory is (or the reverse) — in the target, or within the archive itself (`f` as a file beside `f/g`; `failed_entries` names the file entry) — or names the same file as another entry (`x.txt` and `/x.txt`; `A.txt` and `a.txt`, compared without case so every disk agrees). A leading `/` is ignored, so `/x` lands at `<target>/x`.
- **Entry names and kinds.** Every entry name is taken as a path inside the target. A name starting with `/` (an absolute path in the archive) is not refused: the `/` is dropped, so `/etc/x` lands at `<target>/etc/x`. A drive name such as `C:/x` is refused (its `:`). Godot's `ZIPReader` does not expose an entry's file attributes, so the extractor cannot tell a symbolic-link entry (what Unix `zip -y` stores) from a file: it is written as an ordinary file whose content is the link's target path (an entry `link` → `/etc` becomes a file `link` holding the text `/etc`), never as a link, so nothing is written through it. An entry that tries to go through that name (`link/x`) needs it as a folder, so the archive is refused (see the first note). Unix permission bits (such as the executable bit) are not restored either; files get default permissions.
- **Sizes are checked before decompressing.** The extractor reads the archive's table of contents (its "central directory"; the large-file zip64 format too) and checks the declared sizes before any entry is decompressed. Directory offsets and sizes, including 64-bit zip64 ones, are checked against the archive's length in a way that cannot overflow, so a directory claimed to lie past the end of the file refuses the archive instead of being read. The directory must end exactly where its end record starts, and a zip64 locator must sit right before the end record and be the only one, and an entry may carry one zip64 size field: otherwise `ZIPReader` could read a different directory or size than the one checked, so the archive is refused (this also refuses a self-extracting archive with data before the zip). Godot's `ZIPReader` reads only the declared number of bytes of an entry. An entry whose content is shorter than declared, or whose bytes fail the CRC check stored in the archive, fails the run (the engine prints its own error for a CRC failure). An entry whose content is longer than declared is cut at the declared size: when the archive's CRC matches those first bytes (a deliberately crafted archive), it is extracted that way without an error.
- **Staging.** Entries are first unpacked into a temporary folder named `<target>.partial-*` beside the target and moved into it only when all were staged. A failed or canceled run removes the staging folder and leaves the target untouched.
- **Undo of a failed move.** With `overwrite` on, a file an entry replaces is first moved to `<target>.partial-*-replaced`. If a move fails midway (e.g. a file locked by another program), the files moved in so far are removed, the replaced files are moved back, the folders the run created are removed (when empty), and `finished(false, false)` follows with `failed_entries` naming the entry and `failure_reason` saying it was undone. If the undo itself fails, `failure_reason` lists what could not be undone and the replaced files stay in the `-replaced` folder. A crash or power loss during the moves is not undone: the target can then hold part of the archive.
- `entry_processed` fires during staging, so it reaches 100% before the entries are moved into the target.
- The worker reports through the game's main loop (once per frame), so the game must keep running for `entry_processed` and `finished` to arrive. Nothing is reported in the frame `start` was called in, so connecting to `finished` right after `start` is always in time.
- Dropping the last reference to a running extractor cancels it and waits for the worker (no `finished`). A run already moving entries into place finishes (or undoes) its moves first.
- **Repeated entries.** A directory listed more than once (Godot's own `ZIPPacker` writes an explicit `dir/` entry twice) is one directory and counts once in `entry_processed`. A *file* listed twice is ambiguous — which copy is meant? — so the archive is refused with a `failure_reason` naming it.
- The extractor logs its start, why an archive was refused (also kept in `failure_reason`), and its finish through `LFLogger.log`, so these lines print only after `LFLogger.enable_print_logs = true`.
