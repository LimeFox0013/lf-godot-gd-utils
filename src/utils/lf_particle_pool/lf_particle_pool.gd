## A pool of particle systems copied from one you set up in the editor, for effects that fire often.
##
## Make a `GPUParticles2D` or `GPUParticles3D` once, with its material and look (one shot), and point
## `reference` at it. `acquire()` hands out an independent copy, with its own materials, so one
## can be recoloured without touching the rest; when a copy finishes it returns to the pool by
## itself and is reused. Restart it yourself after setting it up (`restart()`).
class_name LFParticlePool
extends Node

## How many copies are built ahead when none is set.
const DEFAULT_WARM_UP := 5
## The pool's key in its `LFFactory`.
const _KEY := &"particles"

## The particle node to copy: a `GPUParticles2D` or `GPUParticles3D`. Leave it where it is.
@export var reference: Node
## Where the copies are added. Empty: the reference's parent.
@export var container: Node
## How many copies are built when the pool starts, so the first effects don't stutter.
@export var warm_up := DEFAULT_WARM_UP

static var _log := LFLogger.new()

var _factory := LFFactory.new()


func _ready() -> void:
	if reference == null or not (reference is GPUParticles2D or reference is GPUParticles3D):
		_log.error("LFParticlePool: reference must be a GPUParticles2D or GPUParticles3D")
		return
	if container == null:
		container = reference.get_parent()
	_factory.set_container(container)
	_factory.register(_KEY, _copy_reference, Callable(), _stop)
	var warmed: Array[Node] = []
	for i in maxi(warm_up, 0):
		warmed.append(_factory.acquire(_KEY))
	for node in warmed:
		_factory.release(node)


## A copy of the reference, ready to configure and `restart()`; null (with an error) when the pool
## has no valid reference. It returns to the pool by itself when it emits `finished`
## (a one-shot system does), or when you give it back with `release`.
func acquire() -> Node:
	if !_factory.is_registered(_KEY):
		_log.error("LFParticlePool: acquire called without a usable reference")
		return null
	return _factory.acquire(_KEY)


## Gives a copy back before it has finished. False for a node this pool didn't hand out or one already back.
func release(particles: Node) -> bool:
	return _factory.release(particles)


## How many copies are waiting to be reused.
func pooled_count() -> int:
	return _factory.pooled_count(_KEY)


func _copy_reference() -> Node:
	var copy := reference.duplicate(true)
	if copy.get("process_material") != null:
		copy.process_material = copy.process_material.duplicate(true)
	if copy.get("draw_pass_1") != null:
		copy.draw_pass_1 = copy.draw_pass_1.duplicate(true)
	copy.finished.connect(_on_finished.bind(copy))
	return copy


func _on_finished(copy: Node) -> void:
	_factory.release(copy)


func _stop(copy: Node) -> void:
	copy.emitting = false
