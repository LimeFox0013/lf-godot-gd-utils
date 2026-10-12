# LFHurtBox2D and LFHitBox2D

> A pair of `Area2D` nodes for melee, projectiles and hazards: the hit box deals, the hurt box receives, and the hurt box's invulnerability gate keeps one overlap from hurting every frame.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add them to a scene |
| **Files** | `lf_hurt_box_2d.gd`, `lf_hit_box_2d.gd` |
| **Tests** | `tests/test_lf_hit_boxes.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

**Classes:**

| Class | How you use it |
|---|---|
| `LFHurtBox2D` | Node: add it under a creature, with collision shapes as children |
| `LFHitBox2D` | Node: add it under an attack (a sword, a bullet, a fire patch), with collision shapes as children |

## When to use it

Use it when "this shape touches that shape" must turn into "that creature takes damage", with
a short immunity afterwards so a body standing in a fire is hurt at a steady rhythm rather
than once per physics frame. The hurt box reports `hit_received(hit_box)`; what the hit
means (damage, knockback) is yours: put it in the hit box's `payload` and `source`, and in
the hurt box's `source`. The library never reads those, so any creature or attack type works.

A bare `Area2D` with `area_entered` is enough if one touch is one hit and nothing repeats.
Use these when a hit box can stay overlapped, when one swing must hit each target once
(`ONCE`), or when an overlap that began during the immunity must still count once it ends.

## Step by step

Goal: a damage patch on the floor that hurts a player standing in it twice per second.

1. Make a scene with a `CharacterBody2D` named `Player`. Give it a `CollisionShape2D` child (any shape).
2. Add a child to `Player`: *+ Add Child Node*, search "LFHurtBox2D", *Create*. Give the hurt box a `CollisionShape2D` child with a shape (*Shape* in the Inspector: New RectangleShape2D). In the Inspector set *Invulnerability Seconds* to `0.5`.
3. In another scene (or as a child of the level) add an `LFHitBox2D` with a `CollisionShape2D` child covering the patch.
4. Attach a script to `Player`:

   ```gdscript
   extends CharacterBody2D

   func _ready() -> void:
   	# A signal is an event; run our function whenever a hit is accepted.
   	$LFHurtBox2D.hit_received.connect(_on_hit_received)

   func _on_hit_received(hit_box: LFHitBox2D) -> void:
   	print("ouch, damage ", hit_box.payload)
   ```
5. Attach a script to the hit box that sets `payload = 3` in `_ready`. Press *F6* and walk the player into the patch.

You should see `ouch, damage 3` printed once when you enter, and again every half second
while you stay inside.

## API

### Constants

| Member | Signature | Description |
|---|---|---|
| `LFHurtBox2D.DEFAULT_INVULNERABILITY_SECONDS` | `const float = 0.05` (seconds) | Default `invulnerability_seconds`. |

### LFHurtBox2D

| Member | Signature | Description |
|---|---|---|
| `hit_received` | signal `hit_received(hit_box: LFHitBox2D)` | A hit was accepted. Read `hit_box.payload` / `hit_box.source`. |
| `gate_opened` | signal `gate_opened()` | The invulnerability gate opened again (emitted before an overlapping box is re-applied). |
| `invulnerability_seconds` | `float = 0.05` (seconds) | Seconds after an accepted hit during which hits are ignored; `<= 0` means no gate. A NaN is rejected through `LFLogger`; the value is kept. |
| `disabled` | `bool = false` | While true no hits are taken and overlaps are forgotten. Writing it is `set_disabled`. |
| `source` | `Variant = null` | Your data for this hurt box (its creature, for example); never read by the library. |
| `set_disabled` | `set_disabled(state: bool) -> void` | Enabling opens the gate; disabling forgets overlaps. Monitoring changes are deferred, safe inside collision callbacks. |
| `reset` | `reset() -> void` | Disables the hurt box and opens the gate. |
| `try_hit` | `try_hit(hit_box: LFHitBox2D) -> bool` | Takes a hit as if `hit_box` just started overlapping. False when disabled, gate closed, or the hit box refuses. Use it for hits without a shape. |
| `tick` | `tick(delta: float) -> void` | Advances the gate. The node calls it every physics frame while the gate is closed; call it yourself to drive time in tests or simulations. When the gate opens, the most recent still-overlapping usable hit box is applied. |
| `gate_time_left` / `is_gate_closed` | `() -> float` / `() -> bool` | Seconds until the gate opens (0 when open) / whether it is closed. |

### LFHitBox2D

| Member | Signature | Description |
|---|---|---|
| `Behaviour` | `enum { REPEATED, ONCE }` | `ONCE`: hits each hurt box at most once until `clear_hit_targets()`. `REPEATED`: hits whenever the gate allows. |
| `hit_landed` | signal `hit_landed(hurt_box: LFHurtBox2D)` | This hit box landed on a hurt box. |
| `behaviour` | `Behaviour = REPEATED` | The behaviour above. |
| `disabled` | `bool = false` | While true it deals nothing and is not detectable. Writing it is `set_disabled`. |
| `payload`, `source` | `Variant = null` | Your attack data and attacker; never read by the library. |
| `can_hit` | `can_hit(hurt_box: LFHurtBox2D) -> bool` | Enabled, and for `ONCE` not already landed on `hurt_box`. No side effects. |
| `has_hit` | `has_hit(hurt_box: LFHurtBox2D) -> bool` | Whether it has landed on `hurt_box` (kept for `ONCE`). |
| `clear_hit_targets` | `clear_hit_targets() -> void` | Forgets landed-on targets; call when a new swing starts. |
| `set_disabled` | `set_disabled(state: bool) -> void` | Setter of `disabled`; the monitorable change is deferred. |

## Usage

```gdscript
# A sword swing: hits every enemy once, then is re-armed for the next swing.
func start_swing() -> void:
	$Sword.clear_hit_targets()
	$Sword.payload = {"damage": 12}
	$Sword.disabled = false

func end_swing() -> void:
	$Sword.disabled = true
```

## Notes

- Hit boxes are detected through `area_entered` on the hurt box, so the hit box's collision layer must be in the hurt box's collision mask. Set the layers/masks in the Inspector.
- A hit box that is still overlapping when the gate opens is applied then (the most recently entered usable one wins); a hit box that left, was freed, or is disabled is skipped.
- With `invulnerability_seconds <= 0` there is no gate, and a continuous overlap is one hit (at entry); nothing re-applies it.
- `ONCE` is spent only by an accepted hit: a box refused during the gate can still land when the gate opens. The record is per hit box and keyed by hurt-box instance id; `clear_hit_targets()` empties it.
- The gate is a counter driven by `tick(delta)`; it uses no `Timer` and runs on physics frames only while closed.
- Enabling a hurt box opens its gate; disabling it forgets which hit boxes overlapped, so ones already inside when it is re-enabled do not hit until they re-enter or you call `try_hit`.
- `Area2D.monitoring` / `monitorable` changes are deferred to a safe point, so they take effect at the end of the frame.
