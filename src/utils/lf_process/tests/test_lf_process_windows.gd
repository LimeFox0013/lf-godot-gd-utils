extends GutTest

## Spawns real cmd.exe children; runs on Windows only. The /bin/sh tests are in
## test_lf_process.gd.

var lf_process: LFProcess


func should_skip_script() -> bool:
	return OS.get_name() != "Windows"


func before_each():
	lf_process = LFProcess.new()


func after_each():
	lf_process.stop()


func _wait_until(predicate: Callable, max_ms := 5000) -> bool:
	var deadline := Time.get_ticks_msec() + max_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return predicate.call()


func test_run_shell_reports_started_the_output_lines_and_the_exit_code():
	var lines := []
	var codes := []
	var pids := []
	lf_process.started.connect(func(pid: int): pids.append(pid))
	lf_process.output_received.connect(func(_pid: int, line: String): lines.append(line))
	lf_process.exited.connect(func(_pid: int, code: int): codes.append(code))

	assert_true(lf_process.run_shell("echo hello&exit 3"))

	assert_true(await _wait_until(func(): return not codes.is_empty()), "exited never fired")
	assert_eq(codes, [3])
	assert_eq(lines, ["hello"])
	assert_eq(pids.size(), 1)
	assert_gt(pids[0], 0)


func test_stop_ends_a_running_process_and_exited_reports_stopped():
	var codes := []
	lf_process.exited.connect(func(_pid: int, code: int): codes.append(code))
	assert_true(lf_process.run_shell("ping -n 30 127.0.0.1 > nul"))
	assert_true(await _wait_until(func(): return lf_process.is_running()))

	lf_process.stop()

	assert_false(lf_process.is_running())
	assert_true(await _wait_until(func(): return not codes.is_empty()), "exited never fired")
	assert_eq(codes, [LFProcess.STOPPED])


func test_a_batch_file_is_refused_by_start():
	var path := OS.get_cache_dir().path_join("lf_process_test_%d.cmd" % OS.get_process_id())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("@echo off\r\n")
	file.close()

	assert_false(lf_process.start(path))
	assert_push_error("use run_shell")
	DirAccess.remove_absolute(path)
