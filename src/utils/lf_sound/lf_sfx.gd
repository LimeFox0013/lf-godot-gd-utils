## Plays short sound effects from a pool of players, so that sounds overlap and none is cut off by a new one until
## every player is busy.
##
## Add one to the scene and call `play(stream)` from anywhere that holds it. `pitch` and `volume_db` change one play
## only; a little random pitch (`pitch_jitter`) keeps a sound that repeats from tiring the ear.
class_name LFSfx
extends Node

## How many sounds can play at once; when all are busy the players are cut in turn. Read when the node enters the tree.
@export var voices := 8
## Each play's pitch is multiplied by a random factor within 1 plus or minus this.
@export var pitch_jitter := 0.0
## The audio bus the players play on.
@export var bus: StringName = &"Master"

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for i in maxi(voices, 1):
		var player := AudioStreamPlayer.new()
		player.bus = bus
		add_child(player)
		_players.append(player)


## Plays `stream` on a free player, or else on the next player in turn (round-robin). Returns false for a null stream.
func play(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	if stream == null or _players.is_empty():
		return false
	var player := _free_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)), 0.01)
	player.play()
	return true


## How many players are playing now.
func busy_count() -> int:
	var busy := 0
	for player in _players:
		if player.playing:
			busy += 1
	return busy


func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	return player
