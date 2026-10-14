# LFAllianceGroups

> Teams that fight on the same side: set the groups once, then ask whether two members are allies.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_alliance_groups.gd` |
| **Tests** | `tests/test_lf_alliance_groups.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it when several teams can team up (two players against two others) and your combat or
targeting code must ask "are these two on the same side?". It keeps no picture of what a
team is; you pass any id you like.

## Step by step

1. Make a scene with one **Node** and attach a script to it (right-click, **Attach Script**, *Create*).
2. Replace the script with:

```gdscript
extends Node

func _ready() -> void:
	var alliances := LFAllianceGroups.new()
	alliances.configure([["red", "blue"], ["green"]])
	print(alliances.are_allied("red", "blue"))    # true
	print(alliances.are_allied("red", "green"))   # false
	print(alliances.are_allied("pink", "pink"))   # true: a team is on its own side
	print(alliances.are_allied("pink", "teal"))   # false: teams in no group are nobody's ally
```

3. Press **F6**. The Output panel shows `true`, `false`, `true`, `false`.

## API

| Member | Signature | Description |
|---|---|---|
| `configure` | `configure(groups: Array) -> void` | Replaces every group. Each inner array lists members that are allies of each other; a member listed twice keeps the last group. |
| `are_allied` | `are_allied(a: Variant, b: Variant) -> bool` | True for the same member, or two members of one group. |

## Usage

```gdscript
if not alliances.are_allied(unit.team, other.team):
	attack(other)
```

## Notes

- A member named in no group is allied with itself only, even next to another such member.
- `configure` forgets the old groups; call it again when the line-up changes.
