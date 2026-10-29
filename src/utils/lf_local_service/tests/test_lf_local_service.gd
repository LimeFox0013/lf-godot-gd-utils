extends GutTest

## Starts the Godot executable itself as the stand-in back end (tests/fixtures/health_server.gd:
## a tiny HTTP server), so nothing outside the engine is needed. Each test that starts a service
## stops it in after_each.

## Asks and pause for a start that must succeed: up to 30 s, which only a very busy computer needs.
const START_ATTEMPTS := 200
const START_DELAY_MS := 150

var service: LFLocalService
var _server_script := ""


func before_all():
	_server_script = ProjectSettings.globalize_path((get_script() as Script).resource_path.get_base_dir().path_join("fixtures/health_server.gd"))


func before_each():
	service = LFLocalService.new()


func after_each():
	if service != null:
		service.stop(0)


## A service that runs the stand-in; it answers /health after `health_after_ms`.
func _stand_in(health_after_ms := 0) -> LFLocalService:
	var args_for_port := func(chosen: int) -> PackedStringArray:
		return PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", _server_script, "--", str(chosen), str(health_after_ms)])
	return LFLocalService.new(OS.get_executable_path(), args_for_port)


# ---- the parts that need no program ----

func test_a_new_service_is_idle_with_no_urls():
	assert_eq(service.state, LFLocalService.State.IDLE)
	assert_eq(service.base_url, "")
	assert_eq(service.ws_url, "")
	assert_eq(service.health_url(), "")
	assert_false(service.is_running())
	assert_false(service.is_ready())
	assert_null(service.process)


func test_constructor_arguments_are_kept_and_defaults_applied():
	var custom := LFLocalService.new("/bin/app", Callable(), "/up", "localhost")
	assert_eq(custom.executable, "/bin/app")
	assert_eq(custom.health_path, "/up")
	assert_eq(custom.host, "localhost")
	assert_eq(service.health_path, LFLocalService.DEFAULT_HEALTH_PATH)
	assert_eq(service.host, LFLocalService.DEFAULT_HOST)


func test_urls_are_built_from_host_and_port():
	service.port = 4321
	assert_eq(service.base_url, "http://127.0.0.1:4321")
	assert_eq(service.ws_url, "ws://127.0.0.1:4321")
	assert_eq(service.health_url(), "http://127.0.0.1:4321/health")
	service.host = "::1"
	assert_eq(service.base_url, "http://[::1]:4321")


func test_a_missing_executable_fails_with_a_reason():
	var missing := LFLocalService.new("/no/such/program-xyz")
	watch_signals(missing)
	var started: bool = await missing.start(3, 10)
	assert_false(started)
	assert_eq(missing.state, LFLocalService.State.FAILED)
	assert_signal_emitted(missing, "failed")
	assert_signal_not_emitted(missing, "became_ready")
	var reason: String = get_signal_parameters(missing, "failed")[0]
	assert_string_contains(reason, "could not start")
	assert_push_error_count(2, "the class and LFProcess each report it")


func test_arguments_of_the_wrong_kind_fail_before_starting_anything():
	var wrong := LFLocalService.new("/bin/sh", func(_p: int): return 5)
	var started: bool = await wrong.start(1, 10)
	assert_false(started)
	assert_eq(wrong.state, LFLocalService.State.FAILED)
	assert_null(wrong.process)
	assert_push_error("args_for_port")


func test_stop_without_a_start_does_nothing():
	service.stop()
	assert_eq(service.state, LFLocalService.State.IDLE)


# ---- with the stand-in program ----

func test_start_waits_for_the_health_url_and_exposes_the_urls():
	service = _stand_in(0)
	watch_signals(service)
	var started: bool = await service.start(START_ATTEMPTS, START_DELAY_MS)
	assert_true(started, "the stand-in answered /health")
	assert_eq(service.state, LFLocalService.State.READY)
	assert_true(service.is_ready())
	assert_gt(service.port, 0)
	assert_eq(service.base_url, "http://127.0.0.1:%d" % service.port)
	assert_eq(service.ws_url, "ws://127.0.0.1:%d" % service.port)
	assert_signal_emitted(service, "became_ready")
	var echo: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, service.base_url + "/api/echo")
	assert_eq(echo.get("body_text"), "/api/echo", "the service is reachable on base_url")


func test_output_lines_of_the_program_are_forwarded():
	service = _stand_in(0)
	var lines: Array[String] = []
	service.output_received.connect(func(line: String): lines.append(line))
	assert_true(await service.start(START_ATTEMPTS, START_DELAY_MS))
	await get_tree().create_timer(0.3).timeout
	assert_true(lines.has("listening %d" % service.port), "the start-up line arrived: %s" % [lines])


func test_start_keeps_asking_while_the_health_url_says_not_yet():
	service = _stand_in(1500)
	var began := Time.get_ticks_msec()
	var started: bool = await service.start(START_ATTEMPTS, START_DELAY_MS)
	assert_true(started)
	assert_gte(Time.get_ticks_msec() - began, 1500, "it did not give up at the first 503")


func test_start_gives_up_after_max_attempts_and_stops_the_program():
	service = _stand_in(600000)
	watch_signals(service)
	var started: bool = await service.start(3, 50)
	assert_false(started)
	assert_eq(service.state, LFLocalService.State.FAILED)
	assert_signal_emitted(service, "failed")
	assert_false(service.is_running(), "the program was stopped")
	assert_push_error("did not answer")


func test_stop_ends_the_program_and_emits_exited():
	service = _stand_in(0)
	assert_true(await service.start(START_ATTEMPTS, START_DELAY_MS))
	var pid := service.process.get_pid()
	assert_gt(pid, 0)
	watch_signals(service)
	service.stop()
	assert_false(service.is_running())
	assert_false(LFOS.is_pid_alive(pid), "the process is gone")
	assert_eq(service.state, LFLocalService.State.STOPPED)
	await get_tree().create_timer(0.3).timeout
	assert_signal_emitted(service, "exited")


func test_start_while_ready_is_refused_without_touching_the_service():
	service = _stand_in(0)
	assert_true(await service.start(START_ATTEMPTS, START_DELAY_MS))
	var port := service.port
	assert_false(await service.start(1, 10))
	assert_push_error("already started")
	assert_true(service.is_ready())
	assert_eq(service.port, port)


func test_a_program_that_exits_early_fails_the_start_before_all_attempts():
	var shell := "cmd.exe" if OS.get_name() == "Windows" else "/bin/sh"
	var flag := "/C" if OS.get_name() == "Windows" else "-c"
	var quitter := LFLocalService.new(shell, func(_p: int): return PackedStringArray([flag, "exit 3"]))
	watch_signals(quitter)
	var began := Time.get_ticks_msec()
	var started: bool = await quitter.start(1000, 100)
	assert_false(started)
	assert_lt(Time.get_ticks_msec() - began, 30000, "did not wait for all 1000 attempts")
	assert_eq(quitter.state, LFLocalService.State.FAILED)
	assert_signal_emitted(quitter, "failed")
	assert_push_error("exited before")


func test_stop_during_the_wait_ends_the_start_without_failed():
	service = _stand_in(600000)
	watch_signals(service)
	var result := [null]
	var waiting := func() -> void: result[0] = await service.start(200, 100)
	waiting.call()
	await get_tree().create_timer(1.0).timeout
	service.stop(0)
	await get_tree().create_timer(0.5).timeout
	assert_eq(result[0], false)
	assert_signal_not_emitted(service, "failed")
	assert_eq(service.state, LFLocalService.State.STOPPED)


func test_the_program_is_stopped_when_the_service_is_freed():
	service = _stand_in(0)
	assert_true(await service.start(START_ATTEMPTS, START_DELAY_MS))
	var pid := service.process.get_pid()
	service = null
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	assert_false(LFOS.is_pid_alive(pid))
