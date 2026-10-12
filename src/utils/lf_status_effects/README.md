# LFStatusEffects, LFStatusEffectDef, LFStatusStack

> A per-owner container of named, timed status effects (stacking, capping, ticking, expiring), ticked from the owner's own update loop; a frame where nothing is due does a few constant-time checks and no per-stack work.

| | |
|---|---|
| **Files** | `lf_status_effects.gd`, `lf_status_effect_def.gd`, `lf_status_stack.gd` |
| **Tests** | `tests/test_lf_status_effects.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFStatusEffects` | Object: create it with `.new()` |
| `LFStatusEffectDef` | Object: create it with `.new()` |
| `LFStatusStack` | Object: create it with `.new()` |

## When to use it

Use it for anything that is put on a unit for a while and wears off: poison that deals
damage every second, a slow from a frost spell, a 10-second shield, a rage buff that
stacks up to 5 times. Describe each effect once as an `LFStatusEffectDef` (how long it
lasts, how repeat applications stack, what it does per tick), give each unit one
`LFStatusEffects`, apply effects to it and call `tick(delta, self)` from the unit's
`_physics_process`. It replaces a pile of `Timer` nodes or hand-written countdowns, and a
frame where none of a unit's effects is due costs a few checks, not a walk over its stacks. It only tracks effects: your code reads `count()` /
`has()` to change stats (or use `LFLayeredStats` for the stat side). For a single
"can I use this again yet" timer, use `LFCooldown`.

## Step by step

Goal: poison a unit for 3 seconds and watch it take damage once a second. You make a
*definition* (the recipe for "poison"), a *container* (the unit's list of active
effects), apply the effect, and call `tick` every physics frame so time passes for it.

1. Choose *Scene → New Scene*, pick *Other Node*, create a plain `Node`, and save the scene.
2. Right-click it in the Scene dock, choose *Attach Script*, then *Create*.
3. Replace the script with the code below.
4. Press *F6* (run the current scene).
5. Watch the *Output* panel. You should see "poison started", then three "poison tick"
   lines about a second apart, then "poison ended" after 3 seconds.

```gdscript
extends Node

var health := 100.0
# The unit's list of active effects. One per unit.
var effects := LFStatusEffects.new()
# The recipe: name, how repeats combine (INDEPENDENT = each application is its own copy),
# how long it lasts (seconds), the most copies at once, what to do beyond that (DROP =
# ignore the new one), seconds between ticks, and the function to run on each tick.
var poison := LFStatusEffectDef.new(&"poison", LFStatusEffectDef.Accumulation.INDEPENDENT,
	3.0, 5, LFStatusEffectDef.Overflow.DROP, 1.0, _on_poison_tick)


func _ready() -> void:
	# A signal is an event other code can listen to. `changed` fires when an effect
	# starts or ends, with its name.
	effects.changed.connect(_on_changed)
	effects.apply(poison)


func _physics_process(delta: float) -> void:
	# delta = seconds since the last frame. Without this call, time never passes.
	effects.tick(delta, self)


# Runs once per tick. `target` is whatever you passed to tick() (here: this node).
func _on_poison_tick(target: Variant, _stack: LFStatusStack) -> void:
	target.health -= 5.0
	print("poison tick, health ", target.health)


func _on_changed(id: StringName) -> void:
	print(id, " started" if effects.has(id) else " ended")
```

For your game, change the `3.0` (duration, seconds), the `1.0` (seconds between ticks)
and the damage in `_on_poison_tick`. Read `effects.count(&"poison")` or
`effects.has(&"poison")` anywhere to change a unit's stats while the effect is on.

## API

Everything the three classes offer; you only need the rows used above to get started.

### LFStatusEffectDef

| Member | Signature | Description |
|---|---|---|
| `Accumulation` | `enum { INDEPENDENT, SHARED }` | INDEPENDENT: each application is its own stack. SHARED: one stack; reapplying refreshes expiry and raises `count`. |
| `Overflow` | `enum { DROP, REPLACE_OLDEST }` | What an INDEPENDENT application at the cap does: ignored, or the soonest-expiring stack is removed. |
| `id` | `var id: StringName` | The effect's name: its key in the container (e.g. `&'poison'`). |
| `accumulation`, `overflow` | `var accumulation: Accumulation = INDEPENDENT`, `var overflow: Overflow = DROP` | How repeat applications combine; what an INDEPENDENT application at the cap does. |
| `DEFAULT_DURATION`, `DEFAULT_MAX_STACKS`, `DEFAULT_TICK_INTERVAL` | `const DEFAULT_DURATION := 1.0`, `const DEFAULT_MAX_STACKS := 1`, `const DEFAULT_TICK_INTERVAL := 0.0` | Defaults of `duration` (seconds), `max_stacks` and `tick_interval` (seconds; 0 never ticks), also used by `_init` and `shared`. |
| `duration` | `var duration: float = DEFAULT_DURATION` (1.0) | Seconds each application lasts, unless `apply()` overrides it. INF lasts until removed. A NaN is rejected: reported through `LFLogger`, the value is kept. |
| `max_stacks` | `var max_stacks: int = DEFAULT_MAX_STACKS` (1) | Cap (stack count, or SHARED `count`); a cap below 1 counts as 1. A re-application's cap limits how far it raises the count; it never lowers it. |
| `cap_per_source` | `var cap_per_source: bool = false` | INDEPENDENT only: the cap (and REPLACE_OLDEST's eviction) counts only stacks from the applying `source`. |
| `tick_interval` | `var tick_interval: float = DEFAULT_TICK_INTERVAL` (0.0) | Seconds between ticks; `<= 0` or INF never ticks (a NaN is rejected: reported, the value is kept); a positive interval below `LFStatusEffects.MIN_TICK_INTERVAL` is raised to it. |
| `on_tick` | `var on_tick: Callable` | `func(owner: Variant, stack: LFStatusStack) -> void`, called once per elapsed tick of each stack. |
| `interval_fn` | `var interval_fn: Callable` | `func(stack: LFStatusStack) -> float`: chooses the seconds until a stack's next tick, asked when the stack is applied and again at every tick, so an effect can re-roll a random interval each time. A result of 0 or less, INF or NaN ends that stack's ticking; a positive one below `MIN_TICK_INTERVAL` is raised to it. Empty (the default): the fixed `tick_interval` rules. |
| `_init` | `LFStatusEffectDef.new(effect_id: StringName = &'', accumulation_mode: Accumulation = INDEPENDENT, effect_duration: float = DEFAULT_DURATION, stack_cap: int = DEFAULT_MAX_STACKS, overflow_mode: Overflow = DROP, interval: float = DEFAULT_TICK_INTERVAL, tick_callback: Callable = Callable())` (1.0, 1, 0.0) | Sets `id`, `accumulation`, `duration`, `max_stacks`, `overflow`, `tick_interval`, `on_tick` in that order. |
| `shared` | `static shared(effect_id: StringName, accumulation_mode: Accumulation, overflow_mode: Overflow, per_source: bool = false) -> LFStatusEffectDef` | One cached definition per (id, accumulation, overflow, `cap_per_source`), with a 1 s duration, a cap of 1 and no tick, for effects applied ad hoc by name with per-application duration/interval/cap. Shared by every caller: never change its fields. Main thread only. |

### LFStatusStack

| Member | Signature | Description |
|---|---|---|
| `expires_at` | `var expires_at: float` | Absolute time on the container clock. |
| `next_tick_at` | `var next_tick_at: float` | Absolute time of the next tick; `INF` when the stack never ticks. |
| `tick_interval` | `var tick_interval: float` | Effective interval; 0 when the stack never ticks (no positive finite interval, or no callback). |
| `DEFAULT_COUNT` | `const DEFAULT_COUNT := 1` | Default `count`: one copy. |
| `count` | `var count: int = DEFAULT_COUNT` (1) | 1 for INDEPENDENT; refresh count for SHARED. |
| `data` | `var data: Variant` | Caller payload from `apply()`. |
| `on_tick` | `var on_tick: Callable` | Overrides the definition's `on_tick` when valid. |
| `interval_fn` | `var interval_fn: Callable` | When valid, chooses the seconds to each next tick (see the definition's `interval_fn`); `tick_interval` then holds the latest chosen interval (0 once ticking ended). |
| `source` | `var source: Variant` | Who applied it, as passed to `apply()`. |
| `_init` | `LFStatusStack.new(expiry_time: float = 0.0, interval: float = 0.0, first_tick_at: float = INF, payload: Variant = null, tick_callback: Callable = Callable())` | Sets `expires_at`, `tick_interval`, `next_tick_at`, `data`, `on_tick`. Created by the container; you rarely need it. |

### LFStatusEffects

| Member | Signature | Description |
|---|---|---|
| `changed` | `signal changed(id: StringName)` | On apply, refresh, replace, expiry, `remove`, `clear`. Not on a dropped application. |
| `DEFAULT_DURATION`, `DEFAULT_TICK_INTERVAL`, `DEFAULT_MAX_STACKS` | `const DEFAULT_DURATION := -1.0`, `const DEFAULT_TICK_INTERVAL := -1.0`, `const DEFAULT_MAX_STACKS := 0` | Defaults of `apply`'s overrides: "use the governing definition's value". |
| `MIN_TICK_INTERVAL` | `const MIN_TICK_INTERVAL := 0.001` | The shortest tick interval (seconds); a shorter positive one is raised to it, because an interval far below the clock's precision would loop forever. |
| `apply` | `apply(def: LFStatusEffectDef, duration := DEFAULT_DURATION, tick_interval := DEFAULT_TICK_INTERVAL, max_stacks := DEFAULT_MAX_STACKS, on_tick := Callable(), data: Variant = null, source: Variant = null, interval_fn := Callable()) -> int` (-1.0, -1.0, 0) | Applies once; `interval_fn` (`func(stack) -> float`) picks each tick delay instead of a fixed interval (precedence, strongest first: this `interval_fn`, a non-negative `tick_interval` here, the definition's `interval_fn`, the definition's `tick_interval`); see Re-application. Overrides win when given (`duration >= 0`, `tick_interval >= 0`, `max_stacks > 0`), else the governing definition's values; a zero duration expires on the next tick, an INF duration lasts until removed. A NaN duration or tick interval passed here is rejected: reported, nothing applied, 0 returned (a definition rejects its own NaN when it is set). Returns the resulting `count()`. A null `def` is reported and applies nothing (returns 0). |
| `tick` | `tick(delta: float, owner: Variant = null) -> void` | Advances the clock, drops expired stacks, then fires due ticks (catching up, never past expiry, expired stacks' last ones included; a stack or effect removed by a callback fires no more ticks, even when another effect's callback removed it). `owner` is passed to `on_tick`. |
| `has` | `has(id: StringName) -> bool` | Whether the effect is active. |
| `count` | `count(id: StringName) -> int` | Stack count (INDEPENDENT) or refresh count (SHARED); 0 if inactive. |
| `remaining` | `remaining(id: StringName) -> float` | Seconds until the longest-lived stack expires; 0 if inactive. |
| `stacks` | `stacks(id: StringName) -> Array[LFStatusStack]` | Live array, soonest-expiring first. Do not mutate. |
| `ids` | `ids() -> Array[StringName]` | Active effect ids. |
| `is_empty` | `is_empty() -> bool` | Whether no effect is active. |
| `now` | `now() -> float` | Container clock; only advances while something is active. |
| `remove` | `remove(id: StringName) -> void` | Removes every stack of the effect; emits `changed` if it was active. |
| `clear` | `clear() -> void` | Removes everything; safe to call from inside `on_tick` (effects that already expired earlier in that same pass are still announced). |

### Re-application

While an effect is active, the definition it was first applied with **governs** it (accumulation, overflow, defaults, callback); a later definition with the same id only names it. A re-application **never lowers the count**: its cap only limits how far it can raise it.

| Mode | Live count `n`, this application's cap `c` | Result | `changed` | Returns (`count()`) |
|---|---|---|---|---|
| any | not active | new stack | yes | 1 |
| SHARED | `n < c` | count `n + 1`; expiry refreshed; `data` replaced | yes | `n + 1` |
| SHARED | `n >= c` | count stays `n`; expiry refreshed; `data` replaced | yes | `n` |
| INDEPENDENT | `n < c` | new stack | yes | `n + 1` |
| INDEPENDENT + DROP | `n >= c` | ignored | no | `n` |
| INDEPENDENT + REPLACE_OLDEST | `n >= c` | exactly one stack (soonest-expiring) replaced | yes | `n` |

A SHARED refresh never moves the expiry earlier (`max(current, now + duration)`), and keeps the first application's tick interval and callback. With `cap_per_source`, `n` in the cap test counts only stacks from the same `source`, while the return value is still the total `count()`. Sources of different types never match.

## Usage

```gdscript
# A fuller example: enemy.gd, on a CharacterBody3D. A Callable is a function passed
# as a value (here `_on_poison_tick`).
extends CharacterBody3D

# Made once and shared by every enemy: a `static var` belongs to the script, not to each
# enemy. Each hit adds its own 3 s stack (up to 5; a 6th replaces the oldest), and every
# stack ticks once a second. Its callback is a static function, so it holds no enemy:
# the enemy being ticked arrives as `target`, from `effects.tick(delta, self)`.
static var poison := LFStatusEffectDef.new(&'poison', LFStatusEffectDef.Accumulation.INDEPENDENT,
	3.0, 5, LFStatusEffectDef.Overflow.REPLACE_OLDEST, 1.0, _on_poison_tick)

var health := 100.0
# One container per enemy.
var effects := LFStatusEffects.new()


# Called by whatever hits this enemy with a poisoned blade.
func poison_hit(damage_per_tick: float) -> void:
	effects.apply(poison, -1.0, -1.0, 0, Callable(), damage_per_tick)  # data = damage per tick


# Called by a frost spell. Ad hoc, by name: one stack that refreshes, counting up to 3.
func chill(seconds: float) -> void:
	var chill_def := LFStatusEffectDef.shared(&'chill', LFStatusEffectDef.Accumulation.SHARED, LFStatusEffectDef.Overflow.DROP)
	effects.apply(chill_def, seconds, -1.0, 3)


func _physics_process(delta: float) -> void:
	effects.tick(delta, self)  # fires due ticks (with this enemy as `target`), drops expired stacks
	var speed := 5.0 * (1.0 - 0.2 * effects.count(&'chill'))  # derive stats from the state
	velocity = -global_basis.z * speed
	move_and_slide()


# Static: shared by every enemy. `target` is the enemy whose tick() fired it.
static func _on_poison_tick(target: Variant, stack: LFStatusStack) -> void:
	target.take_damage(stack.data)


func take_damage(amount: float) -> void:
	health -= amount
```

The definition and its callback hold no enemy, so one definition serves every enemy in
the game: `tick(delta, owner)` hands each container's owner to the callback. A
definition made per enemy with an instance method (`var poison := ...` with a
non-static `_on_poison_tick`, as in the step-by-step) also works, at one definition per
enemy.

## Notes

- A `tick()` where nothing is due is O(1) (a few checks and an addition; it creates no arrays, dictionaries or objects): stacks store absolute times and the container keeps a lower bound on its next due event; an empty container returns before touching the clock. A `tick()` where something is due walks every active effect id.
- **Random or changing intervals**: give the definition (or `apply`) an `interval_fn` such as `func(_stack): return randf_range(5.0, 15.0)`. It is asked once at `apply` for the first tick and again each time the stack ticks, before the tick callback runs (so inside `on_tick`, `stack.tick_interval` already holds the interval to the next tick). It needs a tick callback, and it replaces the fixed interval: with both a definition `tick_interval` and a definition `interval_fn`, the function wins; an explicit `tick_interval` passed to `apply` beats the definition's function, and an `interval_fn` passed to `apply` beats everything.
- A negative or non-finite `delta` passed to `tick()` is ignored. A large `delta` fires every tick that elapsed, one callback call each (`delta / tick_interval` per stack, up to its expiry): after a long pause, pass smaller steps or `remove()` the effect if that many calls would hitch.
- The container never stores the owner, so an owner can hold its own container without a cycle. Effects never mutate stats; callers derive stats from `count()`/`has()`.
- Callbacks and lifetime: a callback whose object was freed (`is_valid()` false: a method of a freed object, or a lambda that uses a freed object's `self`) is skipped. For an owner that is a RefCounted object (not a Node), a lambda that uses `self` holds a reference to it, so stored in a definition or stack the owner keeps, it keeps the owner from ever being freed; a method (`_on_poison_tick`) or a static function holds no reference. Nodes are not reference-counted, so no callback keeps a Node alive. A static callback that gets the owner through `tick(delta, owner)` avoids both questions.
- A `tick()` drops every expired stack before it fires any tick callback, so callbacks
  never find an expired stack among the active ones: re-applying an effect whose stacks
  all expired in that pass starts it afresh (a SHARED count restarts at 1), a cap counts only live stacks, and
  the expiry is still announced with `changed`. An expired stack still fires its due ticks
  up to its expiry in that pass (unless `remove()` or `clear()` stops it).
- Due-time bounds can be stale-early after a removal; that costs at most one extra pass.
- A SHARED refresh keeps the first application's tick interval, callback and `source`;
  only the expiry, `count` and `data` change.
- Uses only `LFLogger` (to report a null definition or a rejected NaN duration or tick interval).
