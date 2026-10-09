## Keeps the client's playback time a little behind the newest server update, so movement
## from the network looks smooth.
##
## This is the clock for entity interpolation (showing each networked object slightly in
## the past, between two updates already received, instead of guessing ahead). It runs at
## real speed `delay` seconds behind the newest stamp heard, closes any drift slowly
## (`correction_rate` of the gap per second) so uneven update arrival does not show as
## speed changes, jumps when it is more than `snap_seconds` off (the first data, or a long
## stall), and never passes the newest stamp, since nothing is known beyond it.
##
## Call `stamp(time)` once per received update with its server time, then `advance(delta)`
## once per frame and sample every `LFInterpolationBuffer` at the result.
class_name LFPlaybackClock
extends RefCounted

## Default `delay`: seconds the playback trails the newest stamp.
const DEFAULT_DELAY := 0.1
## Default `correction_rate`: share of the gap closed per second.
const DEFAULT_CORRECTION_RATE := 0.5
## Default `snap_seconds`: a larger gap, in seconds, is jumped.
const DEFAULT_SNAP_SECONDS := 0.5

## Seconds the playback trails the newest stamp. A couple of update intervals rides out
## one late update.
var delay: float
## The share of the gap to the wanted time closed per second (0.5 = half the gap per
## second). 0 never corrects small drift; large gaps still jump.
var correction_rate: float
## A gap larger than this many seconds is jumped instead of closed slowly.
var snap_seconds: float
## The current playback time; -INF before the first stamp. May be set directly.
var time := -INF
## The newest stamp heard; -INF before the first.
var latest := -INF


## Creates a clock that trails the newest stamp by `trail_seconds`, closes small drift at
## `drift_correction_rate` of the gap per second, and jumps over gaps larger than
## `jump_after_seconds`. It waits for the first `stamp()`.
func _init(trail_seconds := DEFAULT_DELAY, drift_correction_rate := DEFAULT_CORRECTION_RATE, jump_after_seconds := DEFAULT_SNAP_SECONDS) -> void:
	delay = trail_seconds
	correction_rate = drift_correction_rate
	snap_seconds = jump_after_seconds


## Notes an update stamped `stamp_time`. The first one starts playback `delay` behind it;
## an older or equal stamp, or one that is not finite, changes nothing.
func stamp(stamp_time: float) -> void:
	if is_finite(stamp_time) and stamp_time > latest:
		latest = stamp_time
		if not is_started():
			time = stamp_time - delay


## Moves playback on by `delta` seconds, nudged toward `delay` behind the newest stamp and
## capped at it, and returns the new playback time. Before the first stamp it returns -INF
## and does nothing.
func advance(delta: float) -> float:
	if not is_started():
		return time
	var wanted := latest - delay
	time += delta
	var gap := wanted - time
	if absf(gap) > snap_seconds:
		time = wanted
	else:
		time += gap * minf(correction_rate * delta, 1.0)
	time = minf(time, latest)
	return time


## Returns `true` once a stamp has been heard (until `reset()`).
func is_started() -> bool:
	return time != -INF


## Forgets every stamp; playback waits for the next one.
func reset() -> void:
	time = -INF
	latest = -INF
