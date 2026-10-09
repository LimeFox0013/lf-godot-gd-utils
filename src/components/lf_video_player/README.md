# LFVideoPlayer

> A `VideoStreamPlayer` that plays a timed segment and then holds the frame, with chainable millisecond-based start/pause/unpause.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_video_player.gd` |
| **Tests** | `tests/test_lf_video_player.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it to show part of a video: a 3-second teaser from 0:12 on a title screen, a tutorial
clip that stops on its last frame until the player clicks, or a cutscene beat that waits
for the video before the dialogue continues. `await player.play_for(3000.0, 12000.0)`
plays that segment, pauses, and returns (its time stands still while the game is paused),
and `start_at` seeks in the right order, since a seek before `play()` is lost. To play a
whole video once, a plain `VideoStreamPlayer` with `autoplay` is enough.

## Step by step

**Before you start:** you need a video file in Ogg Theora format (`.ogv`), the only video
format Godot plays. Copy it into your project folder; it appears in the FileSystem dock
and imports itself.

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock. Save it.
2. Click **+ Add Child Node**, type `LFVideoPlayer`, press *Create*.
3. In the Inspector drag your `.ogv` from the FileSystem dock onto the *Stream* slot. Turn
   *Expand* on and set *Layout → Custom Minimum Size* to x = `640`, y = `360` (pixels), so
   the picture is that big.
4. Right-click the root node, choose **Attach Script**, press *Create*, and replace the
   script's contents with:

   ```gdscript
   extends Control

   @onready var video: LFVideoPlayer = $LFVideoPlayer


   func _ready() -> void:   # runs once when the scene starts
   	# Play 3000 ms (3 s) of the video, starting at 2000 ms (0:02), then pause on the
   	# last frame. `await` means "wait here until this finishes".
   	await video.play_for(3000.0, 2000.0)
   	print("Segment done")
   ```
5. Change `3000.0` (how long, milliseconds) and `2000.0` (where to start, milliseconds).
6. Press **F6** (*Run Current Scene*). The video plays for three seconds and freezes on
   its last frame, and the **Output** panel shows `Segment done`. If the video starts from
   the beginning instead of 0:02, your file does not support seeking; see the Notes.

## API

Everything the class offers; you only need the rows used above to get started. A signal is an event other code can listen to; a coroutine is a function you `await`.

### Signals

| Member | Signature | Description |
|---|---|---|
| `segment_finished` | `segment_finished(completed: bool)` | A `play_for` segment ended. `completed` is true when its time ran out (the player is now paused), false when it was cut short. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `start_at` | `start_at(ms := 0.0, force_unpause := false) -> LFVideoPlayer` | Calls `play()`, then seeks with `stream_position = ms / 1000`, optionally clears `paused`. Ends a running segment without pausing. Outside the tree it reports an error and does nothing. Returns `self`. |
| `pause` | `pause() -> LFVideoPlayer` | `paused = true`. Returns `self`. |
| `unpause` | `unpause() -> LFVideoPlayer` | `paused = false`. Returns `self`. |
| `play_for` | `play_for(duration_ms := 0.0, from_ms := stream_position * 1000.0) -> LFVideoPlayer` | Coroutine: `start_at(from_ms, true)`, plays `duration_ms` ms of video, then pauses. Returns `self` when the segment ends, however it ends. A negative or NaN duration, or a player outside the tree, is reported and starts nothing (it returns at once). |

A segment's time is how far `stream_position` advances, so it stands still while the video
is paused by `pause()` or by a tree pause. It ends early, without pausing (emitting
`segment_finished(false)`), when:
- playback stops (`stop()`, or the video reaches its end);
- playback restarts: Godot's own `play()` (seen as `stream_position` moving backwards),
  `start_at`, or another `play_for`. With `loop` on, the jump back when the stream wraps
  from its end to its start is not a restart: the segment keeps counting through it;
- `stream` changes;
- the player leaves the tree (including being freed).

## Usage

```gdscript
# title_screen.gd. In the scene: an LFVideoPlayer named Intro (add a
# VideoStreamPlayer and attach lf_video_player.gd) with a .ogv video in its Stream.
extends Control

@onready var intro: LFVideoPlayer = $Intro


func _ready() -> void:
	intro.segment_finished.connect(_on_segment_finished)
	await intro.play_for(3000.0, 12000.0)   # play 3 s starting at 0:12, then pause
	print("Teaser done; the last frame stays on screen.")


func _on_segment_finished(completed: bool) -> void:
	if not completed:
		print("The teaser was cut short (stopped, restarted or removed).")


# The controls return the player, so they chain.
func restart_paused() -> void:
	intro.start_at(0.0).pause()
```

## Notes

- All times are milliseconds; `stream_position` itself is seconds.
- `play_for` pauses (not stops) at the end; call `stop()` yourself to rewind.
- Seeking happens after `play()`, because `play()` restarts from the beginning. Whether the seek takes effect depends on the stream: Godot's `VideoStreamPlayer` only seeks for formats/backends that support it (Theora support is limited), otherwise playback starts from 0. `play_for`'s default `from_ms` (the current position) therefore restarts from 0 on such streams.
- A backwards jump of `stream_position` during a segment counts as a restart (seeking backwards ends the segment), except a `loop` wrap: with `loop` on, a jump back on the frame the position plus that frame's playback reaches `get_stream_length()` (within 0.05 s) counts the time up to the end plus the time from the start. A stream whose length is unknown (0) cannot be told apart, so its wrap still ends the segment.
- Limit of that wrap test: `VideoStreamPlayer` wraps a looping stream internally (it calls its own `play()`) and emits no signal for it, so the segment can only judge by positions. With `loop` on, any backwards jump on a frame where the previous position plus that frame's playback (`delta × speed_scale`) is within 0.05 s of the end counts as a wrap, also one you caused: setting `stream_position` back (to any point, not only the start) or calling `play()` during those last 0.05 s keeps the segment running and counts `length - previous position + new position` as played. Earlier in the stream, or with `loop` off, such a jump ends the segment as described above.
- `start_at` without `force_unpause` on a paused player starts playback that stays paused: `play()` does not clear `paused`.
- `VideoStreamPlayer` ignores `stream_position` writes and `play()` while no `stream` is loaded, so set `stream` first. Without a stream nothing plays, and a `play_for` ends on the next frame as stopped.
- The player must be in the tree: `play()` needs it, and the segment is watched from `_process`. Outside it, `start_at` and `play_for` report an error and do nothing.
