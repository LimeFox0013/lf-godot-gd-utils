## A room of some of an [LFSocketServer]'s peers, used as if it were a server of its own.
##
## Sends and broadcasts reach members only, a member's messages and disconnects are
## re-emitted by the group, and peers outside the group are never touched. Many groups can
## share one server: rooms, chat channels or sessions on one port. You decide who is in it:
## peers join with [method add_member] and leave with [method remove_member], or by
## disconnecting.
class_name LFSocketPeerGroup
extends RefCounted

## A member's connection closed (by either side, or by the server stopping). It has
## already left the group when this fires.
signal peer_disconnected(peer_id: int)
## A member sent a message (with `forward_messages`), or the owner handed one over with
## `deliver()`.
signal message_received(peer_id: int, data: Dictionary)

## `true`: every message a member sends the server is re-emitted as [signal message_received].
## `false`: you route messages yourself and pass a member's on with [method deliver].
var forward_messages := true

var _server: LFSocketServer
var _members: Dictionary = {}  # peer_id (int) -> true


## Creates an empty group over `server`. The group holds the server; the server does
## not hold the group, so dropping the group frees it.
func _init(server: LFSocketServer) -> void:
	_server = server
	_server.message_received.connect(_on_server_message)
	_server.peer_disconnected.connect(_on_server_peer_disconnected)


## Returns the server this group was created over.
func get_server() -> LFSocketServer:
	return _server


## Makes `peer_id` a member. Adding a member twice is harmless. The id isn't checked: an
## id the server doesn't know simply never receives anything.
func add_member(peer_id: int) -> void:
	_members[peer_id] = true


## Takes `peer_id` out of the group without disconnecting it; no signal is emitted. Does
## nothing for a peer that isn't a member.
func remove_member(peer_id: int) -> void:
	_members.erase(peer_id)


## Returns `true` if `peer_id` is a member.
func has_member(peer_id: int) -> bool:
	return _members.has(peer_id)


## Returns every member's id, in the order they were added, whether or not the server
## can send to them right now.
func member_ids() -> Array:
	return _members.keys()


## Lets go of every member without disconnecting anyone or emitting a signal. The
## server keeps running, and the group can take members again.
func stop() -> void:
	_members.clear()


## Returns `true` while the server is listening.
func is_listening() -> bool:
	return _server.is_listening()


## Returns the members the server can send to now: finished connecting and not being
## disconnected.
func connected_peer_ids() -> Array:
	var ids := []
	for peer_id: int in _server.connected_peer_ids():
		if _members.has(peer_id):
			ids.append(peer_id)
	return ids


## Returns a member's IP address; `''` for a peer outside the group.
func peer_address(peer_id: int) -> String:
	return _server.peer_address(peer_id) if _members.has(peer_id) else ''


## Sends `data` to a member like [method LFSocketServer.send_to]; returns
## `ERR_DOES_NOT_EXIST` for anyone outside the group.
func send_to(peer_id: int, data: Dictionary) -> Error:
	if !_members.has(peer_id):
		return ERR_DOES_NOT_EXIST
	return _server.send_to(peer_id, data)


## Sends already-encoded text to a member like [method LFSocketServer.send_text_to];
## returns `ERR_DOES_NOT_EXIST` for anyone outside the group.
func send_text_to(peer_id: int, text: String) -> Error:
	if !_members.has(peer_id):
		return ERR_DOES_NOT_EXIST
	return _server.send_text_to(peer_id, text)


## Sends `data` to every member in [method connected_peer_ids], encoding it only once.
func broadcast(data: Dictionary) -> void:
	var text := JSON.stringify(data)
	for peer_id: int in connected_peer_ids():
		_server.send_text_to(peer_id, text)


## Disconnects a member like [method LFSocketServer.disconnect_peer]: its queued messages
## go out first, and [signal peer_disconnected] fires once the close completes. A peer
## outside the group is ignored.
func disconnect_peer(peer_id: int) -> void:
	if _members.has(peer_id):
		_server.disconnect_peer(peer_id)


## Emits [signal message_received] for a member, as if it had just sent `data`, and
## returns `true`; returns `false` (emitting nothing) for a peer outside the group. With
## [member forward_messages] off, this is how you pass on the messages the group should see.
func deliver(peer_id: int, data: Dictionary) -> bool:
	if !_members.has(peer_id):
		return false
	message_received.emit(peer_id, data)
	return true


func _on_server_message(peer_id: int, data: Dictionary) -> void:
	if forward_messages and _members.has(peer_id):
		message_received.emit(peer_id, data)


func _on_server_peer_disconnected(peer_id: int) -> void:
	if _members.erase(peer_id):
		peer_disconnected.emit(peer_id)
