# LFTone and LFSfx

> Simple sound effects made from code, and a small pool that plays them: a game with no sound files can still bleep, thud and chirp.

| | |
|---|---|
| **Kind** | `LFTone` is [static](../../../README.md#how-lf-classes-work): call it as `LFTone.make(...)`. `LFSfx` is a Node: add it to a scene |
| **Files** | `lf_tone.gd`, `lf_sfx.gd` |
| **Tests** | `tests/test_lf_tone.gd`, `tests/test_lf_sfx.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | nothing |

## When to use it

Use it for a prototype or a jam game that has no sound files yet, or for small effects (a click, a jump, a
landing thud, a count tick) that need no recording. A real game will want recorded sound for its voice and music;
`LFSfx` plays any `AudioStream`, so the tones can be swapped one by one for files later.

## Step by step

1. Add a node to your scene, attach a script and replace its text with the code below.
2. Press **F6**. You should hear a short bleep, then a falling chirp half a second later.

```gdscript
extends Node

var sfx := LFSfx.new()


func _ready() -> void:
	add_child(sfx)
	sfx.play(LFTone.make(660.0, 0.12, LFTone.Wave.SQUARE, 0.4))
	await get_tree().create_timer(0.5).timeout
	sfx.play(LFTone.make(900.0, 0.25, LFTone.Wave.TRIANGLE, 0.5, 200.0))
```

Make each tone once, keep it in a variable and play it as often as you like.

## API

`LFTone` (static):

| Member | Signature | Description |
|---|---|---|
| `make` | `make(frequency, seconds, wave = Wave.SINE, volume = 0.5, end_frequency = 0.0, attack = 0.005, rate = 22050) -> AudioStreamWAV` | A mono 16-bit sound. The pitch glides to `end_frequency` when it is above 0. The sound fades out over its length. An empty sound for a length of 0 or less, or a pitch of 0 or less (noise needs no pitch). |
| `samples` | same arguments `-> PackedByteArray` | The raw 16-bit samples `make` uses. |
| `Wave` | `SINE`, `SQUARE`, `TRIANGLE`, `NOISE` | The shape of the sound. Noise is the same every time. |

`LFSfx` (Node):

| Member | Signature | Description |
|---|---|---|
| `voices` | `int = 8` | How many sounds play at once; read when the node enters the tree. |
| `pitch_jitter` | `float = 0.0` | Each play's pitch is multiplied by a random factor within 1 plus or minus this. |
| `bus` | `StringName = &"Master"` | The audio bus the players use; read when the node enters the tree. |
| `play` | `play(stream, volume_db = 0.0, pitch = 1.0) -> bool` | Plays on a free player, else cuts the one that has played longest. False for a null stream. |
| `busy_count` | `busy_count() -> int` | How many players are playing now. |

## Notes

- Tones are 22 050 Hz mono: fine for bleeps, thin for anything that should sound rich.
- Make the tones once at start-up: making one costs a loop over every sample.
- Add the `LFSfx` to the tree before the first `play`; it makes its players when it enters the tree.
