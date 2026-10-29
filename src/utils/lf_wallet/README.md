# LFWallet

> A balance you can add to, check a price against and spend, that tells you when it changes.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_wallet.gd` |
| **Tests** | `tests/test_lf_wallet.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it for any amount the player earns and spends (gold, energy, tokens) when a shop or a
label needs to react to every change. It keeps one number; what it is called is up to you.

## Step by step

1. Make a scene with one **Node** and attach a script to it (right-click, **Attach Script**, *Create*).
2. Replace the script with:

```gdscript
extends Node

func _ready() -> void:
	var gold := LFWallet.new(10.0)
	gold.changed.connect(func(amount): print("gold is now ", amount))
	gold.add(5.0)
	print(gold.spend(20.0))   # false: not enough
	print(gold.spend(8.0))    # true
```

3. Press **F6**. The Output panel shows `gold is now 15.0`, `false`, then `gold is now 7.0` and `true`.

## API

| Member | Signature | Description |
|---|---|---|
| `changed` | `signal changed(amount: float)` | The balance changed; carries the new amount. |
| `amount` | `var amount: float` | The current balance. |
| `_init` | `LFWallet.new(starting_amount := 0.0)` | Sets the starting balance. |
| `add` | `add(delta: float) -> void` | Adds `delta` and announces it. Not clamped. |
| `can_afford` | `can_afford(cost: float) -> bool` | Whether the balance covers `cost`. |
| `spend` | `spend(cost: float) -> bool` | Takes `cost` and announces it; false and silent when the balance falls short. |

## Usage

```gdscript
if shop_wallet.spend(item_price):
	give_item()
```

## Notes

- `add` always announces, even for 0, and a negative `add` can take the balance below zero; use `spend` for a limit.
- Setting `amount` directly does not announce anything.
