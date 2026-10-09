## A video player that can play a timed segment ("3 s from 0:12, then hold the frame").
##
## It is a VideoStreamPlayer with millisecond-based `start_at`, `pause` and `unpause`
## that return the player (so calls can be chained), and `play_for`, which plays for a
## set time and then pauses. Use it with `await` to wait for the segment to end.
class_name LFVideoPlayer
extends VideoStreamPlayer

static var _log := LFLogger.new()

## A `play_for` segment ended: `completed` when its time ran out (the player is now
## paused), false when it was cut short (playback stopped or restarted, the stream
## changed, a newer start, or the player left the tree).
signal segment_finished(completed: bool)

## How far `stream_position` may step back before the segment counts it as a restart.
const _RESTART_TOLERANCE_S := 0.001
## How close to the stream's end (seconds) the last frame's position plus that frame's
## playback must reach for a jump back to count as `loop` wrapping around.
const _LOOP_END_TOLERANCE_S := 0.05
## Milliseconds per second, for the millisecond-based API.
const _MS_PER_S := 1000.0

var _segment_running := false
## Seconds of playback the running segment has left, counted down by how far
## `stream_position` advances.
var _segment_left := 0.0
var _segment_stream: VideoStream
var _segment_last_position := 0.0


func _ready() -> void:
	# Godot turns `_process` on at ready; a segment started before that keeps it on.
	set_process(_segment_running)


## Starts playback, then seeks to `ms` milliseconds (seeking only takes effect for
## streams whose format supports it), and clears `paused` when `force_unpause`; returns
## the player. Ends a running `play_for` segment without pausing. Outside the tree it is
## reported and starts nothing.
func start_at(ms := 0.0, force_unpause := false) -> LFVideoPlayer:
	if not is_inside_tree():
		_log.error('LFVideoPlayer.start_at needs the player in the tree')
		return self
	_end_segment(false)
	play()
	stream_position = ms / _MS_PER_S
	if force_unpause:
		paused = false
	return self


## Pauses playback (sets `paused`); returns the player.
func pause() -> LFVideoPlayer:
	paused = true
	return self


## Resumes paused playback (clears `paused`); returns the player.
func unpause() -> LFVideoPlayer:
	paused = false
	return self


## Coroutine: plays from `from_ms` for `duration_ms` milliseconds of playback, then
## pauses; returns the player. Use it with `await`. Time is measured by how far
## `stream_position` advances, checked in the player's `_process`, so it stands still
## while the video is paused (by `pause()` or by a tree pause) and the pause lands on the
## first frame at or past the end. The segment ends early, without pausing, when
## playback stops, restarts (`start_at`, another `play_for`, or `play()`, which is seen
## only as the position moving back) or moves backwards, the stream changes, or the
## player leaves the tree. The coroutine then returns: at once for `start_at`, another
## `play_for` or leaving the tree, at the player's next `_process` for the others.
## With `loop` on, a jump back right after the position reached the end
## (`get_stream_length()`) is the stream wrapping around, and the segment keeps counting
## through it; a stream that reports no length cannot be told apart from a restart, so
## its wrap ends the segment. Godot emits nothing on a loop wrap, so the test is by
## positions only: with `loop` on, a seek back or `play()` of your own on a frame that
## reaches within 0.05 s of the end also counts as a wrap. A negative or NaN
## `duration_ms`, or a player outside the tree, is reported and starts nothing.
func play_for(duration_ms := 0.0, from_ms := stream_position * _MS_PER_S) -> LFVideoPlayer:
	if not duration_ms >= 0.0:
		_log.error('LFVideoPlayer.play_for needs a duration of 0 ms or more, got %s' % duration_ms)
		return self
	if not is_inside_tree():
		_log.error('LFVideoPlayer.play_for needs the player in the tree')
		return self
	start_at(from_ms, true)
	_segment_running = true
	_segment_left = duration_ms / _MS_PER_S
	_segment_stream = stream
	_segment_last_position = stream_position
	set_process(true)
	await segment_finished
	return self


func _process(delta: float) -> void:
	if not _segment_running:
		set_process(false)
		return
	if not is_playing() or stream != _segment_stream:
		_end_segment(false)
		return
	var advanced := stream_position - _segment_last_position
	if stream_position < _segment_last_position - _RESTART_TOLERANCE_S:
		if not _wrapped(delta):
			_end_segment(false)
			return
		advanced = get_stream_length() - _segment_last_position + stream_position
	_segment_left -= advanced
	_segment_last_position = stream_position
	if _segment_left <= 0.0:
		paused = true
		_end_segment(true)


## Whether a jump back is `loop` restarting the stream at its end: the last position plus
## this frame's playback (`delta` scaled by `speed_scale`) reaches the stream's end.
func _wrapped(delta: float) -> bool:
	var length := get_stream_length()
	return loop and length > 0.0 and _segment_last_position + delta * speed_scale >= length - _LOOP_END_TOLERANCE_S


func _exit_tree() -> void:
	_end_segment(false)


func _end_segment(completed: bool) -> void:
	if not _segment_running:
		return
	_segment_running = false
	_segment_stream = null
	set_process(false)
	segment_finished.emit(completed)
