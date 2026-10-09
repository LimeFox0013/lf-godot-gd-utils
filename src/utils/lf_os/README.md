# LFOS

> Small helpers for the computer your game runs on: find a program, check whether another program is still running, relaunch your own game as a server, and list network addresses.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_os.gd` |
| **Tests** | `tests/test_lf_os.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFFile` (`to_absolute`), `LFUrl` (`is_private_ipv4`), `LFJson` and `LFText` (quiet decoding in `decode_arg_value`), `LFThread` (`PidWatchdog`'s off-main-thread check) |

## When to use it

Use it for the plumbing around launching programs and multiplayer hosting. Typical cases:
a "Host game" button that starts a headless copy of your own project (a copy that runs
without a window) as the server (`self_launch_args` + `encode_arg_value`), that server
quitting by itself when the game that launched it closes (`PidWatchdog`), showing the
player the LAN address friends should join (`local_addresses` + `is_private_ipv4`), or
checking that a tool such as `ffmpeg` is installed before you call it
(`resolve_executable`).
For the OS name and CPU architecture use the engine directly: `OS.get_name()` and
`Engine.get_architecture_name()`. To run and watch the program itself, use `LFProcess`.

## Step by step

**Before you start:** written for desktop (Windows, macOS, Linux); the tests run on Linux
and macOS, so the Windows-only paths (`tasklist`, `PATHEXT`) are not covered by tests. On
the web and iOS a game can't look at other programs, so `is_pid_alive` (which answers only for this
process's own id there) and `resolve_executable` are not useful there; on Android `is_pid_alive`
reads `/proc` like Linux, and what that shows of other apps is not verified. A *pid* ("process id") is the number the system gives each running program.
Paths starting with `res://` (your project folder) are turned into real disk paths first,
but note that inside an exported game `res://` is packed into the game file, so a program
you want to run must live in a normal folder (or in `user://`, the game's data folder,
which an exported game can write to, unlike `res://`; **Project → Open User Data Folder**
shows where that is on your system).

1. Choose *Scene → New Scene*, click **Other Node** in the Scene dock and pick a plain
   **Node**. Save it (Ctrl+S) as `os_demo.tscn`.
2. Right-click the Node and choose **Attach Script**, then **Create**.
3. Replace the script's contents with this:

```gdscript
extends Node


func _ready() -> void:
	# Where is a program? A bare name is searched in the same places a terminal
	# searches. You get "" when it isn't installed.
	var git := LFOS.resolve_executable("git")
	print("git is at: ", git if git != "" else "not installed")

	# Which network addresses does this computer have? Keep only private ones
	# (192.168.x.x and the like): on a home or office network, friends join through one.
	var addresses := LFOS.local_addresses(false, true)   # (include link-local, IPv4 only)
	var lan := addresses.filter(func(a: String) -> bool: return LFOS.is_private_ipv4(a))
	print("friends on your network can join one of: ", lan)

	# Is some other program still running? (This game's own id is always "alive".)
	print("this game is running: ", LFOS.is_pid_alive(OS.get_process_id()))

	# Pass a setting to another copy of your game through the command line.
	# encode_arg_value turns a value JSON can hold into one word; decode_arg_value turns
	# it back (numbers come back as decimals).
	var word := LFOS.encode_arg_value({"map": "valley"})
	print("as a command-line word: ", word)
	print("back again: ", LFOS.decode_arg_value(word))

	# Read "--key=value" and "--flag" words, as in `game --server --port=7000`.
	print(LFOS.parse_user_args(PackedStringArray(["--server", "--port=7000"])))
```

4. Press **F6** (*Run Current Scene*). The Output panel shows (your values will differ):
   `git is at: /usr/bin/git`, a list such as `["192.168.1.20"]`, `this game is running: true`,
   `as a command-line word: eyJtYXAiOiJ2YWxsZXkifQ==`, `back again: { "map": "valley" }` and
   `{ "server": true, "port": "7000" }`.
5. For your own game, replace `"git"` with the tool you need (`"ffmpeg"`, ...) and the
   dictionary with the settings your server needs. The full "Host game" setup, with a
   server that quits when the game that launched it is gone, is under Usage below.

## API

Everything the class offers; you only need the rows used in the steps above to get started.

### Constants

| Member | Value |
|---|---|
| `BACKEND_METAL` | `'metal'` |
| `BACKEND_CUDA` | `'cuda'` |
| `BACKEND_VULKAN` | `'vulkan'` |
| `BACKEND_CPU` | `'cpu'` |

### Methods

| Member | Signature | Description |
|---|---|---|
| `select_backend` | `static select_backend(os_name: String = OS.get_name().to_lower(), rendering_driver := '', gpu_vendor: String = get_gpu_vendor()) -> String` | Picks which build of a native helper program to launch (Metal, CUDA, Vulkan or CPU). `macos` → `BACKEND_METAL`. `windows`/`linux` with a GPU vendor containing "nvidia" → `BACKEND_CUDA`. Otherwise `BACKEND_VULKAN` when the rendering driver is Vulkan, else `BACKEND_CPU`. `rendering_driver = ''` means `RenderingServer.get_current_rendering_driver_name()`, while `gpu_vendor = ''` means "no GPU". Pass the arguments to decide for a machine other than the running one (or in tests). |
| `get_gpu_vendor` | `static get_gpu_vendor() -> String` | Lower-cased `RenderingServer.get_video_adapter_vendor()`; `''` when there is none. |
| `is_pid_alive` | `static is_pid_alive(pid: int) -> bool` | Whether a process with this id exists — any process, not only a child (`OS.is_process_running()` answers only for children, and reports an error for any other pid). Linux: `/proc/<pid>`. Other Unix: `kill -0` (a process of another user counts as alive). Windows: `tasklist` (when it cannot run, every other pid reads as gone). Where `/proc` exists (Linux, and Android, since the `/proc` check comes first in the code) it reads `/proc/<pid>`; which other processes `/proc` shows on Android is not verified. Web/iOS: only this process's own id. `pid <= 0` → `false`. **Blocks** the calling thread while `kill`/`tasklist` runs (see `pid_check_runs_command`). |
| `pid_check_runs_command` | `static pid_check_runs_command() -> bool` | Whether `is_pid_alive` for another process launches a command (macOS and other Unix without `/proc`, Windows) and so blocks until it exits. `false` on Linux and on web/Android/iOS. |
| `self_launch_args` | `static self_launch_args(user_args: PackedStringArray = [], headless := true) -> PackedStringArray` | Arguments that run this same project again: `--headless` (when `headless`), `--path <project>` when running from the editor (whose executable is Godot itself), then `--` and `user_args` (read back with `OS.get_cmdline_user_args()`). Pair with `OS.get_executable_path()`. |
| `parse_user_args` | `static parse_user_args(args: PackedStringArray) -> Dictionary` | `--key=value` → `{key: 'value'}` (the value is everything after the first `=`) and `--flag` → `{flag: true}`. Arguments not starting with `--`, and a bare `--`, are skipped; a repeated key keeps its last value. Pair with `OS.get_cmdline_user_args()`. |
| `encode_arg_value` | `static encode_arg_value(value: Variant) -> String` | `value`'s JSON, base64-encoded: one word of letters, digits, `+`, `/` and `=` (none special to a POSIX shell), which argv carries unchanged whatever text or structure it holds. |
| `decode_arg_value` | `static decode_arg_value(text: String) -> Variant` | The value `encode_arg_value` wrote, or `null` when `text` is not base64 of JSON. Quiet: no engine error on bad input. Numbers come back as floats. |
| `local_addresses` | `static local_addresses(include_link_local := false, ipv4_only := false) -> Array[String]` | This machine's IP addresses (`IP.get_local_addresses()`), sorted. Link-local ones (`fe80::/10`, `169.254.0.0/16`) are left out unless `include_link_local`; `ipv4_only` drops IPv6. |
| `is_private_ipv4` | `static is_private_ipv4(address: String, include_shared_range := true) -> bool` | An IPv4 address in 10/8, 172.16/12 or 192.168/16 (RFC 1918), plus the 100.64/10 shared range (RFC 6598: carrier-grade NAT, overlay or mesh VPNs) unless `include_shared_range` is false. The address is read as `LFUrl.classify_host` reads a host: legacy numeric forms (`2130706433`, `0x0a.1`, `10.1`) and an IPv4-mapped IPv6 address (`::ffff:10.0.0.1`) count as the IPv4 address they carry. Loopback, link-local, public, host-name and other IPv6 addresses are `false`. A private address is not proof another machine can reach it (firewalls, VPNs, carrier-grade NAT). |
| `resolve_executable` | `static resolve_executable(path: String) -> String` | The file a launch of `path` would run, or `''`. A bare name is searched in `PATH`; a path with a separator is checked as given (relative to the working directory). Unix requires an execute bit. Windows tries each `PATHEXT` extension on a name without one. A macOS `X.app` resolves to `X.app/Contents/MacOS/<CFBundleExecutable>` (XML `Info.plist`; else the binary named after the bundle). `res://`/`user://` are globalized first (`LFFile.to_absolute`). |

### `LFOS.PidWatchdog` (RefCounted)

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_CHECK_INTERVAL_SECONDS` | `const DEFAULT_CHECK_INTERVAL_SECONDS := 2.0` | Default for `interval_seconds`, in seconds. |
| `_init` | `new(watched_pid: int, interval_seconds: float = DEFAULT_CHECK_INTERVAL_SECONDS)` (2.0) | Watches `watched_pid`, checking every `interval_seconds` seconds; `0` or less watches nothing. |
| `pid` | `var pid: int` | The watched id. |
| `check_interval_seconds` | `var check_interval_seconds: float` | Seconds between checks. A NaN is rejected: reported through `LFLogger` as an error, and the value is kept. |
| `tick` | `tick(delta: float) -> bool` | Advances by `delta`; once per interval asks `is_pid_alive`. `true` once the process is gone, and on every call after. Where `pid_check_runs_command()` is true, the check runs on an `LFThread`: the tick that starts it returns `false` and a later tick reports the answer (the next interval counts from then). A result for a `pid` that was changed meanwhile is dropped. |
| `is_checking` | `is_checking() -> bool` | Whether a check started by `tick` is waiting to be collected: on a worker thread, or, without thread support (or with `LFThread.force_main_thread`), waiting to run, blocking, in the next tick. |
| `is_gone` | `is_gone() -> bool` | Whether a check has found it gone. |

## Usage

Launch a headless copy of this project that quits once this process is gone. In the
parent (e.g. a script on the menu scene):

```gdscript
extends Node

var server := LFProcess.new()


func host_game() -> void:
	var settings := {"map": "valley", "players": ["ann", "bo"]}
	var args := LFOS.self_launch_args([
		'--server',
		'--parent-pid=%d' % OS.get_process_id(),
		'--settings=' + LFOS.encode_arg_value(settings),
	])
	server.start(OS.get_executable_path(), args)
```

In the launched copy (a script on its main scene):

```gdscript
extends Node

var watchdog: LFOS.PidWatchdog
var settings: Variant

func _ready() -> void:
	var args := LFOS.parse_user_args(OS.get_cmdline_user_args())
	if !args.has('server'):
		return
	settings = LFOS.decode_arg_value(str(args.get('settings', '')))
	watchdog = LFOS.PidWatchdog.new(int(args.get('parent-pid', '0')))

func _process(delta: float) -> void:
	if watchdog != null and watchdog.tick(delta):
		get_tree().quit()
```

Tell another player on the LAN where to connect, and pick which build of a native helper
program to launch on this machine (inside any function):

```gdscript
var shareable := LFOS.local_addresses(false, true).filter(func(a): return LFOS.is_private_ipv4(a))

var binary := "tool-%s-%s" % [Engine.get_architecture_name(), LFOS.select_backend()]
var path := LFOS.resolve_executable(binary)
if path.is_empty():
	push_warning("no %s on PATH" % binary)
```

## Notes

- `select_backend` is a simple naming rule, not a check of what the computer can really do: it returns `metal` on any macOS (even when Godot renders through OpenGL) and `cuda` from the vendor string alone, without probing for a CUDA runtime.
- `'vulkan'` means Godot itself renders through Vulkan; a GPU that supports Vulkan while Godot uses D3D12 or OpenGL gives `'cpu'`.
- Under `--headless` the GPU vendor is empty, but the driver name still reflects the configured renderer (e.g. `metal` on macOS), so the result there follows the OS and driver, not the hardware.
- `is_pid_alive` launches `kill -0` (macOS, other Unix without `/proc`) or `tasklist` (Windows, the slowest of these) per call and waits for it, freezing the calling thread meanwhile; on Linux it only reads `/proc`. Don't call it every frame on the main thread. `PidWatchdog` runs that command on an `LFThread`, so its `tick` doesn't wait; on a build without thread support `LFThread` runs it inside a later `tick`, which then does block. On Unix systems without `/proc` (macOS, the BSDs) it needs a `kill` binary on `PATH`; where there is none, every other process reads as gone, so a `PidWatchdog` would fire at once. The same holds on Windows when `tasklist` cannot be run. A program that has ended but has not yet been cleaned up by the system (a "zombie") still counts as alive; for your own children prefer `LFProcess.is_running()`.
- `resolve_executable` checks that the file exists and is allowed to run (the "execute permission" on macOS/Linux), not what is inside it: a file that is executable but not a valid binary or script still resolves.
