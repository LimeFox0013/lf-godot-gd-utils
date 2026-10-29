extends SceneTree
## A stand-in for a bundled back end, run by the tests with the Godot executable itself:
##   godot --headless -s health_server.gd -- <port> [health_after_ms]
## It listens on 127.0.0.1:<port>, answers GET /health with 503 until `health_after_ms` have passed
## since it started and with 200 afterwards, answers any other path with 200 and the path as
## text, and prints "listening <port>" once it is bound.

var _server := TCPServer.new()
var _peers: Array[StreamPeerTCP] = []
var _health_after_ms := 0
var _started_ms := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if args.size() > 0 else 0
	_health_after_ms = int(args[1]) if args.size() > 1 else 0
	_started_ms = Time.get_ticks_msec()
	if _server.listen(port, "127.0.0.1") != OK:
		printerr("cannot listen on ", port)
		quit(2)
		return
	print("listening ", port)


func _process(_delta: float) -> bool:
	while _server.is_connection_available():
		_peers.append(_server.take_connection())
	for peer: StreamPeerTCP in _peers.duplicate():
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.erase(peer)
			continue
		if peer.get_available_bytes() <= 0:
			continue
		var request := peer.get_utf8_string(peer.get_available_bytes())
		var path := request.get_slice(" ", 1)
		var status := "200 OK"
		var body := path
		if path == "/health" and Time.get_ticks_msec() - _started_ms < _health_after_ms:
			status = "503 Service Unavailable"
			body = "starting"
		var head := "HTTP/1.1 %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, body.to_utf8_buffer().size()]
		peer.put_data((head + body).to_utf8_buffer())
		peer.disconnect_from_host()
		_peers.erase(peer)
	return false
