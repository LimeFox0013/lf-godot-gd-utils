# LFFactory

> Reuses nodes (bullets, sparks, enemies) instead of creating and deleting them over and over.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_factory.gd` |
| **Tests** | `tests/test_lf_factory.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils` (`tree_root`), `LFLogger` |

## When to use it

Use it when your game creates and destroys many copies of the same node, such as a gun
that fires twenty bullets a second or hit sparks on every impact. Creating and freeing
nodes that often can cause stutters; a pool keeps released nodes and hands them out again.
You register each kind once with a function that builds it, then call `acquire` to get
one and `release` when you are done with it. One factory holds several kinds (bullets,
sparks, enemies), each with its own pool. If you spawn only a few nodes now and then,
plain `scene.instantiate()` plus `add_child` is simpler.

## Step by step

A *pool* is a box of spare nodes: instead of deleting a bullet you put it back in the box and take it out again later.

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **2D Scene** (a `Node2D`).
2. Right-click the `Node2D`, choose **Attach Script**, and press *Create*.
3. Select everything in the script and replace it with:

```gdscript
extends Node2D

var _pool := LFFactory.new()


func _ready() -> void:
	_pool.set_container(self)  # new nodes become children of this node
	# Teach the pool one kind of thing, named &"dot": how to build it, and what to do
	# when it is taken out (show it) or put back (hide it).
	_pool.register(&"dot", _make_dot, _show_dot, _hide_dot)


# Called only when the pool has no spare dot. It builds a brand-new one.
func _make_dot() -> Node:
	var dot := ColorRect.new()  # a plain coloured square
	dot.size = Vector2(24, 24)  # pixels
	dot.color = Color.ORANGE
	return dot


func _show_dot(dot: ColorRect) -> void:
	dot.show()


func _hide_dot(dot: ColorRect) -> void:
	dot.hide()


# Godot calls this for every input event nobody else used.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var dot: ColorRect = _pool.acquire(&"dot")  # take a dot out of the pool
		dot.position = event.position
		await get_tree().create_timer(1.0).timeout  # wait here for 1 second
		_pool.release(dot)                          # put it back instead of deleting it
		print("spare dots: ", _pool.pooled_count(&"dot"))
```

4. Press **F6** (*Run Current Scene*) and save the scene when asked.
5. Click in the game window: an orange square appears where you clicked, disappears after one second, and the **Output** panel prints `spare dots: 1`. Click again after that: the same square is reused (the count goes back up to 1). Clicking again within the second takes a second square from the pool, so the count can then reach 2.
6. Change the `1.0` for how long a dot lives (seconds), and `Vector2(24, 24)` for its size (pixels). In your own game, `_make_dot` would return `my_scene.instantiate()` instead.

## API

Everything the class offers; you only need the rows used above to get started.

"Entity" means a Node the factory created.

| Member | Signature | Description |
|---|---|---|
| `container` | `var container: Node` | Default parent of fresh entities. |
| `set_container` | `set_container(new_container: Node) -> void` | Sets the parent of fresh entities. Replacing a different live container reports an error. |
| `register` | `register(key: Variant, create_fn: Callable, on_acquire: Callable = Callable(), on_release: Callable = Callable(), on_created: Callable = Callable()) -> void` | Defines a key. `create_fn` takes no arguments and returns a new Node. Hooks get the entity; they are called, never awaited. Registering again replaces it: idle pooled entities are freed, ones handed out under the old definition are freed when released. |
| `is_registered` | `is_registered(key: Variant) -> bool` | Whether `key` has a registration. |
| `acquire` | `acquire(key: Variant) -> Node` | Synchronous: a pooled entity, or a fresh one created and added to the container in this call. Null with an error for an unknown key, no (or a freed) container, or a creation function that is invalid (empty, or its object freed), returns no Node, or returns a Node that is already tracked or in the tree. See "Where to call acquire and release". |
| `acquire_async` | `acquire_async(key: Variant) -> Node` | Coroutine (a function that can wait; call it with `await`). A pooled entity comes back at once, without waiting a frame. Otherwise awaits the creation function, runs `on_created`, then adds the entity with a deferred `add_child` plus one frame. Null if `reset()`, a re-register or the container being freed happened meanwhile (the entity is freed), or, with an error, if the creation function returns no Node (or one already tracked or in the tree). |
| `release` | `release(entity: Variant) -> bool` | Pools it (marked first, then `on_release`) and returns true. False for an untracked, already pooled, in-flight or freed entity, for one that `on_release` freed or queued for deletion (forgotten, not pooled), and for a stale one (its key re-registered), which is freed instead. |
| `release_all` | `release_all() -> void` | Pools every handed-out entity; stale ones (their key re-registered) are freed. |
| `reset` | `reset() -> void` | Frees every tracked entity, empties pools, forgets the container; keeps registrations. Frees with `queue_free` (gone at the end of the frame). |
| `pooled_count` | `pooled_count(key: Variant) -> int` | Idle entities in `key`'s pool; 0 for an unknown key. Entities freed elsewhere are not counted. Sweeps every record each call: the cost grows with the record count (see Notes). |
| `tracked_count` | `tracked_count(key: Variant = null) -> int` | Handed-out plus pooled entities for `key`; null counts every key. In-flight `acquire_async` entities and entities freed elsewhere are not counted. Sweeps every record each call, like `pooled_count`. |
| `is_pooled` | `is_pooled(entity: Variant) -> bool` | Live and sitting in a pool. Safe on a freed entity. |
| `owns` | `owns(entity: Variant) -> bool` | Live and tracked (handed out or pooled). False for a stranger, a freed or in-flight entity, and everything after `reset()`. |

## Usage

```gdscript
extends Node2D

const BULLET_SCENE := preload("res://bullet.tscn")  # your own scene

var _pool := LFFactory.new()


func _ready() -> void:
	_pool.set_container(self)  # fresh bullets become children of this node
	_pool.register(&"bullet", BULLET_SCENE.instantiate, _on_bullet_acquired, _on_bullet_released)


func fire(from: Vector2) -> void:
	var bullet: Node2D = _pool.acquire(&"bullet")  # already in the tree, this frame
	bullet.global_position = from


func bullet_hit(bullet: Node2D) -> void:
	_pool.release(bullet)  # back into the pool instead of queue_free()


func _on_bullet_acquired(bullet: Node2D) -> void:
	bullet.show()
	bullet.process_mode = Node.PROCESS_MODE_INHERIT


func _on_bullet_released(bullet: Node2D) -> void:
	bullet.hide()
	bullet.process_mode = Node.PROCESS_MODE_DISABLED
```

## Notes

- Hook order: `on_created` once per fresh entity (before it is parented), `on_acquire` on
  every hand-out, `on_release` on every release that pools it.
- A released entity stays in the tree. Hide it and stop its processing in `on_release`, and
  reset its state in `on_acquire`.
- An entity is never handed out twice without a release in between, and never handed out
  freed.
- Fresh entities are parented with `add_child`; `owner` is not set.
- Hooks and lifetime. Methods (like `_hide_dot` above) and inline `func()` lambdas both work as hooks; the rules are the same as for any Godot Callable:
  - Nodes are not reference-counted, so no Callable keeps a Node alive, and a lambda that uses a Node's `self` forms no cycle.
  - A RefCounted object (a Resource, or an object whose script extends `RefCounted` or nothing) is kept alive by a lambda that uses its `self` or captures a variable holding it. Stored in a factory that the same object holds, such a lambda is a cycle: neither is ever freed. A method Callable (`obj.method`) holds no reference.
  - Once the object behind a hook is freed, a method of it, or a lambda that uses its `self`, reports `is_valid() == false`: LFFactory then skips that hook silently, and `acquire` reports a creation function in that state and returns null. A lambda that only captured a freed node in a local variable still reports itself valid; calling it makes Godot report an error and pass `null` in place of that node, so check `is_instance_valid` inside such a lambda.

- `set_container` to a different node while entities are out leaves them parented to the
  old one (only an error is reported).
- `reset()` forgets the container: call `set_container` again before the next `acquire`. A
  container freed without `reset()` (a scene change) is detected: `acquire` reports and
  returns null.
- An entity still being parented by `acquire_async` can't be released until the call
  returns it.
- An entity freed without `release` (for example by an animation that frees its node when
  done) is forgotten: the counts skip it at once, and its record is dropped by a sweep.
  The sweep runs inside `acquire` and `acquire_async` after max(32, records left by the
  previous sweep) fresh entities were created. With L records left by the last sweep (all
  live then), the factory holds at most L + max(32, L) records, live or not, however many
  entities were spawned; a sweep goes over every record once. `pooled_count` and `tracked_count` also sweep, on every call, so they cost time in proportion to the records of all keys (measured on a desktop CPU: about 0.15 ms per call with 2000 records). Keep your own count if you need one every frame.

## Where to call acquire and release

What happens in each place (each row is covered by a test):

| Called from | `acquire` (fresh entity) | `acquire` (from the pool), `release` |
|---|---|---|
| Ordinary game code and `_physics_process` | Safe, physics entities included. | Safe. |
| A physics-overlap signal (`body_entered`, `area_entered`, ...), emitted while the physics server flushes its queries | An entity holding an Area or a body with shapes makes Godot report "Can't change this state while flushing queries": use `acquire_async`, or `acquire.call_deferred(key)` (both raise no error there). | Safe with hooks that show/hide the entity and switch its `process_mode` (as in Usage). Other hooks follow Godot's rules there: change physics state with `set_deferred`. |
| An `LFStateMachine` hook (tested with an enter hook) | Safe. | Safe. But when the entity's own machine is the one running that hook, an `on_acquire` that calls its `do()` is refused (`false`): one transition at a time. Release it from a `state_entered` listener (a `do()` there is queued, not refused) or connect with `CONNECT_DEFERRED`. |
| An `LFStatusEffects` tick callback | Safe. | Safe; an `on_release` that calls the entity's `effects.clear()` stops its remaining ticks. |
| While the container is setting up its children (a child's `_ready` as the container enters the tree with it) | Godot refuses the `add_child` ("Parent node is busy setting up children"), so the entity comes back outside the tree: use `acquire_async`. | Neither adds a node to the tree; only your hooks' own tree changes are subject to Godot's rule. |
