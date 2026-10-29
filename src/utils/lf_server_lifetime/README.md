# LFServerLifetime

> Says when a server process should quit: it finished its job, nobody is connected, or the program that started it is gone.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_server_lifetime.gd` |
| **Tests** | `tests/test_lf_server_lifetime.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFOS` (`PidWatchdog`) |

## When to use it

Use it in a server your game starts for itself (a headless match or a helper), so a crashed
or forgotten server does not keep running. It only names the reason; you decide how to quit
and what to log. Its time is the `delta` you pass.

## Step by step

1. Make a scene with one **Node** and attach a script to it (right-click, **Attach Script**, *Create*).
2. Replace the script with:

```gdscript
extends Node

# Quit after 10 s with nobody connected.
var _lifetime := LFServerLifetime.new(10.0, 5.0)

func _process(delta: float) -> void:
	var connected := 0   # replace with your real count of connected clients
	if _lifetime.tick(delta, connected) != LFServerLifetime.Reason.NONE:
		print("quitting")
		set_process(false)
```

3. Press **F6**. After about ten seconds the Output panel shows `quitting`.
4. Call `_lifetime.finish()` when the job is done to also quit 5 seconds later.

## API

| Member | Signature | Description |
|---|---|---|
| `Reason` | `enum { NONE, FINISHED, IDLE, PARENT_GONE }` | What `tick` returns. |
| `idle_seconds` | `var idle_seconds: float` | Seconds with nobody connected before `IDLE`. |
| `finished_seconds` | `var finished_seconds: float` | Seconds after `finish` before `FINISHED`. |
| `parent_pid` | `var parent_pid := 0` | The process to watch; 0 or less watches nothing. Read when the first check starts. |
| `parent_check_seconds` | `var parent_check_seconds: float` | Seconds between checks of the parent. Read when the first check starts. |
| `parent_watch` | `var parent_watch: LFOS.PidWatchdog` | The watcher; null until the first tick that reaches the parent check. |
| `_init` | `LFServerLifetime.new(idle: float, after_finish: float, check_seconds := 2.0)` | Sets the three times. |
| `finish` | `finish() -> void` | Starts (or restarts) the `finished_seconds` countdown. |
| `tick` | `tick(delta: float, connected_count: int) -> Reason` | Advances the clocks and returns the first reason to quit, checked in the order `FINISHED`, `IDLE`, `PARENT_GONE`, else `NONE`. |

## Usage

```gdscript
func _process(delta: float) -> void:
	_lifetime.parent_pid = _launcher_pid
	match _lifetime.tick(delta, _server.connected_peer_ids().size()):
		LFServerLifetime.Reason.FINISHED: _quit("job done")
		LFServerLifetime.Reason.IDLE: _quit("no players")
		LFServerLifetime.Reason.PARENT_GONE: _quit("launcher exited")
```

## Notes

- Where a pid check launches a command (macOS, Windows) the answer arrives on a later tick; see `LFOS.PidWatchdog`.
- Keep calling `tick` until you quit: the parent answer needs a few more ticks.
