# LFGraph

> Layer depths of a prerequisite graph (tech, skill or quest trees) over plain ids and a "parents of" callback, memoised and terminating on cycles.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_graph.gd` |
| **Tests** | `tests/test_lf_graph.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it to lay out a tech tree, skill tree or quest chain in columns: every entry with no
prerequisite goes in tier 0, an entry needing a tier-0 entry in tier 1, and so on (the
"layer depth" is the length of the longest prerequisite chain behind an entry). Your data
stays where it is; you only pass the ids and a function returning each id's
prerequisites. It is not a pathfinder: for shortest paths between points use Godot's
`AStar2D` / `AStar3D` / `AStarGrid2D`.

## Step by step

Goal: print which column ("tier") each skill of a small skill tree belongs in.

1. Open your project and choose *Scene → New Scene*. Pick *Other Node* in the Scene dock
   (top left), search for `Node`, and create it. Save it with *Scene → Save Scene*.
2. Right-click the node in the Scene dock and choose *Attach Script*, then *Create*.
3. Replace the script's contents with the code below.
4. Press *F6* (run the current scene).
5. Look at the *Output* panel at the bottom of the editor. You should see the depth of
   each skill (`slash is in tier 0`, `block is in tier 0`, `riposte is in tier 1`,
   `whirlwind is in tier 1`), then the skills grouped by tier
   (`Tier 0: [&"slash", &"block"]`, `Tier 1: [&"riposte", &"whirlwind"]`).

```gdscript
extends Node

# A Dictionary is a list of "key: value" pairs. Here: each skill, and the skills it needs.
# Change these names and requirements to your own tree.
var skills := {
	&"slash": [],                           # needs nothing -> tier 0
	&"block": [],
	&"riposte": [&"slash", &"block"],       # needs both -> one tier after them
	&"whirlwind": [&"slash"],
}


func _ready() -> void:
	# The second argument is a small function that, given a skill, returns what it needs.
	var depths := LFGraph.layer_depths(skills.keys(), func(id): return skills[id])
	for skill in depths:
		print(skill, " is in tier ", depths[skill])

	# Group the skills by tier: { 0: [slash, block], 1: [riposte, whirlwind] }.
	var tiers := LFUtils.group_by(skills.keys(), func(id): return depths[id])
	for tier in tiers:
		print("Tier ", tier, ": ", tiers[tier])
```

The result is a Dictionary from each skill to its tier number (0 is the first column).
Use it to place buttons: tier 0 in the left column, tier 1 in the next, and so on.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `layer_depths` | `static layer_depths(ids: Array, parents_of: Callable) -> Dictionary` | `{ id: depth }` in the order of `ids`: the length of the longest chain of parents that stays inside `ids` (0 = no parent inside `ids`). `parents_of.call(id)` returns an Array of parent ids, or null for none. |

## Usage

```gdscript
# A script on a skill-tree screen (a Control node): place each skill in a column by its tier.
extends Control

# Each skill lists the skills it requires.
var skills := {
	&'slash': [],
	&'block': [],
	&'riposte': [&'slash', &'block'],
	&'whirlwind': [&'slash'],
	&'blade_storm': [&'whirlwind', &'riposte'],
}


func _ready() -> void:
	var depths := LFGraph.layer_depths(skills.keys(), func(id): return skills[id])
	# depths == { slash: 0, block: 0, riposte: 1, whirlwind: 1, blade_storm: 2 }
	var tiers := LFUtils.group_by(skills.keys(), func(id): return depths[id])
	# tiers == { 0: [slash, block], 1: [riposte, whirlwind], 2: [blade_storm] }
	for tier in tiers:
		print("Tier %d: %s" % [tier, tiers[tier]])
```

## Notes

- Parents outside `ids` are ignored, so passing one branch of a bigger graph gives depths within that branch.
- Each id is visited once and `parents_of` is called once per id, so a dense graph costs about its edge count (no exponential re-walking of shared paths).
- A cycle never hangs: the edge that closes it (a parent still being walked) is ignored. Which edge that is depends on the order of `ids`, so depths on a cyclic graph are well defined but arbitrary; validate the data if cycles are an error.
- The walk is iterative: a chain thousands long can't overflow the call stack.
- A duplicate in `ids` appears once in the result.
