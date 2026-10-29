## Starts a helper program that serves HTTP (and maybe WebSocket) on a free port, waits until it
## answers, and stops it with the game.
##
## An app that ships a local back end (a language-model server, a small web service, a
## database) has the same steps every time: pick a free port, start the program with that port
## on its command line, ask a health URL until it answers, then hand out the `http://` and
## `ws://` addresses. This class does those steps with `LFSocketServer.free_port`,
## `LFProcess` and `LFHttp`. `await service.start()` is `true` once the health URL answered
## with a 2xx status. Stopping it, or freeing the object, ends the program.
class_name LFLocalService
extends RefCounted


## Where the service is in its life: `IDLE` before `start`, `STARTING` while it waits for the
## health URL, `READY` once it answered, `FAILED` when the start did not work, `STOPPED` after
## `stop()` or when a ready program exited.
enum State { IDLE, STARTING, READY, FAILED, STOPPED }

## The health path asked when none is given.
const DEFAULT_HEALTH_PATH := '/health'
## The host the program listens on when none is given: this computer only.
const DEFAULT_HOST := '127.0.0.1'
## How many times `start` asks the health URL before giving up.
const DEFAULT_MAX_ATTEMPTS := 30
## How long `start` waits between two health requests, in milliseconds.
const DEFAULT_DELAY_MS := 500
## How long one health request may take, in milliseconds.
const DEFAULT_REQUEST_TIMEOUT_MS := 2000

## Emitted once when the health URL answered with a 2xx status.
signal became_ready
## Emitted when `start` gives up, with a short English reason.
signal failed(reason: String)
## Emitted when the program ended; `code` is its exit code, or `LFProcess.STOPPED` (-1) when it
## was stopped by `stop()` or by this class giving up.
signal exited(code: int)

## One non-empty line the program printed to its standard output (no line ending).
signal output_received(line: String)
## One non-empty line the program printed to its standard error (no line ending).
signal error_output_received(line: String)

## The program to run (a path, or a name found on the PATH).
var executable: String
## Called as `args_for_port(port: int)` and returns the command line (a `PackedStringArray`, or
## an `Array` of strings) for the program; for example `func(port): return ["--port", str(port)]`.
## Empty: the program gets no arguments.
var args_for_port: Callable
## Path of the URL asked to find out whether the program is up, starting with `/`.
var health_path: String
## Host the program is expected to listen on, and the one in `base_url` and `ws_url`.
var host: String
## Extra environment variables for the program (name to value), added to this process's own.
var env: Dictionary = {}
## How long one health request may take, in milliseconds.
var request_timeout_ms := DEFAULT_REQUEST_TIMEOUT_MS
## The runner of the program, for its pid or `write_line`. A fresh one is made by every
## `start`; null before the first.
var process: LFProcess = null
## The port chosen by the last `start`; 0 before one.
var port := 0
## Where the service is now.
var state: State = State.IDLE
## `http://host:port` once a port is chosen; `''` before the first `start`.
var base_url: String:
	get:
		return LFUrl.for_host('http', host, port) if port > 0 else ''
## `ws://host:port` once a port is chosen; `''` before the first `start`.
var ws_url: String:
	get:
		return LFUrl.for_host('ws', host, port) if port > 0 else ''

var _log := LFLogger.new(['LFLocalService'])
# Bumped by every start, so a start that is still waiting can tell a newer one replaced it.
var _generation := 0


## A service for `executable_path`; see the properties of the same names.
func _init(executable_path: String = '', port_arguments: Callable = Callable(), health: String = DEFAULT_HEALTH_PATH, service_host: String = DEFAULT_HOST) -> void:
	executable = executable_path
	args_for_port = port_arguments
	health_path = health
	host = service_host


## The full health address (`base_url` plus `health_path`); `''` before the first `start`.
func health_url() -> String:
	return base_url + health_path if port > 0 else ''


## True while the program is running (it may not have answered yet).
func is_running() -> bool:
	return process != null and process.is_running()


## True once the health URL answered and the program has not ended since.
func is_ready() -> bool:
	return state == State.READY and is_running()


## Picks a free port, starts the program and asks the health URL up to `max_attempts` times,
## `delay_ms` apart, until it answers with a 2xx status (use `await`). Returns true once it did,
## after emitting `became_ready`. Otherwise stops the program, sets the state to `FAILED`, emits
## `failed` with the reason and returns false: no port, the program would not start, it exited
## early, or it never answered. Returns false at once, without touching a running service, when
## one is already starting or ready (call `stop()` first). A `stop()` during the wait ends the wait
## and returns false without `failed`. Needs a running SceneTree.
## The port is free when picked, but another program could take it before yours binds it.
func start(max_attempts := DEFAULT_MAX_ATTEMPTS, delay_ms := DEFAULT_DELAY_MS) -> bool:
	if state == State.STARTING or is_ready():
		_log.error('already started; call stop() first')
		return false
	var tree := LFUtils.tree_root
	if tree == null:
		return _fail('there is no running SceneTree')
	_generation += 1
	var generation := _generation
	port = 0
	process = null
	state = State.STARTING
	var chosen := LFSocketServer.free_port(host)
	if chosen < 0:
		return _fail('no free port on %s' % host)
	port = chosen
	var arguments: Variant = _arguments_for(chosen)
	if arguments == null:
		return _fail('args_for_port must return a PackedStringArray or an Array of strings')
	process = LFProcess.new()
	process.exited.connect(_on_process_exited.bind(generation))
	process.output_received.connect(_on_process_output)
	process.error_output_received.connect(_on_process_error_output)
	if not process.start(executable, arguments, env):
		return _fail('could not start %s' % executable)
	var attempts := maxi(max_attempts, 1)
	for attempt in attempts:
		var answered := await _health_ok()
		if _superseded(generation):
			return false
		if answered:
			state = State.READY
			became_ready.emit()
			return true
		if not process.is_running():
			return _fail('%s exited before it answered %s' % [executable, health_url()])
		if attempt < attempts - 1:
			await LFUtils.timeout(delay_ms)
			if _superseded(generation):
				return false
	return _fail('%s did not answer after %d attempts' % [health_url(), attempts])


## Ends the program: asks it to exit, waits up to `grace_ms` (0 or less: no waiting, it is killed
## at once), then kills it. Blocks the caller for up to that time. Does nothing when nothing is
## running. Ends a `start` that is still waiting. `exited` is emitted with the code.
func stop(grace_ms: int = LFProcess.DEFAULT_TERMINATE_GRACE_MS) -> void:
	if process == null:
		return
	if grace_ms > 0:
		process.terminate(grace_ms)
	else:
		process.stop()
	if state == State.STARTING or state == State.READY:
		state = State.STOPPED


# Whether a start that began as `generation` has been replaced by a newer start or ended by stop().
func _superseded(generation: int) -> bool:
	return generation != _generation or state != State.STARTING


func _arguments_for(chosen_port: int) -> Variant:
	if not args_for_port.is_valid():
		return PackedStringArray()
	var result: Variant = args_for_port.call(chosen_port)
	if typeof(result) == TYPE_PACKED_STRING_ARRAY:
		return result
	if typeof(result) == TYPE_ARRAY:
		for item: Variant in result:
			if typeof(item) != TYPE_STRING:
				return null
		return PackedStringArray(result)
	return null


func _health_ok() -> bool:
	var answer: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, health_url(), {}, '', request_timeout_ms)
	return answer.get('ok', false) and int(answer.get('status', 0)) >= 200 and int(answer.get('status', 0)) < 300


func _fail(reason: String) -> bool:
	_log.error(reason)
	if process != null:
		process.stop()
	state = State.FAILED
	failed.emit(reason)
	return false


func _on_process_exited(_pid: int, code: int, generation: int) -> void:
	if generation != _generation:
		return
	if state == State.READY:
		state = State.STOPPED
	exited.emit(code)


func _on_process_output(_pid: int, line: String) -> void:
	output_received.emit(line)


func _on_process_error_output(_pid: int, line: String) -> void:
	error_output_received.emit(line)
