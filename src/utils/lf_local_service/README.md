# LFLocalService

> Starts a bundled back-end program on a free port, waits until its health URL answers, gives you its `http://` and `ws://` addresses, and stops it when you are done.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_local_service.gd` |
| **Tests** | `tests/test_lf_local_service.gd`, `tests/fixtures/health_server.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFProcess`, `LFHttp`, `LFSocketServer`, `LFUrl`, `LFUtils`, `LFLogger` |

## When to use it

Use it when your app ships a helper program that talks over the network on this computer:
a local language-model server, a small web service, a database. Every such app does the
same dance: find a port nobody uses, start the program with that port, wait until it is
really up, and only then connect. `await service.start()` does all of it and returns `true`
when the program answered. For running a program and reading its output without waiting
for a web address, use `LFProcess` alone; for sending requests afterwards, `LFHttp` (one
answer) or `LFSocket` (a connection that stays open).

## Step by step

Goal: start a small web server that comes with your game and print its address. This needs
a program that listens on the port you give it and answers `GET /health` with a 2xx status;
the example uses a placeholder name, `my-backend`.

1. Put the program next to your game's files, for example `backend/my-backend` (on Windows `my-backend.exe`).
2. In the Godot editor choose *Scene → New Scene*, pick **Other Node → Node**, press *Create*.
3. Select the node, click *Attach Script*, press *Create*, and replace the contents with:

   ```gdscript
   extends Node

   var service: LFLocalService


   func _ready() -> void:
   	var program := ProjectSettings.globalize_path("res://backend/my-backend")
   	# The program is told which port to use through its command line.
   	service = LFLocalService.new(program, func(port: int): return ["--port", str(port)])
   	if await service.start():
   		print("the back end is up at ", service.base_url)
   	else:
   		print("the back end did not start")
   ```
4. Change `"--port"` to whatever your program expects. If its health address is not `/health`, set `service.health_path = "/status"` (your path) before `start()`.
5. Press **F6**. In the *Output* panel you should see the address, for example `http://127.0.0.1:52341`; the port differs every run. A program inside `res://` only runs from a project folder: in an exported game copy it next to the executable and use `OS.get_executable_path().get_base_dir()` instead.

## API

Everything the class offers; you only need the rows used above to get started. A *signal* is an event other code can listen to: `object.signal_name.connect(my_function)`.

| Member | Signature | Description |
|---|---|---|
| `new` | `LFLocalService.new(executable_path := '', port_arguments := Callable(), health := '/health', service_host := '127.0.0.1')` | Sets `executable`, `args_for_port`, `health_path`, `host`. |
| `start` | `start(max_attempts := 30, delay_ms := 500) -> bool` | Coroutine (`await`). Picks a free port, starts the program, asks the health URL until a 2xx answer. True after `became_ready`. False after `failed` (no port, would not start, exited early, never answered; the program is stopped). False at once, with an error, when already starting or ready. |
| `stop` | `stop(grace_ms := 2000) -> void` | Asks the program to exit and kills it after `grace_ms`; 0 or less kills at once. Blocks for up to that time. Ends a `start` that is still waiting (it returns false, no `failed`). |
| `is_running` | `is_running() -> bool` | The program is running (it may not have answered yet). |
| `is_ready` | `is_ready() -> bool` | The health URL answered and the program is still running. |
| `state` | `var state: LFLocalService.State` | `IDLE`, `STARTING`, `READY`, `FAILED` or `STOPPED`. |
| `base_url` / `ws_url` / `health_url()` | `String` | `http://host:port`, `ws://host:port` and the health address; `''` before the first `start`. An IPv6 host is put in brackets. |
| `port` | `var port: int` | The port picked by the last `start`; 0 before one. |
| `process` | `var process: LFProcess` | The runner, for the pid or `write_line`. A new one for every `start`; null before the first. |
| `executable`, `args_for_port`, `health_path`, `host`, `env`, `request_timeout_ms` | properties | Change them before `start`. `args_for_port(port)` returns a `PackedStringArray` or an `Array` of strings; `env` adds environment variables for the program. |
| `became_ready` | `signal became_ready` | The health URL answered with 2xx. |
| `failed` | `signal failed(reason: String)` | `start` gave up. |
| `exited` | `signal exited(code: int)` | The program ended (`LFProcess.STOPPED`, -1, when it was stopped). |
| `output_received` / `error_output_received` | `signal output_received(line: String)` | One non-empty line the program printed to stdout / stderr, without its line ending. |
| `DEFAULT_HEALTH_PATH`, `DEFAULT_HOST`, `DEFAULT_MAX_ATTEMPTS`, `DEFAULT_DELAY_MS`, `DEFAULT_REQUEST_TIMEOUT_MS` | constants | The defaults above (`/health`, `127.0.0.1`, 30, 500 ms, 2000 ms). |

## Usage

```gdscript
# A manager node: start the back end with the game, ask it something, stop it on quit.
extends Node

var service := LFLocalService.new(
	OS.get_executable_path().get_base_dir().path_join("bin/my-backend"),
	func(port: int): return ["--port", str(port), "--quiet"],
)


func _ready() -> void:
	service.health_path = "/status"
	service.output_received.connect(func(line: String): print("[backend] ", line))
	service.failed.connect(func(reason: String): push_warning("back end: " + reason))
	service.exited.connect(func(code: int): print("back end ended with code ", code))
	if await service.start(40, 250):   # up to 40 asks, a quarter of a second apart
		var answer := await LFHttp.request(HTTPClient.METHOD_GET, service.base_url + "/api/hello")
		print(answer.body_text)
		# For a live connection use service.ws_url with LFSocket.


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		service.stop()
```

## Notes

- The port is free when it is picked (`LFSocketServer.free_port`), not reserved: another program could take it before yours binds it. If your program fails to bind, `start` reports that it exited early, or never answered.
- A freed `LFLocalService` ends its program (the `LFProcess` it holds does that when freed), but call `stop()` on quit anyway: it asks politely first.
- `start` treats only a 2xx answer to a GET as "up"; a redirect, 3xx, 4xx or 5xx means "not yet". Each ask has its own time limit, `request_timeout_ms`.
- The wait is at most `max_attempts` asks and the pauses between them (the last ask is not followed by a pause). Reading `state` or the signals is enough to follow it; nothing else polls.
- The back end runs with the same rights as your game and binds `host` (`127.0.0.1`, this computer only, by default). The class does not secure the connection: anything else running on the computer can connect to the port.
- The program's output lines (stdout, stderr) are forwarded by `output_received` and `error_output_received`, connected before the program starts, so start-up lines are not missed. For more control (the pid, `write_line`) use `process`, which exists once `start` has begun.
- Desktop only, like `LFProcess`. The tests start the Godot executable itself, running a small script that serves `/health`; they have been run on macOS only.
