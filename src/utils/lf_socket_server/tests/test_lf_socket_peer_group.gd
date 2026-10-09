extends GutTest

## A peer group over a real server and real `WebSocketPeer` clients: members only are
## reached by sends and broadcasts, members' messages and closes are re-emitted, and the
## group never touches peers outside it.

var server: LFSocketServer
var group: LFSocketPeerGroup
var port: int
var clients: Array[WebSocketPeer] = []


func before_each():
	server = LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	port = server.get_local_port()
	group = LFSocketPeerGroup.new(server)
	clients = []


func after_each():
	for client in clients:
		client.close()
	server.stop()


func _wait_until(predicate: Callable, ms: int = 3000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		for client in clients:
			client.poll()
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


## Opens a client and returns its peer id on the server.
func _open_client() -> int:
	var before := server.connected_peer_ids()
	var client := WebSocketPeer.new()
	clients.append(client)
	client.connect_to_url('ws://127.0.0.1:%d' % port)
	assert_true(await _wait_until(func(): return client.get_ready_state() == WebSocketPeer.STATE_OPEN and server.connected_peer_ids().size() > before.size()), 'reached before the timeout')
	for peer_id: int in server.connected_peer_ids():
		if !before.has(peer_id):
			return peer_id
	return -1


func _received(client: WebSocketPeer) -> Array:
	var texts := []
	while client.get_available_packet_count() > 0:
		texts.append(client.get_packet().get_string_from_utf8())
	return texts


func test_members_are_added_listed_and_removed():
	group.add_member(3)
	group.add_member(5)

	assert_true(group.has_member(3))
	assert_eq(group.member_ids(), [3, 5])
	group.remove_member(3)
	assert_false(group.has_member(3))
	assert_eq(group.member_ids(), [5])


func test_broadcast_reaches_members_only():
	var inside := await _open_client()
	var outside := await _open_client()
	group.add_member(inside)

	group.broadcast({ 'type': 'hello' })

	var got := { 'inside': [], 'outside': [] }
	assert_true(await _wait_until(func():
		got['inside'].append_array(_received(clients[0]))
		got['outside'].append_array(_received(clients[1]))
		return !got['inside'].is_empty()
	), 'reached before the timeout')
	await get_tree().process_frame
	clients[1].poll()
	got['outside'].append_array(_received(clients[1]))
	assert_eq(got['inside'], [JSON.stringify({ 'type': 'hello' })])
	assert_eq(got['outside'], [], 'a peer outside the group hears nothing')
	assert_ne(outside, -1)


func test_sends_to_a_peer_outside_the_group_are_refused():
	var outside := await _open_client()

	assert_eq(group.send_to(outside, { 'type': 'x' }), ERR_DOES_NOT_EXIST)
	assert_eq(group.send_text_to(outside, '{}'), ERR_DOES_NOT_EXIST)


func test_send_to_a_member_goes_out_through_the_server():
	var inside := await _open_client()
	group.add_member(inside)

	assert_eq(group.send_to(inside, { 'type': 'x' }), OK)
	var got := []
	assert_true(await _wait_until(func(): got.append_array(_received(clients[0])); return !got.is_empty()))
	assert_eq(got, [JSON.stringify({ 'type': 'x' })])


func test_connected_peer_ids_are_the_members_the_server_can_send_to():
	var inside := await _open_client()
	await _open_client()
	group.add_member(inside)
	group.add_member(999)

	assert_eq(group.connected_peer_ids(), [inside], 'neither outsiders nor ids the server does not have')


func test_a_members_messages_are_re_emitted_and_an_outsiders_are_not():
	var inside := await _open_client()
	await _open_client()
	group.add_member(inside)
	var heard := []
	group.message_received.connect(func(peer_id: int, data: Dictionary): heard.append([peer_id, data]))

	clients[1].send_text(JSON.stringify({ 'type': 'outside' }))
	clients[0].send_text(JSON.stringify({ 'type': 'inside' }))

	assert_true(await _wait_until(func(): return !heard.is_empty()))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(heard, [[inside, { 'type': 'inside' }]])


func test_with_forwarding_off_only_delivered_messages_are_emitted():
	group.forward_messages = false
	var inside := await _open_client()
	group.add_member(inside)
	var heard := []
	var reached_server := []
	group.message_received.connect(func(peer_id: int, data: Dictionary): heard.append([peer_id, data]))
	server.message_received.connect(func(_peer_id: int, data: Dictionary): reached_server.append(data))

	clients[0].send_text(JSON.stringify({ 'type': 'raw' }))
	assert_true(await _wait_until(func(): return !reached_server.is_empty()), 'the server received it')
	await get_tree().process_frame
	assert_eq(heard, [], 'the owner routes messages itself')

	assert_true(group.deliver(inside, { 'type': 'routed' }))
	assert_false(group.deliver(inside + 100, { 'type': 'stranger' }), 'only to members')
	assert_eq(heard, [[inside, { 'type': 'routed' }]])


func test_a_member_closing_is_reported_once_and_leaves_the_group():
	var inside := await _open_client()
	var outside := await _open_client()
	group.add_member(inside)
	var gone := []
	group.peer_disconnected.connect(func(peer_id: int): gone.append(peer_id))

	clients[1].close()
	clients[0].close()

	assert_true(await _wait_until(func(): return server.connected_peer_ids().is_empty()))
	assert_eq(gone, [inside], 'an outsider closing is not the group\'s business')
	assert_false(group.has_member(inside))
	assert_ne(outside, -1)


func test_disconnect_peer_closes_a_member_after_its_last_message():
	var inside := await _open_client()
	group.add_member(inside)
	var gone := []
	group.peer_disconnected.connect(func(peer_id: int): gone.append(peer_id))

	group.send_to(inside, { 'type': 'bye' })
	group.disconnect_peer(inside)

	var got := []
	assert_true(await _wait_until(func():
		got.append_array(_received(clients[0]))
		return clients[0].get_ready_state() == WebSocketPeer.STATE_CLOSED and !gone.is_empty()
	))
	assert_eq(got, [JSON.stringify({ 'type': 'bye' })], 'the goodbye arrives before the close')
	assert_eq(gone, [inside])
	assert_false(group.has_member(inside))


func test_disconnect_peer_leaves_peers_outside_the_group_alone():
	var outside := await _open_client()

	group.disconnect_peer(outside)

	await _wait_until(func(): return false, 300)
	assert_eq(clients[0].get_ready_state(), WebSocketPeer.STATE_OPEN)
	assert_true(server.connected_peer_ids().has(outside))


func test_stop_lets_go_of_every_member_without_disconnecting_anyone():
	var inside := await _open_client()
	group.add_member(inside)
	var gone := []
	group.peer_disconnected.connect(func(peer_id: int): gone.append(peer_id))

	group.stop()

	assert_eq(group.member_ids(), [])
	await _wait_until(func(): return false, 300)
	assert_eq(clients[0].get_ready_state(), WebSocketPeer.STATE_OPEN)
	assert_eq(gone, [])
	assert_true(group.is_listening(), 'the server keeps running')


func test_the_server_stopping_reports_every_member():
	var inside := await _open_client()
	group.add_member(inside)
	var gone := []
	group.peer_disconnected.connect(func(peer_id: int): gone.append(peer_id))

	server.stop()

	assert_eq(gone, [inside])
	assert_false(group.is_listening())


func test_peer_address_is_known_for_members_only():
	var inside := await _open_client()
	var outside := await _open_client()
	group.add_member(inside)

	assert_eq(group.peer_address(inside), '127.0.0.1')
	assert_eq(group.peer_address(outside), '')


func test_a_dropped_group_is_freed_while_its_server_runs():
	var dropped := LFSocketPeerGroup.new(server)
	var ref: WeakRef = weakref(dropped)
	dropped = null

	assert_null(ref.get_ref(), 'the server\'s signals do not keep a group alive')


func test_send_text_to_a_member_delivers_the_text_as_it_is():
	var inside := await _open_client()
	group.add_member(inside)

	assert_eq(group.send_text_to(inside, '{"type":"pre-encoded"}'), OK)
	var got := []
	assert_true(await _wait_until(func(): got.append_array(_received(clients[0])); return !got.is_empty()))
	assert_eq(got, ['{"type":"pre-encoded"}'])


func test_a_peer_in_two_groups_is_re_emitted_by_both():
	var other := LFSocketPeerGroup.new(server)
	var peer := await _open_client()
	group.add_member(peer)
	other.add_member(peer)
	var heard := []
	group.message_received.connect(func(id, data): heard.append(['group', id, data.get('type')]))
	other.message_received.connect(func(id, data): heard.append(['other', id, data.get('type')]))
	group.peer_disconnected.connect(func(id): heard.append(['group closed', id]))
	other.peer_disconnected.connect(func(id): heard.append(['other closed', id]))

	clients[0].send_text(JSON.stringify({ 'type': 'hi' }))
	assert_true(await _wait_until(func(): return heard.size() == 2), 'reached before the timeout')
	clients[0].close()
	assert_true(await _wait_until(func(): return heard.size() == 4), 'reached before the timeout')

	assert_eq(heard, [['group', peer, 'hi'], ['other', peer, 'hi'], ['group closed', peer], ['other closed', peer]])
	assert_false(group.has_member(peer))
	assert_false(other.has_member(peer))


func test_get_server_is_the_server_the_group_was_made_over():
	assert_same(group.get_server(), server)


func test_adding_a_member_twice_keeps_one_entry_and_removing_a_stranger_is_harmless():
	group.add_member(3)
	group.add_member(3)
	group.remove_member(8)

	assert_eq(group.member_ids(), [3])
