# LFDebounce

> Runs a callback once, a short delay after the last of a burst of calls, with that call's arguments.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_debounce.gd` |
| **Tests** | `tests/test_lf_debounce.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils` (`create_timer`) |

## When to use it

Use it when something is called many times in a row but should only really happen once
things settle: save the settings 300 ms after the player stops dragging a volume slider,
search as the player types but only once they pause, rebuild a layout after a window
resize ends. Every call restarts the wait; only the last call runs. If instead the first
call should run at once and repeats be limited, use `LFThrottle`; for a plain "may this
run now?" gate use `LFCooldown`.

## Step by step

A *debounce* waits for things to go quiet: every new call restarts the wait, and only
the last call actually runs. Here it will run a "search" only after you stop typing.

1. In the editor choose *Scene → New Scene*, then in the Scene dock click *User
   Interface* (a `Control` root).
2. Click *+ Add Child Node*, type `LineEdit`, press *Create*. (A LineEdit is a text box.)
3. Right-click the root node, choose *Attach Script*, keep the defaults, press *Create*,
   and replace the script with:

```gdscript
extends Control

@onready var box: LineEdit = $LineEdit   # the text box from step 2

# Run _search 500 milliseconds after the LAST call to trigger().
# Keep it in a variable like this so it stays alive.
var _search_soon := LFDebounce.new(_search, 500)

func _ready() -> void:
	# `text_changed` is a signal: an event that fires on every keystroke.
	box.text_changed.connect(_on_text_changed)

func _on_text_changed(new_text: String) -> void:
	_search_soon.trigger(new_text)   # restart the wait, remember this text

func _search(text: String) -> void:
	print("Searching for: ", text)
```
4. Press *Ctrl+S* (*Cmd+S* on macOS) and save the scene, then *F6* (*Run Current Scene*).
5. Click into the text box and type `hello` quickly. Look at the *Output* panel: you
   should see a single `Searching for: hello` about half a second after your last key,
   not one line per letter. Type, pause, type again: one line per pause.
6. Change `500` to your own delay in milliseconds. If you ever need to drop a waiting
   call use `_search_soon.cancel()`, or run it right now with `_search_soon.flush()`.

## API

Everything the class offers; you only need the rows used above to get started.

### Constructor / properties

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_DELAY_MS` | `const float = 1000.0 / 60` (ms) | Default `delay_ms`: one 60 fps frame (about 16.7 ms). |
| `_init` | `LFDebounce.new(debounced_callback: Callable, initial_delay_ms: float = DEFAULT_DELAY_MS)` | A debouncer for `debounced_callback`, stored in `callback`; `initial_delay_ms` becomes `delay_ms`. |
| `callback` | `var callback: Callable` | The wrapped callback. |
| `delay_ms` | `var delay_ms: float` | Delay in milliseconds after the latest `trigger()`. A change applies from the next `trigger()`. A NaN is rejected: reported through `LFLogger` as an error, and the value is kept. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `trigger` | `trigger(...args: Array) -> void` | Records these args and restarts the wait: `callback` runs with them `delay_ms` after the latest trigger. |
| `is_pending` | `is_pending() -> bool` | Whether a call is scheduled and has not run. |
| `cancel` | `cancel() -> void` | Drops the pending call. |
| `flush` | `flush() -> void` | Runs the pending call now, once (it won't run again at the end of the delay); no-op if none. |
| `fn` | `static fn(debounced_callback: Callable, initial_delay_ms: float = DEFAULT_DELAY_MS) -> Callable` | Returns a Callable taking any arguments that calls `trigger` on a private debouncer. Use `new()` when you need `cancel`/`flush`. |

## Usage

```gdscript
# settings_menu.gd — on the settings screen
extends Control

@onready var volume_slider: HSlider = $VolumeSlider

# Save 300 ms after the last slider change, not on every pixel of the drag.
var _save_soon := LFDebounce.new(_save_volume, 300)

func _ready() -> void:
	volume_slider.value_changed.connect(_on_volume_changed)

func _on_volume_changed(value: float) -> void:
	_save_soon.trigger(value)          # restarts the 300 ms wait each time

func _save_volume(value: float) -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "volume", value)
	config.save("user://settings.cfg")

func _exit_tree() -> void:
	_save_soon.flush()                 # leaving the menu: save now if a save is waiting
```

The one-line form, when you never need `cancel`/`flush`. These lines go inside a function of a script that has a `run_search(text)` method:

```gdscript
var search_soon := LFDebounce.fn(func(text: String): run_search(text), 250)
search_soon.call("he")
search_soon.call("hello")   # only this one runs, ~250 ms later
```

## Notes

- Default window is one 60 fps frame (~16.7 ms).
- The last call's arguments run once, `delay_ms` after that call.
- The delay is **real time**: it ignores `Engine.time_scale` (slow motion) and keeps counting while the game is paused. `LFThrottle` does the same, so the pair behaves alike.
- It needs a running game (a scene tree) and is accurate to about one frame.
- It only runs the call at the *end* of a burst (the "trailing edge"). To run the *first* call at once, use `LFThrottle`.
- Keep the instance in a variable that outlives the calls (a member, as above): a debouncer nobody references is freed, and its pending call never runs. `fn()`'s Callable keeps its own debouncer alive.
- A callback whose object was freed is skipped when the delay ends (no error). Rapid triggers restart one timer; the last call's arguments are released once it has run or been cancelled.
