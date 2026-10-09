## Sends input events through a stack of prioritized handlers, so an open overlay can block
## input to the scene below it.
##
## Each layer is a handler function with a priority and an owner node. An event goes to
## the layers from the highest priority down, and a layer that consumes it (returns
## true) hides it from every layer below. A layer is dropped when its owner leaves the
## tree. Add one manager per scene (or per overlay); managers share no state.
class_name LFInputManager
extends Node

static var _log := LFLogger.new()

## Default `priority` of `add_layer`.
const DEFAULT_PRIORITY := 0
## The id `add_layer` returns when it refuses a layer; no layer ever has it.
const _NO_ID := 0
## The id of the first layer a manager adds; later ones count up from it.
const _FIRST_ID := 1

## Where a manager picks events up from the viewport.
enum Stage {
	## `_unhandled_input`: after GUI controls had their turn (the default).
	UNHANDLED,
	## `_input`: before GUI controls, so a layer can take keys a focused control would use.
	INPUT,
	## Nowhere: the caller hands events to `route` itself.
	MANUAL,
}

## One registered handler (internal; callers hold its id).
class Layer:
	## The id `add_layer` returned; never 0.
	var id: int
	## The node whose leaving the tree drops the layer, and whose processing state decides
	## whether it takes part (unless `always_active`).
	var owner_node: Node
	## `func(event) -> bool`; true consumes the event.
	var handler: Callable
	## Higher runs first.
	var priority: int
	## Optional `func() -> bool` asked as each event reaches the layer.
	var enabled: Callable
	## The `set_layer_enabled` switch.
	var switched_on := true
	## The `set_layer_always_active` switch: the owner's processing state is not checked.
	var always_active := false


## Where this manager picks events up from. Events a layer consumes are marked handled in
## the viewport, so later input stages and other listeners never see them.
@export var stage := Stage.UNHANDLED

## Layers in routing order: highest priority first, the newest first among equals.
var _layers: Array[Layer] = []
var _next_id := _FIRST_ID


## Routes even while the tree is paused; a layer's own owner decides whether it takes
## part then (see `route`).
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if stage == Stage.INPUT:
		_route_from_viewport(event)


func _unhandled_input(event: InputEvent) -> void:
	if stage == Stage.UNHANDLED:
		_route_from_viewport(event)


## Adds a layer and returns its id. `handler(event)` returns `true` to consume the event
## (any other return value, or none, passes it on). `enabled() -> bool`, when given, is
## asked each time an event reaches the layer, so the layer can follow UI state (a menu's
## `visible`). The layer is dropped when `owner_node` leaves the tree; layers of equal
## `priority` run newest first.
func add_layer(owner_node: Node, handler: Callable, priority := DEFAULT_PRIORITY, enabled := Callable()) -> int:
	if owner_node == null or not handler.is_valid():
		_log.error('LFInputManager.add_layer needs an owner node and a valid handler')
		return _NO_ID
	var layer := Layer.new()
	layer.id = _next_id
	_next_id += 1
	layer.owner_node = owner_node
	layer.handler = handler
	layer.priority = priority
	layer.enabled = enabled
	var on_exit := _drop_layers_of.bind(owner_node)
	if not owner_node.tree_exiting.is_connected(on_exit):
		owner_node.tree_exiting.connect(on_exit)
	var index := 0
	while index < _layers.size() and _layers[index].priority > priority:
		index += 1
	_layers.insert(index, layer)
	return layer.id


## Drops the layer `id`. Unknown ids are ignored.
func remove_layer(id: int) -> void:
	var layer := _find(id)
	if layer == null:
		return
	_layers.erase(layer)
	_release_owner(layer.owner_node)


## Drops every layer.
func clear() -> void:
	var layers := _layers.duplicate()
	_layers.clear()
	for layer: Variant in layers:
		_release_owner(layer.owner_node)


## Whether the layer `id` is still registered.
func has_layer(id: int) -> bool:
	return _find(id) != null


## Switches the layer `id` on or off. Takes effect at once, even for the event being
## routed right now. Unknown ids are ignored.
func set_layer_enabled(id: int, on: bool) -> void:
	var layer := _find(id)
	if layer != null:
		layer.switched_on = on


## Lets the layer `id` take part whatever its owner's processing state: a paused tree or
## the owner's `process_mode` no longer keep it out. Use it for the key that opens and
## closes a pause menu, which must work both while the game runs and while it is paused.
## The `set_layer_enabled` switch, the `enabled` predicate and the owner being inside the
## tree and not queued for deletion still apply. Unknown ids are ignored.
func set_layer_always_active(id: int, on: bool) -> void:
	var layer := _find(id)
	if layer != null:
		layer.always_active = on


## Whether the layer `id` was marked with `set_layer_always_active`; false for an unknown id.
func is_layer_always_active(id: int) -> bool:
	var layer := _find(id)
	return layer != null and layer.always_active


## Whether the layer `id` is switched on (`set_layer_enabled`); false for an unknown id.
## The `enabled` predicate is not consulted.
func is_layer_enabled(id: int) -> bool:
	var layer := _find(id)
	return layer != null and layer.switched_on


## Hands `event` to the layers in order and returns whether one consumed it. A layer
## takes part when it is switched on, its `enabled` predicate (if any) returns true, and
## its owner is inside the tree, not queued for deletion itself and able to process (so
## while the tree is paused only owners that can process then receive), the last check
## skipped for a layer marked with `set_layer_always_active`. Every check is made as
## the event reaches the layer, so a handler that switches a lower layer off, or hides
## its menu, stops that same event from reaching it. Layers added while routing wait for
## the next event. A layer whose owner, handler object or predicate object was freed is
## dropped.
func route(event: InputEvent) -> bool:
	if is_queued_for_deletion():
		return false
	for layer: Variant in _layers.duplicate():
		if not _layers.has(layer):
			continue
		if not _is_alive(layer):
			_layers.erase(layer)
			continue
		if not _takes_part(layer):
			continue
		var result: Variant = layer.handler.call(event)
		if result is bool and result:
			return true
	return false


func _route_from_viewport(event: InputEvent) -> void:
	if route(event) and is_inside_tree():
		get_viewport().set_input_as_handled()


func _takes_part(layer: Layer) -> bool:
	if not layer.switched_on:
		return false
	var owner_node := layer.owner_node
	if not owner_node.is_inside_tree() or owner_node.is_queued_for_deletion():
		return false
	if not layer.always_active and not owner_node.can_process():
		return false
	if layer.enabled.is_null():
		return true
	var on: Variant = layer.enabled.call()
	return on is bool and on


## False once the owner, or the object behind the handler or the predicate, is freed.
func _is_alive(layer: Layer) -> bool:
	return is_instance_valid(layer.owner_node) and layer.handler.is_valid() \
		and (layer.enabled.is_null() or layer.enabled.is_valid())


func _find(id: int) -> Layer:
	for layer in _layers:
		if layer.id == id:
			return layer
	return null


## Stops listening to `owner_node` once none of its layers is left.
func _release_owner(owner_node: Node) -> void:
	if not is_instance_valid(owner_node) or _layers.any(func(layer: Layer) -> bool: return layer.owner_node == owner_node):
		return
	var on_exit := _drop_layers_of.bind(owner_node)
	if owner_node.tree_exiting.is_connected(on_exit):
		owner_node.tree_exiting.disconnect(on_exit)


func _drop_layers_of(owner_node: Node) -> void:
	_layers = _layers.filter(func(layer: Layer) -> bool: return layer.owner_node != owner_node)
	_release_owner(owner_node)
