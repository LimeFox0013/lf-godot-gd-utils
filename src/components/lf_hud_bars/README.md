# LFTimerIcon, LFStatusEffectIcon, LFValueBar

> Thin HUD bars: an icon that drains as a timer runs down (`LFStatusEffectIcon` drives one from a status effect), and a bar that shows a current value out of a maximum (health, mana, progress) with optional easing.

| | |
|---|---|
| **Files** | `lf_timer_icon.gd`, `lf_value_bar.gd`, `lf_status_effect_icon.gd` |
| **Tests** | `tests/test_lf_timer_icon.gd`, `tests/test_lf_value_bar.gd`, `tests/test_lf_status_effect_icon.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger`, `LFStyle` (`LFValueBar`), `LFStatusEffects` (`LFStatusEffectIcon`) |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFTimerIcon` | Node: add it to a scene (it is a TextureProgressBar) |
| `LFValueBar` | Node: add it to a scene (it is a ProgressBar) |
| `LFStatusEffectIcon` | Node: an `LFTimerIcon` that follows one `LFStatusEffects` effect |

## When to use it

`LFTimerIcon`: a buff or cooldown icon that empties as its time runs out, tracking a `Timer` you already have (a status effect's duration, an ability cooldown). `LFValueBar`: any "current out of maximum" number: a health bar over a unit, a mana bar, a loading bar. Neither knows what the numbers mean, so they work with any health or stat class: you pass numbers, or tell the bar which signal means "changed". For a bar whose look is fully custom, draw your own control.

## Step by step

1. Choose *Scene → New Scene*, then **User Interface**.
2. *+ Add Child Node*, search `LFValueBar`, *Create*. In the Inspector set *Custom Minimum Size* x to `200`, and *Fill Color* to red.
3. Add `LFTimerIcon` the same way; drag any image onto its *Icon* property; set *Custom Minimum Size* to `48, 48` and *Fill Mode* stays as it is.
4. Attach a script to the root and write:

   ```gdscript
   extends Control

   @onready var bar: LFValueBar = $LFValueBar
   @onready var icon: LFTimerIcon = $LFTimerIcon


   func _ready() -> void:
   	bar.ease_seconds = 0.3
   	bar.set_values(75, 100)
   	var timer := Timer.new()     # a clock that counts down
   	add_child(timer)
   	timer.start(5.0)
   	icon.track(timer)
   ```
5. Press **F6**. The bar is three quarters full, the icon drains over five seconds and then stays full (a stopped timer shows `stopped_fraction`, 1 by default; set it to 0 to show an empty icon after the end).

## API

### LFTimerIcon

| Member | Signature | Description |
|---|---|---|
| `icon` | `@export var icon: Texture2D` | Drawn dimmed underneath and bright above, up to the fraction. |
| `under_tint` | `@export var under_tint := Color(0.35, 0.35, 0.35, 0.8)` | Colour multiplied into the dimmed copy. |
| `stopped_fraction` | `@export var stopped_fraction := 1.0` | What a tracked timer that is not running shows. |
| `fraction` | `var fraction: float` | Fraction remaining, 0 to 1. Setting it is `set_fraction`. |
| `set_fraction` | `set_fraction(new_fraction: float) -> void` | Clamps to 0 to 1; a NaN is an error through `LFLogger` and ignored. |
| `track` | `track(new_timer: Timer) -> void` | Follows `time_left / wait_time` every frame; `null` stops. |
| `stop_tracking` | `stop_tracking() -> void` | Stops following; the fraction stays. |
| `timer` | `var timer: Timer` | The tracked timer, or null. |
| `finished` | `signal finished` | The tracked timer stopped or ran out (once per run). Also emitted at once when you start tracking a timer that is not running. |

### LFStatusEffectIcon

Extends `LFTimerIcon` (all its members apply).

| Member | Signature | Description |
|---|---|---|
| `track_effect` | `track_effect(effects: LFStatusEffects, id: StringName) -> void` | Follows effect `id`: a ticking effect shows the time to its next tick, any other finite one its time left out of the length taken now. |
| `refresh` | `refresh() -> void` | Takes the time left now as the full length, for when the effect is refreshed. |

### LFValueBar

| Member | Signature | Description |
|---|---|---|
| `set_values` | `set_values(new_current: float, new_maximum: float) -> void` | Shows current out of maximum. Negatives count as 0; a current above the maximum shows full. NaN is an error and ignored. |
| `ease_seconds` | `@export var ease_seconds := 0.0` | Seconds the fill takes to slide; 0 or less jumps. Eases only inside the scene tree. |
| `fill_color`, `back_color` | `@export var Color` | Colours of the fill and of the background (a flat StyleBox override). |
| `current`, `maximum` | `var float` | The numbers last given (negatives clamped to 0). |
| `ratio` | `ratio() -> float` | `current / maximum` clamped to 0 to 1 (0 for a zero maximum); the target, not the eased fill. |
| `bind` | `bind(source: Object, signal_name: StringName, read: Callable) -> void` | Re-reads when `source` emits `signal_name` (any arguments are ignored): `read()` returns a `Vector2(current, maximum)`. Reads once now. |
| `unbind`, `refresh` | `() -> void` | Stops following; reads the source now. |
| `values_changed` | `signal values_changed(current: float, maximum: float)` | After `set_values`. |
| `DEFAULT_*` | consts | Defaults of the exports and the height (12 px). |

## Usage

```gdscript
# A health bar over a unit that has `hp`, `hp_max` and a `hp_changed` signal.
var bar := LFValueBar.new()
bar.ease_seconds = 0.25
bar.fill_color = Color.GREEN
add_child(bar)
bar.bind(unit, &"hp_changed", func() -> Vector2: return Vector2(unit.hp, unit.hp_max))

# A buff icon that follows the buff's timer.
var icon := LFTimerIcon.new()
icon.icon = load("res://icons/shield.png")
icon.custom_minimum_size = Vector2(32, 32)
add_child(icon)
icon.track(buff_timer)
```

## Notes

- `LFStatusEffectIcon` updates in `_process`; while the effect is not active the fraction stays as it was, and an infinite effect never moves it.
- `LFTimerIcon` updates in `_process` and does nothing while no timer is tracked; it does not create timers of its own. Pause and `Timer.process_mode` follow Godot's rules.
- A tracked timer with `wait_time` 0 shows 0. A one-shot timer that has finished is "stopped" and shows `stopped_fraction`; a timer that was never started is stopped too, so `track` emits `finished` for it on the first update.
- `LFValueBar` has a fixed 12 px height by default (`custom_minimum_size.y`) and no percent text. It is a `ProgressBar`, so theme overrides (`fill`, `background` styleboxes) also work; setting `fill_color` replaces the fill override.
- A source that is freed disconnects itself; `bind` on a freed source or a missing signal is an error and binds nothing.
- Easing is a tween on the bar's `value`; a new `set_values` cancels the running one, and a bar outside the scene tree jumps.
