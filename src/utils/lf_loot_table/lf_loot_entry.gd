## One possible drop in an [LFLootTable]: what you get back, and how likely it is.
##
## An entry holds a payload (`content`) and a relative `weight`, or a nested table
## (`subtable`) that is rolled in its place — e.g. one entry that rolls a separate
## table of its own.
class_name LFLootEntry
extends Resource


## The weight an entry gets when none is given: every default entry is equally likely.
const DEFAULT_WEIGHT := 1.0

## An optional name, used to find the entry later with `LFLootTable.find` (e.g. to
## change its weight).
@export var id: StringName = &""
## How likely this entry is, relative to the others: weight 2 is twice as likely as
## weight 1. Zero or less, NaN or `INF` is never chosen. The default 1 makes a table of default entries
## a uniform pick.
@export var weight: float = DEFAULT_WEIGHT
## When set, choosing this entry rolls this table instead, and its result is returned.
@export var subtable: LFLootTable
## The payload — whatever you want back (an item id, a scene, a Dictionary...). Saved
## with the resource when it is a saveable value. Not shown in the Inspector.
@export_storage var content: Variant


## An entry returning `initial_content`, chosen in proportion to `initial_weight`,
## named `initial_id`.
func _init(initial_content: Variant = null, initial_weight := DEFAULT_WEIGHT, initial_id: StringName = &"") -> void:
	content = initial_content
	weight = initial_weight
	id = initial_id


## A new entry that rolls `table` when chosen, with weight `entry_weight` and name
## `entry_id`.
static func nested(table: LFLootTable, entry_weight := DEFAULT_WEIGHT, entry_id: StringName = &"") -> LFLootEntry:
	var entry := LFLootEntry.new(null, entry_weight, entry_id)
	entry.subtable = table
	return entry
