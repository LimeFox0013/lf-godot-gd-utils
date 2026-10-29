# LFHealth

> A health pool: damage lowers it, healing raises it, a maximum bounds it, and signals tell you when something happened.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_health.gd` |
| **Tests** | `tests/test_lf_health.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it for anything with hit points: a player, an enemy, a wall, a shield. It keeps the
number between 0 and the maximum, rejects nonsense amounts, and emits `damaged`, `healed`
and `died` so your health bar and your death effects can listen. It does not know about
armor, resistances or stats: work out the final damage in your own code and pass it in. If
the maximum comes from a stat that can change, call `set_max` when the stat changes. For
a bar, feed `ratio()` or `percent()` to a ProgressBar; for timed effects like poison use
`LFStatusEffects`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	var health := LFHealth.new(100.0)
   	health.damaged.connect(func(amount: float): print("lost ", amount))
   	health.died.connect(func(): print("dead"))

   	health.damage(30.0)    # lost 30
   	health.heal(10.0)
   	print("health: ", health.points, " (", health.percent(), " %)")
   	health.set_max(150.0)  # raising the maximum also gives 50 more points
   	print("health: ", health.points, " of ", health.max_points)
   	health.damage(500.0)   # lost 80, then dead
   ```
4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
5. In the *Output* panel you should see `lost 30`, `health: 80 (80 %)`, `health: 130 of 150`, `lost 130`, `dead`.

## API

Everything the class offers; you only need the rows used above to get started. A *signal* is an event other code can listen to: `object.signal_name.connect(my_function)`.

| Member | Signature | Description |
|---|---|---|
| `new` | `LFHealth.new(initial_max: float = DEFAULT_MAX_POINTS)` | A full pool. A maximum that is not finite or not above 0 is reported through `LFLogger` and `DEFAULT_MAX_POINTS` is used. |
| `DEFAULT_MAX_POINTS`, `PERCENT` | `const DEFAULT_MAX_POINTS := 1.0`, `const PERCENT := 100.0` | The default maximum; the factor `percent()` uses. |
| `damaged` | `signal damaged(amount: float)` | By `damage`, with the amount really removed. |
| `healed` | `signal healed(amount: float)` | By `heal`, with the amount really restored. |
| `died` | `signal died` | Once, when damage takes `points` to 0, after `damaged`. |
| `max_changed` | `signal max_changed(new_max: float)` | By `set_max` when the maximum changed. |
| `points` | `var points: float` | The health now, 0 to `max_points`. Read it; change it through the methods. |
| `max_points` | `var max_points: float` | The maximum. Change it with `set_max`. |
| `damage` | `damage(amount: float) -> float` | Removes `amount` (0 or more; INF empties the pool), returns `points`. NaN or negative: reported and ignored. Nothing happens, and nothing is emitted, for 0 or on a dead pool. |
| `heal` | `heal(amount: float) -> float` | Restores up to `max_points`, returns `points`. NaN or negative: reported and ignored. Nothing happens for 0, a full pool or a dead one. |
| `set_max` | `set_max(new_max: float, grow_current: bool = true) -> bool` | New maximum (finite, above 0; else reported and false). With `grow_current`, a higher maximum adds the difference to `points` (not to a dead pool). A lower maximum clamps `points`. |
| `reset` | `reset() -> void` | Fills the pool and revives a dead one. No signal. |
| `is_dead` | `is_dead() -> bool` | `points` is 0. |
| `is_full` | `is_full() -> bool` | `points` equals `max_points`. |
| `ratio` | `ratio() -> float` | 0.0 to 1.0. |
| `percent` | `percent() -> float` | 0.0 to 100.0. |

## Usage

```gdscript
# A script on an enemy. Armor is the game's business: it is subtracted before the call.
extends Node2D

@export var armor := 2.0
var health := LFHealth.new(50.0)


func _ready() -> void:
	health.died.connect(queue_free)
	health.damaged.connect(_on_damaged)


func take_hit(raw_damage: float) -> void:
	health.damage(maxf(raw_damage - armor, 0.0))


func apply_level_bonus(extra_max: float) -> void:
	health.set_max(health.max_points + extra_max)   # also grows the current health


func _on_damaged(_amount: float) -> void:
	modulate = Color.WHITE.lerp(Color.RED, 1.0 - health.ratio())
```

## Notes

- `points` is clamped: it never drops below 0 or exceeds `max_points`, so there is no overkill value. `damaged` carries what was really removed (`damage(500)` on 130 points emits 130).
- A dead pool ignores `damage` and `heal` until `reset()`, so `died` is emitted at most once between resets. Raising the maximum of a dead pool does not revive it.
- Lowering the maximum below `points` clamps `points` silently (no `damaged`); only `max_changed` is emitted.
- The class holds no stats and never touches the scene tree. To follow a stat, connect the stat's change to `set_max`.
