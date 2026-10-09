## The rules of a tree of nodes bought level by level: costs, maximum levels and prerequisites.
##
## Each node has a base cost that grows by a multiplier per level (100, 200, 400... with
## growth 2), a maximum level, and prerequisites that must each be owned at least once.
## It answers what the next level costs, whether it can be bought on a budget, and what a
## set of levels cost in all, and can spend a budget round-robin over a pool (one level
## per node per pass — handy for an automated buyer).
##
## Nodes are duck-typed: Dictionaries or Objects, read by field name. The names default to
## `id`, `base_cost`, `max_level`, `cost_growth` and `prerequisites`; pass others to
## `new()` to read your own node type as it is. Levels are `{node_id: level}` dictionaries
## or a `level_of(node_id) -> int` Callable. It holds no levels or points itself.
class_name LFUnlockTree
extends RefCounted

## The field read for a node's id when `new()` renames none.
const DEFAULT_ID_FIELD := &"id"
## The field read for a node's base cost when `new()` renames none.
const DEFAULT_BASE_COST_FIELD := &"base_cost"
## The field read for a node's maximum level when `new()` renames none.
const DEFAULT_MAX_LEVEL_FIELD := &"max_level"
## The field read for a node's cost growth when `new()` renames none.
const DEFAULT_COST_GROWTH_FIELD := &"cost_growth"
## The field read for a node's prerequisites when `new()` renames none.
const DEFAULT_PREREQUISITES_FIELD := &"prerequisites"

## What a node reads as when it lacks a field: no base cost, one level, no growth.
const _ABSENT_BASE_COST := 0.0
const _ABSENT_MAX_LEVEL := 1
const _ABSENT_COST_GROWTH := 1.0

## The keys `new()` accepts.
const _FIELD_KEYS: Array[String] = ["id", "base_cost", "max_level", "cost_growth", "prerequisites"]

static var _log := LFLogger.new()

## The field holding a node's key — what levels and prerequisites name it by.
var id_field: StringName = DEFAULT_ID_FIELD
## The field holding the cost of level 1 (read as 0 when absent).
var base_cost_field: StringName = DEFAULT_BASE_COST_FIELD
## The field holding how many levels can be bought (read as 1 when absent).
var max_level_field: StringName = DEFAULT_MAX_LEVEL_FIELD
## The field holding the cost multiplier per level beyond the first (read as 1, no
## growth, when absent).
var cost_growth_field: StringName = DEFAULT_COST_GROWTH_FIELD
## The field holding the ids that must each be owned at least once (read as none when
## absent).
var prerequisites_field: StringName = DEFAULT_PREREQUISITES_FIELD


## Rules reading nodes through `fields`, which may rename any of `id`, `base_cost`,
## `max_level`, `cost_growth` and `prerequisites` — e.g. `{"id": "node_key"}`.
## An unknown key is ignored and reported once through `LFLogger` as an error naming it.
func _init(fields: Dictionary = {}) -> void:
	for key: Variant in fields:
		if not _FIELD_KEYS.has(key):
			_log.error('LFUnlockTree: unknown field key "%s" ignored' % str(key))
	id_field = fields.get("id", id_field)
	base_cost_field = fields.get("base_cost", base_cost_field)
	max_level_field = fields.get("max_level", max_level_field)
	cost_growth_field = fields.get("cost_growth", cost_growth_field)
	prerequisites_field = fields.get("prerequisites", prerequisites_field)


## The cost of buying `level` (1 is the first purchase) of a node costing `base_cost`
## that grows by `cost_growth` per level: `base_cost × cost_growth^(level − 1)`.
static func cost_at(base_cost: float, cost_growth: float, level: int) -> float:
	return base_cost * pow(cost_growth, level - 1)


## The cost of buying `node`'s `level` (1 is the first purchase), from its fields.
func cost_for_level(node: Variant, level: int) -> float:
	return cost_at(float(_read(node, base_cost_field, _ABSENT_BASE_COST)), float(_read(node, cost_growth_field, _ABSENT_COST_GROWTH)), level)


## `node`'s id (null when it has none).
func id_of(node: Variant) -> Variant:
	return _read(node, id_field, null)


## How many levels of `node` can be bought (1 when it declares none).
func max_level_of(node: Variant) -> int:
	return int(_read(node, max_level_field, _ABSENT_MAX_LEVEL))


## Whether one more level of `node` can be bought on `budget`: not past its maximum, the
## next level affordable, and every prerequisite owned at least once. `level_of(id) ->
## int` gives any node's owned level. A null node, or a NaN cost or budget, never passes.
## Changes nothing.
func can_buy_next(node: Variant, level_of: Callable, budget: float) -> bool:
	if node == null:
		return false
	var next: int = int(level_of.call(id_of(node))) + 1
	# Written as "not affordable" so a NaN on either side fails the check.
	if next > max_level_of(node) or !(cost_for_level(node, next) <= budget):
		return false
	return _prerequisites_met(node, level_of)


## What every level in `levels` (`{id: level}`) cost, over the nodes in `nodes`. Levels
## past a node's maximum count as its maximum; ids not in `nodes` count nothing.
func spent(nodes: Array, levels: Dictionary) -> float:
	var total := 0.0
	for node: Variant in nodes:
		for level in range(1, mini(int(levels.get(id_of(node), 0)), max_level_of(node)) + 1):
			total += cost_for_level(node, level)
	return total


## Buys levels of `pool`'s nodes into `levels` (`{id: level}`, updated in place) for at
## most `limit` in all: one level per node per pass, in pool order, passes repeating until
## nothing more fits. Returns what it spent. Prerequisites are read from `levels` — or,
## when `level_of_override(id) -> int` is given (to count levels owned elsewhere), only
## through it, so a prerequisite bought earlier in this same call counts only if the
## override reads `levels` too. A node's own level always comes from `levels`.
## A NaN, infinite or negative `limit` is reported and buys nothing (returns 0). A node
## whose next level costs a negative amount or NaN is reported and skipped for the rest of
## the call, so it never adds budget. A null node is skipped.
func spend_round_robin(pool: Array, levels: Dictionary, limit: float, level_of_override := Callable()) -> float:
	if not is_finite(limit) or limit < 0.0:
		_log.error('LFUnlockTree.spend_round_robin: the limit must be a finite amount of 0 or more, got %s; nothing bought' % [limit])
		return 0.0
	var own_level := func(id: Variant) -> int: return int(levels.get(id, 0))
	var invalid := {} # node index -> true, for nodes with an invalid cost
	var spent_so_far := 0.0
	var bought := true
	while bought:
		bought = false
		for i in pool.size():
			if invalid.has(i):
				continue
			var node: Variant = pool[i]
			if node == null:
				continue
			var id: Variant = id_of(node)
			var next: int = own_level.call(id) + 1
			if next > max_level_of(node):
				continue
			var cost := cost_for_level(node, next)
			if is_nan(cost) or cost < 0.0:
				_log.error('LFUnlockTree.spend_round_robin: level %d of "%s" has an invalid cost (%s); skipped' % [next, id, cost])
				invalid[i] = true
				continue
			if cost > limit - spent_so_far:
				continue
			if !_prerequisites_met(node, level_of_override if level_of_override.is_valid() else own_level):
				continue
			levels[id] = next
			spent_so_far += cost
			bought = true
	return spent_so_far


func _prerequisites_met(node: Variant, level_of: Callable) -> bool:
	for prerequisite: Variant in _read(node, prerequisites_field, []):
		if int(level_of.call(prerequisite)) <= 0:
			return false
	return true


static func _read(node: Variant, field: StringName, fallback: Variant) -> Variant:
	var value: Variant = node.get(field) if node is Dictionary or node is Object else null
	return value if value != null else fallback
