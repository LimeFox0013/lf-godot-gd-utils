# LFSlotInventory

> Keeps track of items in numbered slots, grouped in sections like a hotbar and a backpack.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_slot_inventory.gd` |
| **Tests** | `tests/test_lf_slot_inventory.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it for a slot-based inventory: a 5-slot hotbar plus a 20-slot backpack, or an equipment
row plus a stash. Every slot holds one item or is empty, and items keep their slot, so the
icons in your UI don't jump around when something is removed. A picked-up item goes to the
first free slot (hotbar first, then backpack, in the order you choose), `move` sends it to
another section, and `grow` adds slots after a bag upgrade. It only keeps track of where
things are; stacking, item types and what a slot accepts are up to your code. For a plain
list of items with no slots, an `Array` is enough.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **Other Node**, pick **Node**, and press *Create*.
2. Right-click the new node, choose **Attach Script**, and press *Create* (the default name is fine). The script editor opens.
3. Select everything in the script and replace it with:

```gdscript
extends Node

# Two sections: "hotbar" with 2 slots, "backpack" with 4 slots.
var inventory := LFSlotInventory.new({"hotbar": 2, "backpack": 4})


func _ready() -> void:
	# Stand-ins for your own items. Any object that is not shared will do.
	var sword := Resource.new()
	var potion := Resource.new()
	var shield := Resource.new()

	# add() uses the first free slot, hotbar first.
	inventory.add(sword)
	inventory.add(potion)
	inventory.add(shield)  # the hotbar is full, so this goes to the backpack

	print(inventory.section_of(shield))  # backpack
	print(inventory.index_of(potion))    # 1

	inventory.remove(sword)
	print(inventory.item_at("hotbar", 0))   # the slot is empty now (null)
	print(inventory.index_of(potion))       # the potion did not move: still 1
```

4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: pick any name.
5. The **Output** panel shows `backpack`, `1`, `<null>` and `1` again: removing the sword left an empty gap instead of shifting the potion.
6. Change the section names and sizes in the first line (slot counts, not pixels). Replace the `Resource.new()` stand-ins with your own item objects.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFSlotInventory.new(sizes: Dictionary = {}, add_order: Array = [])` | `sizes` is `{section: slot_count}` in declaration order. `add` fills sections in `add_order` (empty: every section, in declaration order). |
| `changed` | `signal changed` | A signal (an event other code can listen to; see Usage). Emitted after every add, remove, move and grow that changed something. |
| `sections` | `sections() -> Array` | The section keys, in declaration order (a copy). |
| `slot_count` | `slot_count(section: Variant) -> int` | How many slots `section` has; 0 (reported) for an unknown section. |
| `slots` | `slots(section: Variant) -> Array` | A copy: an item or null per slot. |
| `item_at` | `item_at(section: Variant, index: int) -> Variant` | Null when empty or out of range. |
| `has_room` | `has_room(section: Variant = null) -> bool` | A free slot in `section`, or anywhere. |
| `add` | `add(item: Variant) -> bool` | First free slot of the first section in the add order that has one. False (nothing changes) when full or already held; a null item is reported. |
| `add_to` | `add_to(item: Variant, section: Variant) -> bool` | That section's first free slot. False when it is full or `item` is already held; a null item or unknown section is reported. |
| `remove` | `remove(item: Variant) -> bool` | Empties its slot; neighbors keep theirs. False when it isn't held. |
| `move` | `move(item: Variant, to_section: Variant = null) -> bool` | To `to_section`'s first free slot; with null, to the first other section in the add order with room. False (nothing changes) when not held, same section, or full. |
| `section_of` | `section_of(item: Variant) -> Variant` | Its section, or null. |
| `index_of` | `index_of(item: Variant) -> int` | Its slot within its section, or -1. |
| `has` | `has(item: Variant) -> bool` | Whether `item` is held anywhere. |
| `items` | `items(section: Variant = null) -> Array` | Held items in slot order (empty slots skipped); all sections in declaration order when null. A new array each call. |
| `grow` | `grow(section: Variant, count: int) -> void` | Appends `count` empty slots. A non-positive count or unknown section is reported and changes nothing. |

## Usage

```gdscript
extends Node

enum Section { HOTBAR, BACKPACK }

# A 5-slot hotbar, then a 20-slot backpack. add() fills them in this order.
var inventory := LFSlotInventory.new({Section.HOTBAR: 5, Section.BACKPACK: 20})


func _ready() -> void:
	inventory.changed.connect(_redraw)

	var sword := Resource.new()  # your own item objects; any unique Object works
	var potion := Resource.new()
	inventory.add(sword)   # hotbar slot 0
	inventory.add(potion)  # hotbar slot 1

	inventory.move(sword, Section.BACKPACK)        # backpack slot 0
	print(inventory.item_at(Section.HOTBAR, 1) == potion)  # true: potion did not shift
	print(inventory.index_of(sword))               # 0
	print(inventory.has_room(Section.HOTBAR))      # true

	inventory.grow(Section.BACKPACK, 10)           # a bag upgrade: 30 slots now
	inventory.remove(potion)


func _redraw() -> void:
	for slot in inventory.slots(Section.HOTBAR):  # an item or null per slot
		pass  # draw the slot's icon, or an empty frame for null
```

## Notes

- Items are found by `==`, so use Objects (or otherwise unique values); an item can be
  held only once, and null is never an item.
- Section keys are any values except null (an enum, StringNames). An unknown section is reported
  (`push_error`) and changes nothing.
- A freed Object in a slot reads as an empty slot (`slots`, `item_at`, `items`) and is
  overwritten by the next `add`; call `remove` first if you want `changed` announced.
- A section left out of `add_order` is never filled by `add` — only by `add_to` or `move`.
- Lookups scan the slots, which suits inventories of tens of slots, not thousands.
- Rules about what an item may do (merge, stack, which section allows it) belong to the
  caller: extend this class or keep one inside your own.
