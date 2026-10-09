extends GutTest

## Spawns real /bin/sh children on the local machine (Unix only; no network). Every test
## ends its children: after_each stops the instance, and tests that leave a grandchild
## behind wait for it to finish.

## The line cap the long-line test sets, in bytes.
const LINE_CAP := 1000
## The long line it prints: two full pieces and a half one.
const LONG_LINE_BYTES := 2500
## The pieces that line arrives in.
const LONG_LINE_PIECES := [LINE_CAP, LINE_CAP, LONG_LINE_BYTES - 2 * LINE_CAP]
## Lines printed before the blank line in the delivery-order test.
const SEQ_LINES := 2000
## The exit code of a child killed by SIGTERM.
const SIGTERM := 15

var lf_process: LFProcess
var _temp_files: Array[String] = []


## The children are /bin/sh scripts, so the file is skipped on Windows (see
## test_lf_process_windows.gd for the cmd.exe equivalents).
func should_skip_script() -> bool:
	return OS.get_name() == "Windows"


func before_each():
	lf_process = LFProcess.new()


func after_each():
	lf_process.stop()
	for path in _temp_files:
		DirAccess.remove_absolute(path)
	_temp_files.clear()


func _wait_for_signal(obj: Object, signal_name: String, max_ms := 3000) -> bool:
	var deadline := Time.get_ticks_msec() + max_ms
	var fired := [false]
	obj.connect(signal_name, func(...args): fired[0] = true, CONNECT_ONE_SHOT)
	while not fired[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return fired[0]


func _wait_until(predicate: Callable, max_ms := 3000) -> bool:
	var deadline := Time.get_ticks_msec() + max_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return predicate.call()


func _collect(signal_name: String) -> Array:
	var lines := []
	lf_process.connect(signal_name, func(_pid: int, line: String): lines.append(line))
	return lines


func _temp_script(body: String, executable := true) -> String:
	var path := OS.get_cache_dir().path_join('lf_process_test_%d_%d.sh' % [OS.get_process_id(), Time.get_ticks_usec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('#!/bin/sh\n' + body + '\n')
	file.close()
	if executable:
		FileAccess.set_unix_permissions(path, 0b111_101_101)
	_temp_files.append(path)
	return path


# ---- lifecycle ----

func test_started_and_exited_fire_for_a_quickly_exiting_process():
	watch_signals(lf_process)
	assert_true(lf_process.start("/bin/sh", ["-c", "exit 0"]))

	assert_true(await _wait_for_signal(lf_process, "exited"), "exited never fired")
	assert_signal_emitted(lf_process, "started")


func test_exited_reports_the_exit_code():
	var codes := []
	lf_process.exited.connect(func(_pid: int, code: int): codes.append(code))
	lf_process.start("/bin/sh", ["-c", "exit 3"])

	assert_true(await _wait_until(func(): return codes.size() == 1))
	assert_eq(codes, [3])


func test_stop_ends_a_running_process():
	lf_process.start("/bin/sh", ["-c", "sleep 30"])
	assert_true(lf_process.is_running())

	lf_process.stop()

	assert_false(lf_process.is_running())
	assert_eq(lf_process.get_pid(), -1)


func test_exited_after_stop_reports_the_pid_and_the_stopped_code():
	var exits := []
	lf_process.exited.connect(func(pid: int, code: int): exits.append([pid, code]))
	lf_process.start("/bin/sh", ["-c", "sleep 30"])
	var pid := lf_process.get_pid()

	lf_process.stop()

	assert_true(await _wait_until(func(): return exits.size() == 1))
	assert_eq(exits, [[pid, LFProcess.STOPPED]])


func test_pid_is_cleared_once_the_exit_is_delivered():
	lf_process.start("/bin/sh", ["-c", "exit 0"])
	assert_gt(lf_process.get_pid(), 0)

	assert_true(await _wait_for_signal(lf_process, "exited"))

	assert_eq(lf_process.get_pid(), -1)
	assert_false(lf_process.is_running())


func test_restart_now_replaces_a_live_process():
	lf_process.start("/bin/sh", ["-c", "sleep 4"])
	var old_pid := lf_process.get_pid()

	assert_true(lf_process.restart_now())

	assert_ne(lf_process.get_pid(), old_pid)
	assert_false(LFOS.is_pid_alive(old_pid), "the replaced process must be gone")


func test_restart_now_before_any_start_spawns_nothing():
	assert_false(lf_process.restart_now())


func test_start_on_a_running_instance_replaces_the_process():
	lf_process.start("/bin/sh", ["-c", "sleep 4"])
	var old_pid := lf_process.get_pid()

	lf_process.start("/bin/sh", ["-c", "sleep 4"])

	assert_false(LFOS.is_pid_alive(old_pid), "the replaced process must be gone")
	assert_true(lf_process.is_running())


func test_dropping_a_running_process_without_stop_ends_its_child():
	var dropped := LFProcess.new()
	assert_true(dropped.start('/bin/sleep', ['30']))
	var child := dropped.get_pid()
	assert_true(LFOS.is_pid_alive(child))

	var watch: WeakRef = weakref(dropped)
	dropped = null

	assert_null(watch.get_ref(), 'freed: no worker holds it')
	assert_false(LFOS.is_pid_alive(child), 'the child went with it')


func test_stop_does_not_wait_for_a_grandchild_holding_the_pipe():
	var lines := _collect("output_received")
	lf_process.start("/bin/sh", ["-c", "sleep 30 & echo $!; wait"])
	assert_true(await _wait_until(func(): return lines.size() == 1), "the grandchild pid never arrived")
	var grandchild := int(lines[0])

	lf_process.stop()

	# A stop() that waited for the pipe to close would only return once the grandchild
	# had exited, 30 s on: it returned while it still holds the pipe.
	assert_true(LFOS.is_pid_alive(grandchild), "stop() must not block on a reader the grandchild keeps alive")
	OS.kill(grandchild)
	# The detached readers finish once the grandchild exits; after_each's stop() joins them.
	assert_true(await _wait_until(func(): return not LFOS.is_pid_alive(grandchild), 5000))


# ---- starting ----

func test_a_missing_binary_does_not_start():
	watch_signals(lf_process)
	assert_false(lf_process.start("/nonexistent/binary-xyz"))
	assert_false(lf_process.start("no-such-command-xyz-123"))
	assert_signal_not_emitted(lf_process, "started")
	assert_eq(lf_process.get_pid(), -1)
	assert_push_error_count(2, "each refusal is logged")


func test_a_refused_start_leaves_no_earlier_command_for_restart_now():
	assert_true(lf_process.start("/bin/sh", ["-c", "sleep 30"]))
	assert_false(lf_process.start("/nonexistent/binary-xyz"))
	assert_push_error("not an executable")

	assert_false(lf_process.restart_now(), "the refused start replaced the saved command")
	assert_false(lf_process.is_running())


func test_a_file_without_execute_permission_does_not_start():
	assert_false(lf_process.start(_temp_script("exit 0", false)))
	assert_push_error("not an executable")


func test_a_bare_command_name_is_found_on_path():
	var lines := _collect("output_received")
	assert_true(lf_process.start("echo", ["from-path"]))
	assert_true(await _wait_until(func(): return lines.has("from-path")))


func test_an_invalid_environment_name_does_not_start():
	assert_false(lf_process.start("/bin/sh", ["-c", "exit 0"], {"A=B": "x"}))
	assert_false(lf_process.start("/bin/sh", ["-c", "exit 0"], {"": "x"}))
	assert_push_error_count(2, "each refusal is logged")


func test_env_reaches_the_child_without_leaking_into_this_process():
	var lines := _collect("output_received")
	lf_process.start("/bin/sh", ["-c", "echo value=$LF_PROCESS_TEST_VAR"], {"LF_PROCESS_TEST_VAR": "child-only"})

	assert_true(await _wait_until(func(): return lines.has("value=child-only")))
	assert_false(OS.has_environment("LF_PROCESS_TEST_VAR"), "the parent's environment must be restored")


func test_changing_the_env_dictionary_after_start_does_not_change_a_restart():
	var lines := _collect("output_received")
	var env := {"LF_PROCESS_TEST_VAR": "first"}
	lf_process.start("/bin/sh", ["-c", "echo value=$LF_PROCESS_TEST_VAR"], env)
	assert_true(await _wait_until(func(): return lines.has("value=first")))
	env["LF_PROCESS_TEST_VAR"] = "second"

	lf_process.restart_now()

	assert_true(await _wait_until(func(): return lines.size() >= 2))
	assert_eq(lines[1], "value=first", "start() keeps its own copy of env")


func test_changing_the_args_array_after_start_does_not_change_a_restart():
	var lines := _collect("output_received")
	var args := PackedStringArray(["-c", "echo first"])
	lf_process.start("/bin/sh", args)
	assert_true(await _wait_until(func(): return lines.has("first")))
	args[1] = "echo second"

	lf_process.restart_now()

	assert_true(await _wait_until(func(): return lines.size() >= 2))
	assert_eq(lines[1], "first", "start() keeps its own copy of args")


func test_no_line_arrives_after_stop_even_if_more_were_already_queued():
	var lines := []
	lf_process.output_received.connect(func(_pid: int, line: String):
		lines.append(line)
		if lines.size() == 3:
			lf_process.stop())
	lf_process.start("/bin/sh", ["-c", "i=0; while [ $i -lt 3000 ]; do echo $i; i=$((i+1)); done"])
	assert_true(await _wait_until(func(): return lines.size() >= 3))

	await wait_process_frames(10)

	assert_eq(lines.size(), 3, "stop() ends delivery at once")


func test_set_uid_changes_the_log_prefix_id():
	lf_process.set_uid("my-proc")
	lf_process.start("/nonexistent/binary-xyz")
	assert_push_error("(my-proc)", "the log prefix carries the new uid")

	var named := LFProcess.new("ctor-id")
	named.start("/nonexistent/binary-xyz")
	assert_push_error("(ctor-id)", "a uid passed to new() goes through set_uid")


func test_run_shell_runs_the_command_line_through_a_shell():
	var lines := _collect("output_received")
	assert_true(lf_process.run_shell("echo shell-$((1+2)) | tr a-z A-Z"))

	assert_true(await _wait_until(func(): return lines.has("SHELL-3")), "arithmetic and the pipe are the shell's")


# ---- output ----

func test_stdout_and_stderr_arrive_on_their_own_signals():
	var out := _collect("output_received")
	var err := _collect("error_output_received")
	lf_process.start("/bin/sh", ["-c", "echo to-out; echo to-err 1>&2"])

	assert_true(await _wait_for_signal(lf_process, "exited"))
	assert_eq(out, ["to-out"])
	assert_eq(err, ["to-err"])


func test_lines_after_a_blank_line_are_delivered_before_exit():
	var lines := _collect("output_received")
	var at_exit := []
	lf_process.exited.connect(func(_pid: int, _code: int): at_exit.append(lines.size()))
	lf_process.start("/bin/sh", ["-c", "seq 1 %d; echo; echo tail-line" % SEQ_LINES])

	assert_true(await _wait_until(func(): return at_exit.size() == 1, 5000))
	assert_eq(at_exit[0], SEQ_LINES + 1, "every line is delivered before exited")
	assert_eq(lines[-1], "tail-line")


func test_a_last_line_without_a_newline_is_delivered():
	var lines := _collect("output_received")
	lf_process.start("/bin/sh", ["-c", "printf 'a\\r\\nno-newline'"])

	assert_true(await _wait_for_signal(lf_process, "exited"))
	assert_eq(lines, ["a", "no-newline"], "a CRLF ending is stripped too")


func test_a_line_longer_than_max_line_bytes_arrives_in_pieces():
	lf_process.max_line_bytes = LINE_CAP
	var lines := _collect("output_received")
	lf_process.start("/bin/sh", ["-c", "head -c %d /dev/zero | tr '\\000' a; echo" % LONG_LINE_BYTES])

	assert_true(await _wait_for_signal(lf_process, "exited"))
	assert_eq(lines.map(func(line: String): return line.length()), LONG_LINE_PIECES)


func test_a_split_never_cuts_a_utf8_character():
	lf_process.max_line_bytes = 5
	var lines := _collect("output_received")
	lf_process.start("/bin/sh", ["-c", "printf '\\303\\251\\303\\251\\303\\251\\n'"])	# "ééé", 6 bytes

	assert_true(await _wait_for_signal(lf_process, "exited"))
	assert_eq(lines, ["éé", "é"])


func test_invalid_utf8_becomes_replacement_characters():
	var lines := _collect("output_received")
	lf_process.start("/bin/sh", ["-c", "printf 'a\\377b\\n'"])

	assert_true(await _wait_for_signal(lf_process, "exited"))
	assert_eq(lines, ["a�b"])


func test_every_line_arrives_in_order_when_the_backlog_is_capped():
	lf_process.max_pending_lines = 5
	var lines := _collect("output_received")
	lf_process.start("/bin/sh", ["-c", "seq 1 300"])

	assert_true(await _wait_for_signal(lf_process, "exited", 20000))
	assert_eq(lines.size(), 300)
	assert_eq(lines[0], "1")
	assert_eq(lines[-1], "300")


func test_without_capture_the_child_runs_without_pipes():
	lf_process.capture_output = false
	var lines := _collect("output_received")
	var codes := []
	lf_process.exited.connect(func(_pid: int, code: int): codes.append(code))
	assert_true(lf_process.start("/bin/sh", ["-c", "exit 5"]))
	assert_false(lf_process.write_line("ignored"))

	assert_true(await _wait_until(func(): return codes.size() == 1))
	assert_eq(codes, [5])
	assert_eq(lines, [])


# ---- stdin ----

func test_write_line_reaches_the_childs_stdin():
	var lines := _collect("output_received")
	lf_process.start("/bin/cat")

	assert_true(lf_process.write_line("echo me"))
	assert_true(await _wait_until(func(): return lines.has("echo me")), "cat echoes its stdin")


func test_write_line_without_a_running_child_fails():
	assert_false(lf_process.write_line("nobody listening"))
	lf_process.start("/bin/sh", ["-c", "exit 0"])
	assert_true(await _wait_for_signal(lf_process, "exited"))
	assert_false(lf_process.write_line("too late"))


# ---- terminate ----

func test_terminate_lets_the_child_exit_on_its_own_terms():
	var lines := _collect("output_received")
	var codes := []
	lf_process.exited.connect(func(_pid: int, code: int): codes.append(code))
	lf_process.start("/bin/sh", ["-c", "trap 'exit 7' TERM; echo ready; while :; do sleep 0.05; done"])
	assert_true(await _wait_until(func(): return lines.has("ready")))

	lf_process.terminate(3000)

	assert_true(await _wait_until(func(): return codes.size() == 1))
	assert_eq(codes, [7])


func test_terminate_kills_a_child_that_ignores_the_request():
	var lines := _collect("output_received")
	var codes := []
	lf_process.exited.connect(func(_pid: int, code: int): codes.append(code))
	lf_process.start("/bin/sh", ["-c", "trap '' TERM; echo ready; exec sleep 30"])
	assert_true(await _wait_until(func(): return lines.has("ready")))
	var pid := lf_process.get_pid()

	lf_process.terminate(200)

	assert_false(LFOS.is_pid_alive(pid))
	assert_true(await _wait_until(func(): return codes.size() == 1))
	assert_eq(codes, [LFProcess.STOPPED])


# ---- restarts ----

func test_auto_restart_is_off_by_default():
	assert_false(LFProcess.new().auto_restart)
	watch_signals(lf_process)
	lf_process.start("/bin/sh", ["-c", "exit 0"])
	assert_true(await _wait_for_signal(lf_process, "exited"))
	await wait_seconds(0.3)
	assert_signal_not_emitted(lf_process, "restarted")


func test_auto_restart_numbers_attempts_and_stops_at_the_limit():
	lf_process.auto_restart = true
	lf_process.max_restart_attempts = 2
	lf_process.restart_backoff_ms = 20
	var attempts := []
	var exits := [0]
	lf_process.restarted.connect(func(_pid: int, attempt: int): attempts.append(attempt))
	lf_process.exited.connect(func(_pid: int, _code: int): exits[0] += 1)
	lf_process.start("/bin/sh", ["-c", "exit 0"])

	assert_true(await _wait_until(func(): return exits[0] == 3, 5000), "three runs in all")
	await wait_seconds(0.3)
	assert_eq(attempts, [1, 2])


func test_the_restart_wait_is_capped_by_max_backoff_ms():
	lf_process.auto_restart = true
	lf_process.max_restart_attempts = 1
	lf_process.restart_backoff_ms = 600000
	lf_process.max_backoff_ms = 50

	lf_process.start("/bin/sh", ["-c", "exit 0"])

	assert_true(await _wait_for_signal(lf_process, "restarted", 3000), "the cap, not the backoff, sets the wait")


func test_stop_disables_a_pending_auto_restart():
	lf_process.auto_restart = true
	lf_process.restart_backoff_ms = 100
	watch_signals(lf_process)
	lf_process.start("/bin/sh", ["-c", "sleep 30"])

	lf_process.stop()
	assert_true(await _wait_for_signal(lf_process, "exited"))
	await wait_seconds(0.4)

	assert_signal_not_emitted(lf_process, "restarted")


func test_stop_in_the_exited_handler_cancels_an_already_queued_restart():
	lf_process.auto_restart = true
	lf_process.restart_backoff_ms = 0
	watch_signals(lf_process)
	lf_process.exited.connect(func(_pid: int, _code: int): lf_process.stop())
	lf_process.start("/bin/sh", ["-c", "exit 0"])

	assert_true(await _wait_for_signal(lf_process, "exited"))
	await wait_seconds(0.2)

	assert_signal_not_emitted(lf_process, "restarted")
	assert_false(lf_process.is_running())


func test_start_while_a_restart_is_pending_leaves_one_child_that_stop_ends():
	lf_process.auto_restart = true
	lf_process.restart_backoff_ms = 1500
	var started := []
	lf_process.started.connect(func(p: int): started.append(p))
	lf_process.start("/bin/sh", ["-c", "exit 1"])
	assert_true(await _wait_for_signal(lf_process, "exited"), "the first child never exited")

	lf_process.start("/bin/sleep", ["41.21"])
	var second := lf_process.get_pid()
	await wait_seconds(2.0)	# past the first child's restart wait
	lf_process.stop()

	assert_false(LFOS.is_pid_alive(second), "the child start() made ends with stop()")
	assert_eq(started.size(), 2, "the superseded restart never runs")
	OS.execute("pkill", ["-f", "sleep 41.21"])


func test_turning_auto_restart_off_cancels_a_pending_restart():
	lf_process.auto_restart = true
	lf_process.restart_backoff_ms = 300
	watch_signals(lf_process)
	lf_process.start("/bin/sh", ["-c", "exit 0"])

	assert_true(await _wait_for_signal(lf_process, "exited"), "the process never exited")
	lf_process.auto_restart = false
	await wait_seconds(0.8)

	assert_signal_not_emitted(lf_process, "restarted")
	assert_false(lf_process.is_running())


func test_lowering_max_restart_attempts_cancels_a_pending_restart():
	lf_process.auto_restart = true
	lf_process.restart_backoff_ms = 300
	watch_signals(lf_process)
	lf_process.start("/bin/sh", ["-c", "exit 0"])

	assert_true(await _wait_for_signal(lf_process, "exited"), "the process never exited")
	lf_process.max_restart_attempts = 0
	await wait_seconds(0.8)

	assert_signal_not_emitted(lf_process, "restarted")


func test_a_restart_that_cannot_spawn_reports_restart_failed():
	# The command removes itself, so it is gone before any restart.
	var script := _temp_script('rm -- "$0"\nexit 0')
	lf_process.auto_restart = true
	lf_process.restart_backoff_ms = 200
	watch_signals(lf_process)
	lf_process.start(script)

	assert_true(await _wait_for_signal(lf_process, "restart_failed", 5000))
	assert_signal_not_emitted(lf_process, "restarted")
	assert_push_error("not an executable")


# ---- run ----

func test_run_collects_output_and_the_exit_code():
	var result: Dictionary = await LFProcess.run("/bin/sh", ["-c", "echo out; echo err 1>&2; exit 4"], 5000)

	assert_true(result['started'])
	assert_false(result['timed_out'])
	assert_eq(result['code'], 4)
	assert_eq(result['stdout'], PackedStringArray(["out"]))
	assert_eq(result['stderr'], PackedStringArray(["err"]))


func test_run_kills_a_command_that_outlives_its_timeout():
	var started := Time.get_ticks_msec()
	var result: Dictionary = await LFProcess.run("/bin/sleep", ["30"], 200)

	assert_true(result['timed_out'])
	assert_eq(result['code'], LFProcess.STOPPED)
	assert_lt(Time.get_ticks_msec() - started, 3000)


func test_run_of_a_missing_binary_does_not_start():
	var result: Dictionary = await LFProcess.run("/nonexistent/binary-xyz")
	assert_push_error("not an executable")

	assert_false(result['started'])


func test_run_without_a_scene_tree_spawns_nothing_and_reports_not_started():
	var marker := OS.get_cache_dir().path_join('lf_process_no_tree_%d' % Time.get_ticks_usec())
	_temp_files.append(marker)
	var output := []
	var code := OS.execute(OS.get_executable_path(), [
		'--headless', '--path', ProjectSettings.globalize_path('res://'),
		'-s', _test_dir().path_join('fixtures/run_without_tree.gd'), '--', marker,
	], output, true)

	assert_eq(code, 0, 'the child engine ran the script')
	var line := ''
	for text in '\n'.join(output).split('\n'):
		if text.begins_with('RESULT '):
			line = text.trim_prefix('RESULT ')
	var result: Variant = LFJson.parse_object(line)
	assert_not_null(result, 'the child printed its result')
	if result != null:
		assert_false(result['started'])
	assert_false(FileAccess.file_exists(marker), 'the command was never spawned')


# ---- restart timing and signals ----

func test_the_restart_wait_grows_linearly_with_the_attempt():
	lf_process.auto_restart = true
	lf_process.max_restart_attempts = 2
	lf_process.restart_backoff_ms = 300
	lf_process.max_backoff_ms = 60000
	var stamps := []
	lf_process.exited.connect(func(_pid: int, _code: int): stamps.append(['exited', Time.get_ticks_msec()]))
	lf_process.restarted.connect(func(_pid: int, _attempt: int): stamps.append(['restarted', Time.get_ticks_msec()]))
	var started := Time.get_ticks_msec()
	lf_process.start("/bin/sh", ["-c", "exit 0"])

	assert_true(await _wait_until(func(): return stamps.size() >= 4, 6000), "two restarts")
	if stamps.size() < 4:
		return
	assert_eq([stamps[0][0], stamps[1][0], stamps[2][0], stamps[3][0]], ['exited', 'restarted', 'exited', 'restarted'])
	# Lower bounds only, measured between moments the code itself fixes: a spawn (start,
	# or a restart, which emits `restarted` in the same call) and the next restart. The
	# wait starts after the child exits, so it can only add to these; a slow frame cannot
	# shorten them. (`exited` is delivered a frame later, so it is not a reference point.)
	assert_gte(stamps[1][1] - started, 300, "restart 1 waits restart_backoff_ms")
	assert_gte(stamps[3][1] - stamps[1][1], 600, "restart 2 waits twice restart_backoff_ms")


func test_the_defaults_are_the_documented_constants():
	assert_eq(lf_process.restart_backoff_ms, LFProcess.DEFAULT_RESTART_BACKOFF_MS)
	assert_eq(lf_process.max_backoff_ms, LFProcess.DEFAULT_MAX_BACKOFF_MS)
	assert_eq(lf_process.max_line_bytes, LFProcess.DEFAULT_MAX_LINE_BYTES)
	assert_eq(lf_process.max_pending_lines, LFProcess.DEFAULT_MAX_PENDING_LINES)
	assert_eq(LFProcess.DEFAULT_TERMINATE_GRACE_MS, 2000)


func test_a_signal_death_reports_the_signal_number():
	var codes := []
	lf_process.exited.connect(func(_pid: int, code: int): codes.append(code))
	lf_process.start("/bin/sh", ["-c", "kill -TERM $$"])

	assert_true(await _wait_until(func(): return codes.size() == 1))
	assert_eq(codes, [SIGTERM], "SIGTERM is signal 15")


## This test file's folder, wherever the library is installed.
func _test_dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir()


# ---- more edges ----

func test_a_non_text_environment_name_does_not_start():
	watch_signals(lf_process)
	assert_false(lf_process.start("/bin/sh", ["-c", "exit 0"], {1: "x"}))
	assert_push_error("invalid environment variable name")
	assert_signal_not_emitted(lf_process, "started")


func test_env_overrides_an_existing_variable_only_for_the_child():
	OS.set_environment("LF_PROCESS_TEST_EXISTING", "parent")
	var lines := _collect("output_received")
	lf_process.start("/bin/sh", ["-c", "echo value=$LF_PROCESS_TEST_EXISTING"], {"LF_PROCESS_TEST_EXISTING": "child"})

	assert_true(await _wait_until(func(): return lines.has("value=child")))
	assert_eq(OS.get_environment("LF_PROCESS_TEST_EXISTING"), "parent", "the parent's value comes back")
	OS.unset_environment("LF_PROCESS_TEST_EXISTING")


func test_terminate_without_a_child_returns_at_once():
	var before := Time.get_ticks_msec()
	lf_process.terminate(2000)
	assert_lt(Time.get_ticks_msec() - before, 500)
	assert_false(lf_process.is_running())


func test_terminate_after_the_child_exited_does_not_wait_out_the_grace():
	lf_process.start("/bin/sh", ["-c", "exit 0"])
	assert_true(await _wait_for_signal(lf_process, "exited"))
	var before := Time.get_ticks_msec()
	lf_process.terminate(2000)
	assert_lt(Time.get_ticks_msec() - before, 1000)


func test_the_late_exit_of_a_replaced_child_leaves_the_new_pid_in_place():
	var exits := []
	lf_process.exited.connect(func(pid: int, code: int): exits.append([pid, code]))
	lf_process.start("/bin/sh", ["-c", "sleep 30"])
	var old_pid := lf_process.get_pid()
	lf_process.restart_now()
	var new_pid := lf_process.get_pid()

	assert_true(await _wait_until(func(): return exits.size() == 1))
	assert_eq(exits, [[old_pid, LFProcess.STOPPED]])
	assert_eq(lf_process.get_pid(), new_pid, "the old child's exit does not clear the new pid")
	assert_true(lf_process.is_running())


func test_restart_now_keeps_the_restart_count_that_start_resets():
	lf_process.auto_restart = true
	lf_process.max_restart_attempts = 1
	lf_process.restart_backoff_ms = 20
	var attempts := []
	var exits := [0]
	lf_process.restarted.connect(func(_pid: int, attempt: int): attempts.append(attempt))
	lf_process.exited.connect(func(_pid: int, _code: int): exits[0] += 1)
	lf_process.start("/bin/sh", ["-c", "exit 0"])
	assert_true(await _wait_until(func(): return exits[0] == 2, 5000), "the run and its one restart")
	assert_eq(attempts, [1])

	assert_true(lf_process.restart_now())
	assert_true(await _wait_until(func(): return exits[0] == 3, 5000))
	await wait_seconds(0.3)
	assert_eq(attempts, [1], "the limit is used up: restart_now kept the count")

	lf_process.start("/bin/sh", ["-c", "exit 0"])
	assert_true(await _wait_for_signal(lf_process, "restarted", 3000), "start() reset the count")


func test_a_zero_restart_limit_never_restarts():
	lf_process.auto_restart = true
	lf_process.max_restart_attempts = 0
	lf_process.restart_backoff_ms = 20
	watch_signals(lf_process)
	lf_process.start("/bin/sh", ["-c", "exit 0"])
	assert_true(await _wait_for_signal(lf_process, "exited"))
	await wait_seconds(0.3)
	assert_signal_not_emitted(lf_process, "restarted")


func test_line_and_backlog_limits_below_one_count_as_one():
	lf_process.max_line_bytes = 0
	lf_process.max_pending_lines = 0
	var lines := _collect("output_received")
	lf_process.start("/bin/sh", ["-c", "printf 'abc\\n'"])

	assert_true(await _wait_for_signal(lf_process, "exited"))
	assert_eq(lines, ["a", "b", "c"])


func test_empty_and_carriage_return_only_lines_are_not_delivered():
	var lines := _collect("output_received")
	lf_process.start("/bin/sh", ["-c", "printf '\\n\\r\\nx\\n\\n'"])

	assert_true(await _wait_for_signal(lf_process, "exited"))
	assert_eq(lines, ["x"])


func test_lines_carry_the_pid_of_the_child_that_wrote_them():
	var pids := []
	lf_process.output_received.connect(func(pid: int, _line: String): pids.append(pid))
	lf_process.start("/bin/sh", ["-c", "echo one"])
	var pid := lf_process.get_pid()

	assert_true(await _wait_for_signal(lf_process, "exited"))
	assert_eq(pids, [pid])


func test_started_reports_the_new_pid():
	var started := []
	lf_process.started.connect(func(pid: int): started.append(pid))
	lf_process.start("/bin/sh", ["-c", "sleep 30"])
	assert_eq(started, [lf_process.get_pid()], "emitted synchronously inside start()")


func test_run_without_a_timeout_waits_for_the_exit():
	var result: Dictionary = await LFProcess.run("/bin/sh", ["-c", "sleep 0.2; echo done"])

	assert_true(result['started'])
	assert_false(result['timed_out'])
	assert_eq(result['code'], 0)
	assert_eq(result['stdout'], PackedStringArray(["done"]))
