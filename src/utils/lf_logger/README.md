# LFLogger

> Prints messages, warnings and errors that all start with a tag like `[Shop]`, so you can tell where they came from.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_logger.gd` |
| **Tests** | `tests/test_lf_logger.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it instead of bare `print` calls when you want to know which part of the game a line
came from: a logger made with `LFLogger.new(["[Inventory]"])` starts every line with
`[Inventory]`. Ordinary log lines are **off by default** (warnings and errors are on):
turn them on with `LFLogger.enable_print_logs = true`, once, at startup. You can silence
one noisy logger (`enabled = false`), or every log line, warning or error at once with the
static switches (handy in tests or a release build). For a one-off debug print, plain
`print` is fine.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **Other Node**, pick **Node**, and press *Create*.
2. Right-click the new node, choose **Attach Script**, and press *Create* (the default name is fine). The script editor opens.
3. Select everything in the script and replace it with:

```gdscript
extends Node

# Every line from this logger starts with [Shop].
var _log := LFLogger.new(["[Shop]"])


func _ready() -> void:
	LFLogger.enable_print_logs = true  # log lines are off until you turn them on
	_log.log("bought", 3, "potions")  # an ordinary message
	_log.warning("low on gold")       # a yellow warning
	_log.error("unknown item")        # a red error (the game keeps running)
```

4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: pick any name.
5. The **Output** panel shows `[Shop] bought 3 potions`. The warning and the error appear there too, in yellow and red, and in the *Errors* tab of the **Debugger** panel.
6. Change `"[Shop]"` to the name of the part of your game. You can pass any number of values of any type to `log`, `warning` and `error`. To silence a logger, set `_log.enabled = false`.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `enable_print_logs` | `static var enable_print_logs := false` | Whether `log` prints, for every logger in the game (set it on the class: `LFLogger.enable_print_logs = true`). Off by default, which also keeps the library's own info lines (connection lifecycle, process starts) quiet. |
| `enable_print_warnings` | `static var enable_print_warnings := true` | Whether `warning` reports, for every logger in the process. |
| `enable_print_errors` | `static var enable_print_errors := true` | Whether `error` reports, for every logger in the process. |
| `enabled` | `var enabled := true` | This logger alone; `false` silences it whatever the switches say. |
| `_init` | `LFLogger.new(prefix: Array = [])` | A logger starting every message with the parts of `prefix`. The prefix is copied. |
| `set_prefix` | `set_prefix(prefix: Array = []) -> void` | Replaces the prefix (copied). |
| `log` | `log(...messages: Array) -> void` | `print` of the prefix and `messages`, one space between parts, when this logger and `enable_print_logs` are on. |
| `warning` | `warning(...messages: Array) -> void` | `push_warning` of the same, when this logger and `enable_print_warnings` are on. |
| `error` | `error(...messages: Array) -> void` | `push_error` of the same, when this logger and `enable_print_errors` are on. |

`log`, `warning` and `error` take any number of values of any type. With no parts at all
they print the prefix alone (never an error).

## Usage

```gdscript
extends Node

var _log := LFLogger.new(["[Loader]"])


func _ready() -> void:
	LFLogger.enable_print_logs = true  # opt in to log() lines (off by default)
	_log.log("asset", 3, "loaded")  # prints: [Loader] asset 3 loaded
	_log.warning("cache miss")      # a yellow warning in the debugger
	_log.error("file not found")    # a red error in the debugger (the game keeps running)

	_log.enabled = false            # silence just this logger
	_log.log("hidden")
	_log.enabled = true

	LFLogger.enable_print_logs = false  # silence log() on every logger again
	_log.log("hidden too")
```

## Notes

- `enable_print_logs` starts `false`; `enable_print_warnings` and `enable_print_errors` start `true`. Several LF classes (`LFSocket`, `LFProcess`, the zip extractor) write info lines through `LFLogger`, so turning `enable_print_logs` on shows theirs too.
- The three `enable_print_*` switches belong to the class, not to one logger, so changing one affects every logger in the game; tests put them back in `after_each` (a GUT function that runs after every test).
- Message parts are separated by single spaces (no trailing space).
- The method named `log` shadows GDScript's global `log()` math function inside this class.
