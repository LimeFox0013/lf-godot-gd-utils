## One active copy (a "stack") of a status effect on one owner, as `LFStatusEffects.stacks()` returns it.
##
## Created by the container; read its fields (for example `data` in a tick callback), but
## don't change them. Times are absolute on the owning container's clock
## (`LFStatusEffects.now()`), so nothing here counts down per frame.
class_name LFStatusStack

## Default `count` of a stack: one copy.
const DEFAULT_COUNT := 1

## Absolute time on the container clock at which this stack expires.
var expires_at: float
## Absolute time of this stack's next tick; INF when the stack never ticks.
var next_tick_at: float
## Seconds between this stack's ticks; 0 when it never ticks (no positive interval, or no
## callback to call). For a stack with an `interval_fn` it is the most recently chosen
## interval (0 once the function ended the ticking).
var tick_interval: float
## 1 for an INDEPENDENT stack; the refresh count (up to the cap) for a SHARED one.
var count: int = DEFAULT_COUNT
## Caller payload supplied at apply time (e.g. a strength or a reference).
var data: Variant
## Overrides the definition's `on_tick` for this stack when valid.
var on_tick: Callable
## When valid, `func(stack: LFStatusStack) -> float` chooses the seconds until the next tick
## each time (see `LFStatusEffectDef.interval_fn`); `tick_interval` then is not used for
## scheduling.
var interval_fn: Callable
## Who applied this stack, as passed to `apply()`; what a per-source cap counts by.
var source: Variant
## Internal: set when the container drops this stack, so a tick walk in progress skips it.
## Read and written only by `LFStatusEffects`, hence the warning ignore.
@warning_ignore("unused_private_class_variable")
var _removed := false


## A stack expiring at `expiry_time`, ticking every `interval` seconds from
## `first_tick_at` (INF: never), carrying `payload` and an optional own `tick_callback`.
## The container builds these; you rarely need to.
func _init(expiry_time: float = 0.0, interval: float = 0.0, first_tick_at: float = INF, payload: Variant = null, tick_callback: Callable = Callable()) -> void:
	expires_at = expiry_time
	tick_interval = interval
	next_tick_at = first_tick_at
	data = payload
	on_tick = tick_callback
