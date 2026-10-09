# LFProcess

> Runs another program from your game, shows you what it prints, and can keep it alive.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_process.gd` |
| **Tests** | `tests/test_lf_process.gd` (plus `tests/fixtures/run_without_tree.gd`, a script it runs in a child engine with no `SceneTree`) (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFOS` (executable resolution), `LFUuid` (default uid), `LFLogger` (prefixed logging), `LFText` (lossy UTF-8 lines), `LFUtils` (`tree_root`) |

## When to use it

Use it when your game or tool needs to run another program and react to what it prints:
a helper program, a dedicated game server you launch from the menu, `git` or a
converter in an editor tool. `LFProcess.run()` runs a command once and hands back its
output, with a timeout; it waits with `await`, so the game keeps drawing frames while the
command runs (the launch and the final cleanup happen on the calling thread, see Notes). Instance mode keeps a long-running
helper alive: it streams each output line as a signal (an event other code can listen to),
kills the program when you stop or drop it, and can restart it after a crash, waiting
longer each time.
Godot's `OS.execute()` is enough for a quick command where blocking the game for a moment
is fine. To relaunch this same project headless (without a window), build the arguments with
`LFOS.self_launch_args`.

## Step by step

**Before you start:** this is for desktop games and editor tools. The tests run on Linux
and macOS; on Windows only a few `cmd.exe` tests run (start, output, exit code, stop, refusing `.bat`); restarts, `terminate` and stdin are tested on Linux and macOS only. The
web has no processes to start, and Android and iOS are untested. The
program you run must exist on the player's computer. The example below runs Godot itself
with `--version`, so it works anywhere you can run the editor. A few words you will meet:
*stdout* is the normal text a program prints, *stderr* its error text, and a *pid*
("process id") is the number the system gives each running program.

1. Choose *Scene → New Scene*, click **Other Node** in the Scene dock and pick a plain
   **Node**. Save it (Ctrl+S) as `process_demo.tscn`.
2. Right-click the Node and choose **Attach Script**, then **Create**.
3. Replace the script's contents with this:

```gdscript
extends Node


func _ready() -> void:
	# Run a program once. "await" means: wait here (the game keeps running)
	# until it has finished. The three parts are: the program, its arguments
	# (a list of words you would type after its name), and a time limit in
	# milliseconds (5000 = 5 seconds; 0 waits forever).
	var result: Dictionary = await LFProcess.run(OS.get_executable_path(), ["--version"], 5000)

	# The answer is a Dictionary (named values). "started" is false if the
	# program could not be found or launched.
	if not result.started:
		push_warning("could not start the program")
		return
	print("exit code: ", result.code)         # 0 normally means "all went well"
	print("it printed: ", result.stdout)      # a list with one entry per printed line
	print("timed out: ", result.timed_out)
```

4. Press **F6** (*Run Current Scene*). The Output panel shows `exit code: 0`, the Godot
   version (something like `["4.7.x.stable.official"]`) and `timed out: false`.
5. To run your own tool instead, replace `OS.get_executable_path()` with its name or full
   path (for example `"git"` with `["--version"]`). A bare name is looked up the way a
   terminal does; a path to a file inside your project (`res://`) must be a real file on
   disk, so it only works while you run from the editor.
6. To keep a program running (a server, for instance), create an object instead and listen
   for its lines:

```gdscript
extends Node

var helper := LFProcess.new("my-helper")   # the name appears in log messages


func _ready() -> void:
	helper.output_received.connect(_on_line)
	helper.exited.connect(_on_exit)
	if not helper.start(OS.get_executable_path(), ["--version"]):
		push_warning("could not start the program")


func _on_line(pid: int, line: String) -> void:
	print("[%d] %s" % [pid, line])


func _on_exit(_pid: int, code: int) -> void:
	print("program ended with code ", code)
```

   Press **F6**: you see the version line and then `program ended with code 0`. Call
   `helper.stop()` to kill it early; it is also killed when the object is freed.

## API

Everything the class offers; you only need the rows used in the steps above to get started.

### Constants

| Member | Value | Description |
|---|---|---|
| `STOPPED` | `-1` | The exit code `exited` reports for a process that `stop()`/`terminate()` (or freeing) killed. |
| `DEFAULT_RESTART_BACKOFF_MS` | `1500` | Default for `restart_backoff_ms`, in milliseconds. |
| `DEFAULT_MAX_BACKOFF_MS` | `30000` | Default for `max_backoff_ms`, in milliseconds. |
| `DEFAULT_MAX_LINE_BYTES` | `65536` | Default for `max_line_bytes`, in bytes. |
| `DEFAULT_MAX_PENDING_LINES` | `10000` | Default for `max_pending_lines`. |
| `DEFAULT_TERMINATE_GRACE_MS` | `2000` | Default for `terminate()`'s `grace_ms`, in milliseconds. |

### Signals

| Member | Signature | Description |
|---|---|---|
| `output_received` | `output_received(pid: int, line: String)` | One non-empty stdout line, without its `\n` / `\r\n`. |
| `error_output_received` | `error_output_received(pid: int, line: String)` | One non-empty stderr line. |
| `started` | `started(pid: int)` | Emitted synchronously from `start` / `restart_now` / an auto-restart. |
| `exited` | `exited(pid: int, exit_code: int)` | The process ended: its exit code (a signal number for a signal death on Unix), or `STOPPED` when it was killed. The lines it wrote are delivered before this, unless its pipes stay open more than ~0.5 s after it exits (a grandchild holding them; the 0.5 s starts over while the main thread is still delivering queued lines); lines read after that can follow `exited`. |
| `restarted` | `restarted(pid: int, attempt: int)` | An auto-restart spawned a new process; `attempt` counts restarts since `start()`. |
| `restart_failed` | `restart_failed(attempt: int)` | An auto-restart was due but the command could not be spawned (e.g. the executable was deleted); supervision ends. |

### Properties

| Member | Signature | Description |
|---|---|---|
| `auto_restart` | `var auto_restart: bool = false` | Restart after an exit that `stop()` didn't cause. Read again when a restart is due, so turning it off cancels a pending restart. |
| `max_restart_attempts` | `var max_restart_attempts: int = -1` | `-1` means unlimited. The count is the total since the last `start()`, not consecutive failures. Also re-checked when a restart is due. |
| `restart_backoff_ms` | `var restart_backoff_ms: int = DEFAULT_RESTART_BACKOFF_MS` (1500) | Wait before restart N is `restart_backoff_ms * N` … |
| `max_backoff_ms` | `var max_backoff_ms: int = DEFAULT_MAX_BACKOFF_MS` (30000) | … capped at this. |
| `max_line_bytes` | `var max_line_bytes: int = DEFAULT_MAX_LINE_BYTES` (65536) | A longer line is delivered in pieces of at most this many bytes, cut between UTF-8 characters (a cap below 4 bytes can still cut inside a multi-byte character, whose halves then arrive as U+FFFD). Values below 1 count as 1. |
| `max_pending_lines` | `var max_pending_lines: int = DEFAULT_MAX_PENDING_LINES` (10000) | Lines read but not yet delivered, per process (stdout and stderr together). Past it the reader waits, so a chatty child blocks on its full pipe instead of filling memory. Values below 1 count as 1. |
| `capture_output` | `var capture_output: bool = true` | `false` spawns with `OS.create_process`: the child inherits this process's stdout/stderr, there are no reader threads, no `output_received`/`error_output_received` and no `write_line`. Read at each spawn. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFProcess.new(uid: String = '')` | Optional log id (defaults to a generated `lf-process-…` uuid). |
| `set_uid` | `set_uid(uid: String) -> void` | Changes the log prefix id. |
| `start` | `start(path: String, args: PackedStringArray = [], env: Dictionary = {}) -> bool` | Stops whatever this instance started before (a running child, a pending restart), saves the command (`args` and `env` are copied), resets the restart count and spawns. `false` (nothing spawned, error logged, and `restart_now` has no command to rerun) when `path` doesn't resolve to an executable (`LFOS.resolve_executable`: bare names are searched in `PATH`), on Windows when it is a `.bat`/`.cmd`, or when an `env` key is empty or contains `=`. |
| `stop` | `stop() -> void` | Kills the child (not its own children), cancels a pending restart, joins the worker threads (**blocking** the caller for at most ~0.5 s; see Notes) and drops the pipes. Lines already read but not yet delivered are dropped, so no `output_received` or `error_output_received` arrives after it returns. |
| `terminate` | `terminate(grace_ms: int = DEFAULT_TERMINATE_GRACE_MS) -> void` (2000) | Unix: sends SIGTERM, waits up to `grace_ms` for the child to exit (blocking the caller), then `stop()`s, which waits up to ~0.5 s more for the worker threads. `exited` then reports the child's own code if it exited in time; lines the child printed while shutting down are dropped if not yet delivered, as with `stop()`. Windows: just `stop()`. |
| `write_line` | `write_line(text: String) -> bool` | Writes one line to the child's stdin and flushes. `false` without a running, captured child or when the write fails. |
| `is_running` | `is_running() -> bool` | Whether this instance's child is still running. |
| `get_pid` | `get_pid() -> int` | The child's pid; `-1` before a start, after `stop()`, and once its `exited` has been delivered. |
| `restart_now` | `restart_now() -> bool` | Stops the child, then spawns the saved command again. Keeps the restart count (unlike `start()`). `false` when nothing was started before. |
| `run_shell` | `run_shell(cmd_line: String) -> bool` | `start("cmd.exe", ["/C", cmd])` on Windows, otherwise `start("/bin/sh", ["-c", cmd])` (not a login shell). The shell interprets the whole line, so **never build it from untrusted input**; pass such values as `start()` args instead. |
| `run` | `static run(path: String, args: PackedStringArray = [], timeout_ms: int = 0) -> Dictionary` | Coroutine (`await` it). Runs the command once and returns `{ started, code, timed_out, stdout: PackedStringArray, stderr: PackedStringArray }`. Kills it once `timeout_ms` has passed (`0` or less waits forever); `code` is `STOPPED` when it didn't start or timed out. Needs a running `SceneTree`: without one nothing is spawned and the result is `started: false`. |

## Usage

A script on any node in your scene:

```gdscript
extends Node

var server := LFProcess.new("ai-server")   # the id shown in its log lines


func _ready() -> void:
	# Run a command once and read its output (gives up after 5 s).
	var result: Dictionary = await LFProcess.run("git", ["rev-parse", "HEAD"], 5000)
	if result.started and result.code == 0:
		print("commit: ", result.stdout[0])

	# Keep a helper program running, restarting it up to 3 times if it crashes.
	server.auto_restart = true
	server.max_restart_attempts = 3
	server.output_received.connect(_on_server_output)
	server.exited.connect(_on_server_exited)
	if not server.start("my-server", ["--port", "8080"]):
		push_warning("my-server is not installed")


func _on_server_output(pid: int, line: String) -> void:
	print("[%d] %s" % [pid, line])


func _on_server_exited(_pid: int, code: int) -> void:
	print("server exited with code ", code)


func _exit_tree() -> void:
	server.terminate(1000)   # ask it to quit, kill it after 1 s
```

## Notes

- With `capture_output` on, three background threads (parallel lines of work) run per child: a stdout reader, a stderr reader and an exit monitor (one thread with it off). The monitor polls every 50 ms.
- Every signal except `started`, `restarted` and `restart_failed` is delivered "deferred" (queued with `call_deferred` from a worker thread), so listeners run on the main thread (the one running your game) when it next runs its deferred calls, at the end of a frame, never inside a worker.
- **What blocks the calling thread:** each spawn (`start`, `restart_now`, `run_shell`, an auto-restart, `run`) checks the executable on disk and launches the program synchronously; `stop()`, `restart_now()`, a respawn and freeing wait up to ~0.5 s for the worker threads; `terminate(grace_ms)` waits up to `grace_ms` more. `run()` awaits frames while the command runs, then calls `stop()`.
- One instance has at most one child at a time. `start()`, `restart_now()` and `stop()` end the previous child and supersede a restart that was waiting out its backoff.
- The object only ever kills a program while it knows it is still its own running child, so a pid that the system has handed to some other program is never touched.
- The worker threads never hold the instance, so dropping it without `stop()` frees it. Freeing kills the child and joins the threads like `stop()` does.
- **A short, bounded wait:** `stop()`, a restart and freeing wait at most ~0.5 s for the worker threads to finish. A reader still stuck after that — because a grandchild (a program started by the program you started, e.g. `sleep 30 &` under `run_shell`) holds the output pipe open — is set aside instead of waited for: it is parked in a static list and joined by a later call once the grandchild exits and the pipe closes. A detached reader delivers nothing more. If the application quits first, Godot warns that a Thread was destroyed unjoined.
- `stop()` kills only the child (Godot's `OS.kill`: an immediate, unconditional kill on every system). Grandchildren — e.g. processes started from `run_shell`'s shell — keep running until they exit on their own.
- If this Godot process is killed hard (e.g. `kill -9`), the child keeps running: the OS gives no "die with parent" for it. Pass the child this process's id and have it watch it with `LFOS.PidWatchdog`.
- **stdin can't be closed on its own.** Godot's pipe gives stdin and stdout one handle, so closing it would cut stdout too. A child that reads stdin to EOF (`wc`, `cat > file`) only ends when stopped; pass input as arguments or a file instead.
- Output is read as UTF-8 text; bytes that aren't valid text become the replacement character (U+FFFD, a small question-mark symbol) instead of causing errors. Empty lines are not delivered.
- `env` is set only around the spawn and the previous values are restored right after, so the Godot process's own environment is unchanged afterwards. While the spawn runs it is process-wide (Godot has no per-spawn environment): a process another thread spawns at that moment inherits it too.
- The executable is resolved again before every spawn, so an auto-restart of a command that was deleted reports `restart_failed` instead of spawning a failing child.
- **Windows:** arguments are joined into one command line, and an argument containing `"` or ending in `\` isn't escaped the way `CommandLineToArgvW` expects, so it can split into extra arguments; don't pass untrusted arguments there. `.bat`/`.cmd` files run through `cmd.exe` with its own metacharacter parsing, so `start()` refuses them; use `run_shell` knowingly.
