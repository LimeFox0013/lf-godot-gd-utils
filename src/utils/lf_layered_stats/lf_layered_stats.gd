## Computes an object's final stats from layers such as base, flat bonuses, caps and multipliers.
##
## Each layer holds a `{stat_key: value}` dictionary and a combine rule
## `func(running_total, layer_value) -> float` (stock rules: `sum`, `product`, `min_of`,
## `max_of`). `resolve(stat_key)` "folds" the layers in declaration order: the first layer
## seeds the total, each later one combines into it, and a layer with nothing set for the
## key contributes its identity (the value that changes nothing: 0 for a sum, 1 for a
## product). So with layers base → flat (sum) → mult (product), a stat resolves to
## `(base + flat) × mult`. Nothing is cached: every `resolve()` recomputes.
##
## The declarations (order, rules, identities) live in a [LFLayeredStats.Layout] that any
## number of instances can share, so they are stored once for all of them. Value
## dictionaries are adopted by reference and never written to: one dictionary can feed
## many instances, and a write through this class copies it first.
class_name LFLayeredStats

static var _log := LFLogger.new()


## The list of layers — their order, combine rules and identities — shareable by any
## number of [LFLayeredStats] instances.
class Layout:
	var _index: Dictionary = {} # layer_key -> int
	var _keys: Array = []
	var _combines: Array[Callable] = []
	var _identities := PackedFloat64Array()

	## Adds `layer_key` as the next layer, folded in with `combine(total, value) -> float`;
	## an unset key reads as `identity`. Declaring it again swaps its rule and identity and
	## keeps its position. A `combine` that is not a valid Callable is reported as an error
	## and the layer is not declared.
	func declare(layer_key: Variant, combine: Callable, identity: float = 0.0) -> void:
		if !combine.is_valid():
			LFLayeredStats._log.error('LFLayeredStats: layer "%s" needs a valid combine rule' % [layer_key])
			return
		var at: int = _index.get(layer_key, -1)
		if at == -1:
			_index[layer_key] = _keys.size()
			_keys.append(layer_key)
			_combines.append(combine)
			_identities.append(identity)
			return
		_combines[at] = combine
		_identities[at] = identity

	## Whether `layer_key` is declared.
	func has(layer_key: Variant) -> bool:
		return _index.has(layer_key)

	## How many layers are declared.
	func size() -> int:
		return _keys.size()

	## The identity `layer_key` was declared with; 0.0 for an undeclared layer.
	func identity_of(layer_key: Variant) -> float:
		var at: int = _index.get(layer_key, -1)
		return _identities[at] if at != -1 else 0.0

	func _copy() -> Layout:
		var copy := Layout.new()
		copy._index = _index.duplicate()
		copy._keys = _keys.duplicate()
		copy._combines = _combines.duplicate()
		copy._identities = _identities.duplicate()
		return copy


const _EMPTY := {}


## Combine rule: adds the layer's value (identity 0).
static func sum(total: float, value: float) -> float:
	return total + value


## Combine rule: multiplies by the layer's value (identity 1).
static func product(total: float, value: float) -> float:
	return total * value


## Combine rule: caps the total at the layer's value (identity `INF`).
static func min_of(total: float, value: float) -> float:
	return minf(total, value)


## Combine rule: raises the total to at least the layer's value (identity `-INF`).
static func max_of(total: float, value: float) -> float:
	return maxf(total, value)


var _layout: Layout
var _layout_borrowed: bool
## One dictionary per layer index; `_EMPTY` until set.
var _values: Array[Dictionary] = []
## Whether `_values[i]` is this instance's own copy (writable without copying).
var _owned := PackedByteArray()


## With a `layout`, shares its layers; without one (null), starts with a private, empty
## layout to `declare_layer` on.
func _init(layout: Layout = null) -> void:
	_layout_borrowed = layout != null
	_layout = layout if layout != null else Layout.new()


## Adds `layer_key` as the next layer of this instance (see `Layout.declare`).
## With a shared layout, this instance switches to its own copy first, so the shared
## layout is never changed.
func declare_layer(layer_key: Variant, combine: Callable, identity: float = 0.0) -> void:
	if _layout_borrowed:
		_layout = _layout._copy()
		_layout_borrowed = false
	_layout.declare(layer_key, combine, identity)


## Whether `layer_key` is declared (on the shared layout or this instance's own).
func has_layer(layer_key: Variant) -> bool:
	return _layout.has(layer_key)


## Makes `values` (`{stat_key: number}`) the layer's dictionary, by reference — it
## replaces what was there, never merges. It is never written to: a later
## `set_value()`/`accumulate()` copies it first. An undeclared layer is reported as an
## error and changes nothing.
func set_layer_values(layer_key: Variant, values: Dictionary) -> void:
	var at := _at(layer_key)
	if at == -1:
		return
	_grow(at)
	_values[at] = values
	_owned[at] = 0


## The layer's current dictionary — a shared, read-only empty one when nothing is set (or
## the layer is undeclared, which is reported). Treat it as read-only.
func get_layer_values(layer_key: Variant) -> Dictionary:
	var at := _at(layer_key)
	if at == -1 or at >= _values.size():
		return _EMPTY
	return _values[at]


## The value stored for `stat_key` in the layer, or the layer's identity. An undeclared
## layer is reported and reads 0.0.
func get_value(layer_key: Variant, stat_key: Variant) -> float:
	var at := _at(layer_key)
	if at == -1:
		return 0.0
	var identity: float = _layout._identities[at]
	if at >= _values.size():
		return identity
	return _values[at].get(stat_key, identity)


## Stores `value` for `stat_key` in the layer (copying an adopted dictionary first). An
## undeclared layer is reported as an error and changes nothing.
func set_value(layer_key: Variant, stat_key: Variant, value: float) -> void:
	var at := _at(layer_key)
	if at == -1:
		return
	_writable(at)[stat_key] = value


## Folds `value` into the layer's stored value for `stat_key` through the layer's own rule
## (starting from its identity), stores the result and returns it — e.g. on a `product`
## layer, accumulating 1.5 then 2.0 stores 3.0. An undeclared layer is reported as an
## error, changes nothing and returns 0.0.
func accumulate(layer_key: Variant, stat_key: Variant, value: float) -> float:
	var at := _at(layer_key)
	if at == -1:
		return 0.0
	var values := _writable(at)
	var folded: float = _layout._combines[at].call(values.get(stat_key, _layout._identities[at]), value)
	values[stat_key] = folded
	return folded


## Drops every value of the layer, so each key reads as the layer's identity again. An
## undeclared layer is reported as an error.
func clear_layer(layer_key: Variant) -> void:
	var at := _at(layer_key)
	if at != -1 and at < _values.size():
		_values[at] = _EMPTY
		_owned[at] = 0


## The final value of `stat_key`: every declared layer's value for it folded into one
## total. Returns 0.0 with no layers. Creates no arrays, dictionaries or objects of its
## own (a combine rule you pass in may).
func resolve(stat_key: Variant) -> float:
	var count := _layout._keys.size()
	if count == 0:
		return 0.0
	var set_count := _values.size()
	var total: float = _values[0].get(stat_key, _layout._identities[0]) if set_count > 0 else _layout._identities[0]
	for i in range(1, count):
		var value: float = _values[i].get(stat_key, _layout._identities[i]) if i < set_count else _layout._identities[i]
		total = _layout._combines[i].call(total, value)
	return total


func _at(layer_key: Variant) -> int:
	var at: int = _layout._index.get(layer_key, -1)
	if at == -1:
		_log.error('LFLayeredStats: layer "%s" is not declared' % [layer_key])
	return at


func _grow(at: int) -> void:
	while _values.size() <= at:
		_values.append(_EMPTY)
		_owned.append(0)


func _writable(at: int) -> Dictionary:
	_grow(at)
	if !_owned[at]:
		_values[at] = _values[at].duplicate()
		_owned[at] = 1
	return _values[at]
