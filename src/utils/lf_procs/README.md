# LFProc, LFTriggerSet

> Gated reactions (chance, cooldown, condition, charges) registered under trigger keys and fired by key.

| | |
|---|---|
| **Files** | `lf_proc.gd`, `lf_trigger_set.gd` |
| **Tests** | `tests/test_lf_proc.gd`, `tests/test_lf_trigger_set.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFCooldown`, `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFProc` | Object: create it with `.new()` |
| `LFTriggerSet` | Object: create it with `.new()` |

## When to use it

Use it for "when X happens, maybe do Y" effects, often called procs: "on hit, 30 % chance
to ignite, at most once every 2 s", "on kill, heal 5 HP if below half health", "survive one
lethal blow, once per run". Each `LFProc` bundles the action with its gates (chance,
cooldown, condition, charges); an `LFTriggerSet` holds procs under trigger names and your
game code calls `fire(&"on_hit", rng, target)` at that moment. For a single cooldown on
its own use `LFCooldown`; for a single chance roll, `LFRandom.chance`; for game-wide
events many listeners react to, Godot signals or `LFEventBus`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	var rng := LFRandom.new(3)
   	var reactions := LFTriggerSet.new()

   	# "On hit": 50 % chance to run _ignite.
   	reactions.add(&"on_hit", LFProc.new(_ignite).with_chance(0.5))

   	# Pretend the hero hits an enemy six times.
   	for i in 6:
   		var fired := reactions.fire(&"on_hit", rng, "goblin")     # "goblin" is passed on to _ignite
   		print("hit ", i + 1, ": procs that fired = ", fired)


   func _ignite(target: String) -> void:
   	print("  ", target, " is on fire!")
   ```
4. Change `&"on_hit"` (the name of the moment: any name you choose), `_ignite` (the function to run: your own effect goes there), and `0.5` (the chance: 0.5 is 50 %, 1 is always). The text `"goblin"` is the *context*, anything you want to hand to the effect, here the target. In a real game your combat code would call `reactions.fire(...)` at the moment of a hit.
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel you should see six `hit` lines; roughly half of them are preceded by `goblin is on fire!` and show `procs that fired = 1`. With seed `3` it is the same on every run. Add `.with_cooldown(LFCooldown.new(2000))` after `.with_chance(0.5)` to make the effect wait 2 seconds (2000 milliseconds, real time) between fires: the six hits happen instantly, so it then fires at most once.

## API

Everything the class offers; you only need the rows used above to get started. `Variant` in a signature means "any kind of value". A *Callable* is a function passed around as a value (a method name such as `_my_method`, or an inline `func(x): ...`).

### LFProc

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFProc.new(reaction: Callable)` | `reaction(context) -> Variant` becomes `action`. No gates: always fires until configured. |
| `action` | `var action: Callable` | What firing runs; its result only matters to `LFTriggerSet.fire_until_handled`. |
| `UNLIMITED_CHARGES` | `const UNLIMITED_CHARGES := -1` | The `charges_left` value for a proc that never runs out. |
| `charges_left` | `var charges_left := UNLIMITED_CHARGES` (-1) | Fires left; `UNLIMITED_CHARGES` (the default) is unlimited, as is any negative number. |
| `with_chance` | `with_chance(fraction: float) -> LFProc` | Fixed chance, 0–1 (default 1: no roll). |
| `with_chance_getter` | `with_chance_getter(getter: Callable) -> LFProc` | `getter(context) -> float`, read at every check; overrides `with_chance`. |
| `with_condition` | `with_condition(condition: Callable) -> LFProc` | `condition(context) -> bool`. |
| `with_cooldown` | `with_cooldown(cooldown: LFCooldown) -> LFProc` | Must be ready; started when the proc fires. |
| `with_charges` | `with_charges(charges: int) -> LFProc` | Total fires allowed; `with_charges(0)` never fires. |
| `is_spent` | `is_spent() -> bool` | Whether the charges are used up. |
| `check` | `check(rng: RandomNumberGenerator, context: Variant = null) -> bool` | Every gate, then commit (charge, cooldown) without running the action. |
| `fire` | `fire(rng: RandomNumberGenerator, context: Variant = null) -> bool` | `check`, then the action. True when it fired; a proc whose action is not valid (empty, or its object freed) does not fire and spends nothing. |

### LFTriggerSet

| Member | Signature | Description |
|---|---|---|
| `add` | `add(key: Variant, proc: LFProc) -> void` | Registration order is firing order. The same proc twice under a key registers once; a null key or a null proc is an error (nothing stored). |
| `remove` | `remove(key: Variant, proc: LFProc) -> bool` | False if it wasn't there. A key left empty is dropped. |
| `has` | `has(key: Variant) -> bool` | Whether any proc is under `key`. |
| `count` | `count(key: Variant) -> int` | How many procs are under `key`. |
| `procs_for` | `procs_for(key: Variant) -> Array[LFProc]` | A copy, in firing order. |
| `clear` | `clear() -> void` | Unregisters every proc. |
| `fire` | `fire(key: Variant, rng: RandomNumberGenerator, context: Variant = null) -> int` | Every proc under `key`; returns how many fired. |
| `fire_until_handled` | `fire_until_handled(key: Variant, rng: RandomNumberGenerator, context: Variant = null) -> bool` | Stops at the first proc that fires and whose action returns exactly `true` (a truthy non-bool such as `1` does not count). |

## Usage

```gdscript
# A script on a hero.
extends Node

var hp := 100
var freeze_chance := 0.1
var rng := LFRandom.new(42)          # or a run's own seed
var reactions := LFTriggerSet.new()


func _ready() -> void:
	# 30 % to ignite whatever this hero hits, at most once every 2 s.
	reactions.add(&"on_hit", LFProc.new(_ignite)
		.with_chance(0.3)
		.with_cooldown(LFCooldown.new(2000)))

	# Only on living targets, with a chance read from the hero's current stats.
	reactions.add(&"on_hit", LFProc.new(_freeze)
		.with_condition(_is_alive)
		.with_chance_getter(_current_freeze_chance))

	# Survive one lethal blow, once.
	reactions.add(&"lethal", LFProc.new(_survive).with_charges(1))


# Call these from your combat code.
func on_hit(enemy: Node) -> void:
	reactions.fire(&"on_hit", rng, enemy)


func on_lethal_blow() -> bool:
	return reactions.fire_until_handled(&"lethal", rng, self)   # true: the blow was survived


func _ignite(target: Node) -> void:
	print("ignite ", target.name)


func _freeze(target: Node) -> void:
	print("freeze ", target.name)


func _is_alive(target: Node) -> bool:
	return target.is_inside_tree()


func _current_freeze_chance(_target: Node) -> float:
	return freeze_chance


func _survive(_hero: Node) -> bool:
	hp = 1
	return true
```

## Notes

- **Gate order** is fixed: spent → condition → cooldown → chance → commit → action. A gate
  that fails spends nothing after it, so the rolls a seeded generator spends are
  determined by the procs and their order alone. A chance at or above 1 (or at or below
  0, or NaN) spends no roll; any other chance spends exactly one `rng.randf()` (the same
  roll `LFRandom.chance` makes, so results match either way).
- `rng` is any `RandomNumberGenerator`; an `LFRandom` (which extends it) works the same.
- The `context` you pass to `fire` (the target, a hit record...) reaches the condition,
  the chance getter and the action, so all three take exactly one argument.
- `LFCooldown.new(2000)` runs on real time; pass your game clock as its second argument
  (`LFCooldown.new(2000, world.now_ms)`) to follow pausing or time scaling.
- A chance below 1 needs a generator; without one the proc reports an error and fails.
- A proc with a cooldown or charges carries per-owner state. A proc without either can be
  registered on many owners at once.
- Firing a key creates no arrays, dictionaries or objects of its own (your conditions,
  chance getters and actions may, and so does an error report); its cost is one lookup
  plus checking each proc under the key. Adding, removing or clearing procs while a fire is running takes effect from
  the next fire.
- Keys are Dictionary keys: `1` and `1.0` differ, but `"on_hit"` and `&"on_hit"` are the
  same key.
- Use a method as the action (as above). An inline function (a *lambda*) also works, with one trap: when the object whose `self` it uses is RefCounted (not a Node) and holds the procs, the lambda holds that object and the object holds the lambda, a reference cycle, so neither is ever freed. A method holds no reference, and Nodes are not reference-counted, so a Node's lambdas form no cycle.
