# LFParticlePool

> A pool of particle systems copied from one you set up in the editor, for effects that fire often (landing dust, hit sparks).

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_particle_pool.gd` |
| **Tests** | `tests/test_lf_particle_pool.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFFactory`, `LFLogger` |

## When to use it

Use it when the same one-shot effect plays many times and sometimes with different colours or
amounts: each play needs its own material (so recolouring one does not recolour the rest) and
you do not want to create and free nodes each time. You design the effect once in the editor;
the pool makes independent copies and takes them back when they finish. For pooling any other
node use `LFFactory` directly.

## Step by step

1. In the editor open or create a scene with a **GPUParticles3D** (or 2D) node: set its
   *Process Material*, *Draw Pass* and tick *One Shot*. Untick *Emitting*. Rename it `Dust`.
2. Add a child to its parent: **Node**, rename it `DustPool`, and attach the script
   `lf_particle_pool.gd` (Inspector → *Script* → *Load*, found under `src/utils/lf_particle_pool`).
3. In the Inspector set the pool's *Reference* to `Dust`.
4. In your own script:

```gdscript
@onready var _dust: LFParticlePool = $DustPool

func land(at: Vector3, color: Color) -> void:
	var puff: GPUParticles3D = _dust.acquire()
	puff.global_position = at
	puff.process_material.color = color        # only this copy changes
	puff.restart()                              # when it finishes it goes back to the pool
```
5. Run the scene and call `land` a few times: each puff plays once and the pool reuses it.

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_WARM_UP` | `const DEFAULT_WARM_UP := 5` | Copies built ahead by default. |
| `reference` | `@export var reference: Node` | The `GPUParticles2D` / `GPUParticles3D` to copy. Anything else is an error. |
| `container` | `@export var container: Node` | Where copies go; empty: the reference's parent. |
| `warm_up` | `@export var warm_up := 5` | Copies built when the pool starts. |
| `acquire` | `acquire() -> Node` | An independent copy (own process material and draw pass), not yet restarted; null with an error without a usable reference. |
| `release` | `release(particles: Node) -> bool` | Gives a copy back early; false for a node the pool didn't hand out. |
| `pooled_count` | `pooled_count() -> int` | Copies waiting for reuse. |

## Notes

- A copy returns by itself when it emits `finished`, which only a one-shot system does. A system that loops must be given back with `release`.
- Copies are deep duplicates of the reference's `process_material` and `draw_pass_1` (3D), so a mesh's material is not shared either.
- Set the copy up (position, colour, amount) **before** `restart()`.
- Leave the reference in the scene: copies are made from it when needed. Keep it `Emitting` off so it does not play itself.
