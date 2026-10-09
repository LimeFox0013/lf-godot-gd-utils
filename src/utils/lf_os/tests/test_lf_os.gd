extends GutTest

## Process and executable checks run real commands; the Unix-only ones are skipped on
## Windows.

## A pid no process on a test machine holds.
const NO_SUCH_PID := 999999
## The watchdog interval the tick tests count against, in seconds.
const INTERVAL_SECONDS := 1.0
## A short interval for the tests that must fire on the first tick, in seconds.
const SHORT_INTERVAL_SECONDS := 0.1

var _temp_dir := ''
## LFThread.force_main_thread as it was before each test; after_each puts it back.
var _saved_force_main_thread := false


func before_each():
	_saved_force_main_thread = LFThread.force_main_thread


func after_each():
	LFThread.force_main_thread = _saved_force_main_thread
	if not _temp_dir.is_empty():
		LFFile.remove_recursive(_temp_dir)
		_temp_dir = ''


func _unix() -> bool:
	return not OS.has_feature('windows')


func _make_temp_dir() -> String:
	# The process id keeps two runs at the same time apart.
	_temp_dir = OS.get_cache_dir().path_join('lf_os_test_%d_%d' % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	return _temp_dir


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_select_backend_always_prefers_metal_on_macos():
	assert_eq(LFOS.select_backend('macos'), LFOS.BACKEND_METAL)


func test_select_backend_never_picks_metal_on_non_macos():
	assert_ne(LFOS.select_backend('windows'), LFOS.BACKEND_METAL)
	assert_ne(LFOS.select_backend('linux'), LFOS.BACKEND_METAL)


func test_select_backend_defaults_to_the_running_os():
	assert_eq(LFOS.select_backend(), LFOS.select_backend(OS.get_name().to_lower()))


func test_select_backend_picks_vulkan_when_the_rendering_driver_is_vulkan():
	assert_eq(LFOS.select_backend('linux', 'vulkan', ''), LFOS.BACKEND_VULKAN)
	assert_eq(LFOS.select_backend('windows', 'vulkan', 'amd'), LFOS.BACKEND_VULKAN)


func test_select_backend_prefers_cuda_for_nvidia_and_falls_back_to_cpu():
	assert_eq(LFOS.select_backend('linux', 'vulkan', 'nvidia corporation'), LFOS.BACKEND_CUDA)
	assert_eq(LFOS.select_backend('windows', 'd3d12', 'intel'), LFOS.BACKEND_CPU)
	assert_eq(LFOS.select_backend('linux', 'opengl3', ''), LFOS.BACKEND_CPU)


func test_cuda_is_only_considered_on_windows_and_linux():
	assert_eq(LFOS.select_backend('android', 'vulkan', 'nvidia'), LFOS.BACKEND_VULKAN)
	assert_eq(LFOS.select_backend('freebsd', 'opengl3', 'nvidia'), LFOS.BACKEND_CPU)


func test_the_gpu_vendor_is_the_lower_cased_adapter_vendor():
	var vendor := LFOS.get_gpu_vendor()
	assert_eq(vendor, RenderingServer.get_video_adapter_vendor().to_lower())
	assert_eq(vendor, vendor.to_lower())


func test_this_process_is_alive_and_no_process_id_is_not():
	assert_true(LFOS.is_pid_alive(OS.get_process_id()))
	assert_false(LFOS.is_pid_alive(0))
	assert_false(LFOS.is_pid_alive(-5))


func test_a_process_that_is_not_a_child_is_seen_alive():
	if not _unix():
		pass_test('pid 1 is a Unix init process')
		return
	# pid 1 belongs to another user: `kill -0` is refused, yet the process exists.
	assert_true(LFOS.is_pid_alive(1))


func test_a_killed_child_is_no_longer_alive():
	if not _unix():
		pass_test('uses /bin/sleep')
		return
	var pid := OS.create_process('/bin/sleep', ['30'])
	assert_true(LFOS.is_pid_alive(pid))
	OS.kill(pid)	# also reaps it
	assert_false(LFOS.is_pid_alive(pid))


func test_a_bare_name_is_found_on_path():
	if not _unix():
		pass_test('Unix PATH layout')
		return
	var found := LFOS.resolve_executable('sh')
	assert_true(found.ends_with('/sh'), found)
	assert_true(FileAccess.file_exists(found))


func test_a_missing_or_empty_executable_resolves_to_nothing():
	assert_eq(LFOS.resolve_executable(''), '')
	assert_eq(LFOS.resolve_executable('/nonexistent/binary-xyz'), '')
	assert_eq(LFOS.resolve_executable('no-such-command-xyz-123'), '')


func test_a_directory_or_a_file_without_execute_permission_does_not_resolve():
	if not _unix():
		pass_test('Unix permission bits')
		return
	var dir := _make_temp_dir()
	var script := dir.path_join('tool.sh')
	_write(script, '#!/bin/sh\necho hi\n')
	assert_eq(LFOS.resolve_executable(dir), '', 'a directory is not an executable')
	assert_eq(LFOS.resolve_executable(script), '', 'not executable yet')
	FileAccess.set_unix_permissions(script, 0b111_101_101)
	assert_eq(LFOS.resolve_executable(script), script)


func test_an_app_bundle_resolves_to_its_bundle_executable():
	if not _unix():
		pass_test('macOS bundle layout, built by hand')
		return
	var dir := _make_temp_dir()
	var bundle := dir.path_join('Thing.app')
	DirAccess.make_dir_recursive_absolute(bundle.path_join('Contents/MacOS'))
	_write(bundle.path_join('Contents/Info.plist'),
		'<plist><dict><key>CFBundleExecutable</key>\n\t<string>real-binary</string></dict></plist>')
	var binary := bundle.path_join('Contents/MacOS/real-binary')
	_write(binary, '#!/bin/sh\n')
	FileAccess.set_unix_permissions(binary, 0b111_101_101)

	assert_eq(LFOS.resolve_executable(bundle), binary)

	DirAccess.remove_absolute(binary)
	DirAccess.remove_absolute(bundle.path_join('Contents/Info.plist'))
	DirAccess.remove_absolute(bundle.path_join('Contents/MacOS'))
	DirAccess.remove_absolute(bundle.path_join('Contents'))
	DirAccess.remove_absolute(bundle)


func test_self_launch_args_put_user_args_after_the_separator():
	var args := LFOS.self_launch_args(['--port=9', '--x'])

	assert_eq(args[0], '--headless')
	var separator := args.find('--')
	assert_gt(separator, 0)
	assert_eq(args.slice(separator + 1), PackedStringArray(['--port=9', '--x']))
	assert_eq(args.has('--path'), OS.has_feature('editor'), 'the editor needs the project path')


func test_self_launch_args_without_headless():
	assert_false(LFOS.self_launch_args([], false).has('--headless'))


## Ticks with no time passing until a check started off the main thread has answered.
func _tick_until_answered(watchdog: LFOS.PidWatchdog) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	var gone := watchdog.tick(0.0)
	while watchdog.is_checking() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		gone = watchdog.tick(0.0)
	assert_false(watchdog.is_checking(), 'the check answered in time')
	return gone


func test_the_watchdog_checks_once_per_interval_and_reports_a_gone_process():
	var alive := LFOS.PidWatchdog.new(OS.get_process_id(), INTERVAL_SECONDS)
	assert_false(alive.tick(0.5))
	assert_false(alive.tick(0.6), 'checked, and this process is alive')
	assert_false(await _tick_until_answered(alive))
	assert_false(alive.is_gone())

	var gone := LFOS.PidWatchdog.new(NO_SUCH_PID, INTERVAL_SECONDS)
	assert_false(gone.tick(0.4), 'no check before the interval')
	assert_false(gone.is_checking(), 'nothing started before the interval')
	gone.tick(0.7)
	assert_true(await _tick_until_answered(gone))
	assert_true(gone.tick(0.0), 'stays gone')
	assert_true(gone.is_gone())


func test_the_watchdog_exposes_its_pid_and_interval_and_reads_them_on_each_tick():
	var watchdog := LFOS.PidWatchdog.new(OS.get_process_id())
	assert_eq(watchdog.pid, OS.get_process_id())
	assert_eq(watchdog.check_interval_seconds, LFOS.PidWatchdog.DEFAULT_CHECK_INTERVAL_SECONDS, 'the default interval')
	assert_eq(LFOS.PidWatchdog.DEFAULT_CHECK_INTERVAL_SECONDS, 2.0)
	watchdog.check_interval_seconds = SHORT_INTERVAL_SECONDS
	watchdog.pid = NO_SUCH_PID
	watchdog.tick(0.2)
	assert_true(await _tick_until_answered(watchdog), 'the new pid is checked after the new, shorter interval')


func test_a_check_that_launches_a_command_runs_off_the_main_thread():
	if not LFOS.pid_check_runs_command():
		pass_test('this platform reads /proc directly; nothing to move off the main thread')
		return
	var watchdog := LFOS.PidWatchdog.new(NO_SUCH_PID, SHORT_INTERVAL_SECONDS)
	assert_false(watchdog.tick(0.2), 'the tick that starts the check does not wait for it')
	assert_true(watchdog.is_checking())
	assert_true(await _tick_until_answered(watchdog))


func test_an_answer_about_a_pid_that_was_replaced_meanwhile_is_dropped():
	if not LFOS.pid_check_runs_command():
		pass_test('checks answer on the same tick here')
		return
	var watchdog := LFOS.PidWatchdog.new(NO_SUCH_PID, SHORT_INTERVAL_SECONDS)
	watchdog.tick(0.2)
	watchdog.pid = OS.get_process_id()
	assert_false(await _tick_until_answered(watchdog), 'the old pid being gone says nothing about the new one')


func test_the_pid_check_runs_a_command_exactly_where_there_is_no_proc_folder():
	var expected := not DirAccess.dir_exists_absolute('/proc/self') \
		and not (OS.has_feature('web') or OS.has_feature('android') or OS.has_feature('ios'))
	assert_eq(LFOS.pid_check_runs_command(), expected)


func test_a_watchdog_without_a_pid_never_fires():
	var none := LFOS.PidWatchdog.new(0, SHORT_INTERVAL_SECONDS)
	assert_false(none.tick(5.0))


func test_an_app_bundle_without_an_info_plist_resolves_to_the_binary_named_after_it():
	if not _unix():
		pass_test('macOS bundle layout, built by hand')
		return
	var dir := _make_temp_dir()
	var bundle := dir.path_join('Thing.app')
	DirAccess.make_dir_recursive_absolute(bundle.path_join('Contents/MacOS'))
	var binary := bundle.path_join('Contents/MacOS/Thing')
	_write(binary, '#!/bin/sh\n')
	FileAccess.set_unix_permissions(binary, 0b111_101_101)

	assert_eq(LFOS.resolve_executable(bundle), binary)

	DirAccess.remove_absolute(binary)
	DirAccess.remove_absolute(bundle.path_join('Contents/MacOS'))
	DirAccess.remove_absolute(bundle.path_join('Contents'))
	DirAccess.remove_absolute(bundle)


func test_a_scheme_path_is_globalized_before_it_is_checked():
	if not _unix():
		pass_test('Unix permission bits')
		return
	var scheme_path := 'user://lf_os_test_%d_%d/tool.sh' % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute := ProjectSettings.globalize_path(scheme_path)
	_temp_dir = absolute.get_base_dir()
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	_write(absolute, '#!/bin/sh\n')
	FileAccess.set_unix_permissions(absolute, 0b111_101_101)

	assert_eq(LFOS.resolve_executable(scheme_path), absolute)


# ---- user arguments

func test_parse_user_args_reads_values_and_flags():
	var parsed := LFOS.parse_user_args(PackedStringArray([
		'--port=7777', '--verbose', '--parent-pid=1234', 'positional', '--', '--name=a=b', '--port=26000',
	]))

	assert_eq(parsed, {'port': '26000', 'verbose': true, 'parent-pid': '1234', 'name': 'a=b'})


func test_parse_user_args_of_nothing_is_empty():
	assert_eq(LFOS.parse_user_args(PackedStringArray()), {})


func test_self_launch_args_read_back_through_parse_user_args():
	var args := LFOS.self_launch_args(['--port=7777', '--server'])
	var user_args := args.slice(args.find('--') + 1)

	assert_eq(LFOS.parse_user_args(user_args), {'port': '7777', 'server': true})


func test_an_encoded_arg_value_round_trips_any_json_value():
	var value := {'name': 'Item "one" & two', 'slots': [1, 2], 'nested': {'ok': true}}
	var word := LFOS.encode_arg_value(value)

	assert_false(word.contains(' '), 'one word on a command line')
	assert_eq(LFOS.decode_arg_value(word), {'name': 'Item "one" & two', 'slots': [1.0, 2.0], 'nested': {'ok': true}})
	assert_eq(LFOS.decode_arg_value(LFOS.encode_arg_value('text')), 'text')
	var parsed := LFOS.parse_user_args(PackedStringArray(['--value=' + word]))
	assert_eq(LFOS.decode_arg_value(parsed['value']), LFOS.decode_arg_value(word), 'base64 padding survives the = split')


func test_a_bad_arg_value_decodes_to_null_quietly():
	assert_null(LFOS.decode_arg_value(''))
	assert_null(LFOS.decode_arg_value('not base64!'))
	assert_null(LFOS.decode_arg_value('abc'))
	assert_null(LFOS.decode_arg_value('e30\n'), 'a trailing newline is not base64')
	assert_null(LFOS.decode_arg_value(Marshalls.utf8_to_base64('{broken')))
	assert_engine_error_count(0)


# ---- network addresses

func test_only_private_ipv4_addresses_are_private():
	assert_true(LFOS.is_private_ipv4('192.168.1.20'))
	assert_true(LFOS.is_private_ipv4('10.0.0.5'))
	assert_true(LFOS.is_private_ipv4('172.20.1.1'))
	assert_true(LFOS.is_private_ipv4('100.101.102.103'), 'the shared range counts by default')
	assert_false(LFOS.is_private_ipv4('127.0.0.1'))
	assert_false(LFOS.is_private_ipv4('169.254.3.4'))
	assert_false(LFOS.is_private_ipv4('8.8.8.8'))
	assert_false(LFOS.is_private_ipv4('fe80::1'))
	assert_false(LFOS.is_private_ipv4('172.32.0.1'))
	assert_false(LFOS.is_private_ipv4('not an address'))


func test_the_shared_range_can_be_left_out():
	assert_false(LFOS.is_private_ipv4('100.101.102.103', false))
	assert_true(LFOS.is_private_ipv4('10.0.0.5', false))


func test_local_addresses_leave_out_link_local_ones_unless_asked():
	var all := LFOS.local_addresses(true)
	var default := LFOS.local_addresses()
	var v4 := LFOS.local_addresses(false, true)

	assert_true(default.has('127.0.0.1'), 'loopback is a local address')
	for address in default:
		assert_false(address.to_lower().begins_with('fe80') or address.begins_with('169.254.'), address)
		assert_true(all.has(address))
	for address in v4:
		assert_false(address.contains(':'), address)
	var sorted := default.duplicate()
	sorted.sort()
	assert_eq(default, sorted)


func test_select_backend_matches_vendor_and_driver_case_insensitively():
	assert_eq(LFOS.select_backend('windows', 'd3d12', 'NVIDIA Corporation'), LFOS.BACKEND_CUDA)
	assert_eq(LFOS.select_backend('linux', 'Vulkan', 'amd'), LFOS.BACKEND_VULKAN)


func test_select_backend_with_no_driver_reads_the_running_driver():
	var running := RenderingServer.get_current_rendering_driver_name()
	assert_eq(LFOS.select_backend('linux', '', 'amd'), LFOS.select_backend('linux', running if not running.is_empty() else 'none', 'amd'))


func test_the_private_ranges_end_exactly_at_their_boundaries():
	for inside in ['10.255.255.255', '172.16.0.0', '172.31.255.255', '192.168.0.0', '100.64.0.0', '100.127.255.255']:
		assert_true(LFOS.is_private_ipv4(inside), inside)
	for outside in ['11.0.0.1', '9.255.255.255', '172.15.255.255', '172.32.0.0', '192.167.1.1', '192.169.0.1', '100.63.255.255', '100.128.0.0', '0.0.0.0', '255.255.255.255']:
		assert_false(LFOS.is_private_ipv4(outside), outside)


func test_a_malformed_ipv4_is_not_private():
	assert_false(LFOS.is_private_ipv4('10.0.0.256'))
	assert_false(LFOS.is_private_ipv4(''))
	assert_false(LFOS.is_private_ipv4('10.0.0.1.1'))
	assert_false(LFOS.is_private_ipv4('localhost'))
	assert_false(LFOS.is_private_ipv4('fd00::1'), 'a native IPv6 unique-local address is not IPv4')


func test_numeric_ipv4_forms_are_read_like_lfurl_reads_them():
	for private in ['167772161', '0xa000001', '0x0a.1', '10.1', '10.0.1', '0300.0250.0.1', '2886729729']:
		assert_true(LFOS.is_private_ipv4(private), private)
	for other in ['2130706433', '0x7f.1', '127.1', '134744072', '0x08080808', '4294967296']:
		assert_false(LFOS.is_private_ipv4(other), other)
	assert_true(LFOS.is_private_ipv4('1681915905'), '100.64.0.1 as one number: shared range')
	assert_false(LFOS.is_private_ipv4('1681915905', false))


func test_ipv4_mapped_ipv6_is_read_as_the_ipv4_address_it_carries():
	assert_true(LFOS.is_private_ipv4('::ffff:10.0.0.1'))
	assert_true(LFOS.is_private_ipv4('::FFFF:192.168.1.1'))
	assert_true(LFOS.is_private_ipv4('::ffff:a00:1'))
	assert_true(LFOS.is_private_ipv4('::ffff:100.64.0.1'))
	assert_false(LFOS.is_private_ipv4('::ffff:100.64.0.1', false))
	assert_false(LFOS.is_private_ipv4('::ffff:7f00:1'))
	assert_false(LFOS.is_private_ipv4('::ffff:8.8.8.8'))
	assert_false(LFOS.is_private_ipv4('::ffff:10.0.0.256'))
	assert_false(LFOS.is_private_ipv4('::ffff:zz:1'))
	assert_false(LFOS.is_private_ipv4('::1'))


func test_self_launch_args_from_the_editor_name_this_project():
	var args := LFOS.self_launch_args()
	if not OS.has_feature('editor'):
		assert_false(args.has('--path'))
		return
	var at := args.find('--path')
	assert_eq(args[at + 1], ProjectSettings.globalize_path('res://'))
	assert_lt(at, args.find('--'), 'Godot arguments come before the separator')
	assert_eq(args[-1], '--', 'no user arguments, nothing after the separator')


func test_an_app_bundle_with_a_trailing_slash_resolves_the_same():
	if not _unix():
		pass_test('macOS bundle layout, built by hand')
		return
	var dir := _make_temp_dir()
	var bundle := dir.path_join('Thing.app')
	DirAccess.make_dir_recursive_absolute(bundle.path_join('Contents/MacOS'))
	var binary := bundle.path_join('Contents/MacOS/Thing')
	_write(binary, '#!/bin/sh\n')
	FileAccess.set_unix_permissions(binary, 0b111_101_101)

	assert_eq(LFOS.resolve_executable(bundle + '/'), binary)

	DirAccess.remove_absolute(binary)
	DirAccess.remove_absolute(bundle.path_join('Contents/MacOS'))
	DirAccess.remove_absolute(bundle.path_join('Contents'))
	DirAccess.remove_absolute(bundle)


func test_a_bundle_plist_without_a_string_value_falls_back_to_the_bundle_name_and_needs_an_execute_bit():
	if not _unix():
		pass_test('macOS bundle layout, built by hand')
		return
	var dir := _make_temp_dir()
	var bundle := dir.path_join('Thing.app')
	DirAccess.make_dir_recursive_absolute(bundle.path_join('Contents/MacOS'))
	_write(bundle.path_join('Contents/Info.plist'), '<plist><dict><key>CFBundleExecutable</key></dict></plist>')
	var binary := bundle.path_join('Contents/MacOS/Thing')
	_write(binary, '#!/bin/sh\n')

	assert_eq(LFOS.resolve_executable(bundle), '', 'the bundle binary is not executable yet')
	FileAccess.set_unix_permissions(binary, 0b111_101_101)
	assert_eq(LFOS.resolve_executable(bundle), binary, 'the key without a value names nothing')

	DirAccess.remove_absolute(binary)
	DirAccess.remove_absolute(bundle.path_join('Contents/Info.plist'))
	DirAccess.remove_absolute(bundle.path_join('Contents/MacOS'))
	DirAccess.remove_absolute(bundle.path_join('Contents'))
	DirAccess.remove_absolute(bundle)


func test_a_directory_named_like_a_bundle_is_only_a_bundle_when_it_exists():
	assert_eq(LFOS.resolve_executable('/nonexistent/Thing.app'), '')


## Without thread support the check started by one tick runs, blocking, in the next.
func test_without_threads_the_watchdog_answers_on_the_next_tick():
	if not LFOS.pid_check_runs_command():
		pass_test('checks answer on the same tick here')
		return
	LFThread.force_main_thread = true
	var watchdog := LFOS.PidWatchdog.new(NO_SUCH_PID, SHORT_INTERVAL_SECONDS)
	assert_false(watchdog.tick(0.2), 'the tick that starts the check does not run it')
	assert_true(watchdog.is_checking())
	assert_true(watchdog.tick(0.0), 'the next tick runs the check and reports it')
	assert_false(watchdog.is_checking())


func test_the_next_interval_counts_from_the_answer():
	var watchdog := LFOS.PidWatchdog.new(OS.get_process_id(), INTERVAL_SECONDS)
	watchdog.tick(1.5)
	assert_false(await _tick_until_answered(watchdog))
	assert_false(watchdog.tick(0.9), 'not a whole interval since the answer')
	assert_false(watchdog.is_checking(), 'so no new check')
	watchdog.tick(0.2)
	assert_eq(watchdog.is_checking(), LFOS.pid_check_runs_command(), 'a whole interval later, a new check')
	await _tick_until_answered(watchdog)


func test_a_watchdog_with_a_negative_pid_never_checks():
	var none := LFOS.PidWatchdog.new(-3, SHORT_INTERVAL_SECONDS)
	assert_false(none.tick(5.0))
	assert_false(none.is_checking())
	assert_false(none.is_gone())


func test_a_nan_check_interval_is_rejected_and_the_value_is_kept():
	var watchdog := LFOS.PidWatchdog.new(OS.get_process_id(), 3.0)
	watchdog.check_interval_seconds = NAN
	assert_push_error('NaN')
	assert_eq(watchdog.check_interval_seconds, 3.0)
	assert_eq(LFOS.PidWatchdog.new(OS.get_process_id(), NAN).check_interval_seconds, LFOS.PidWatchdog.DEFAULT_CHECK_INTERVAL_SECONDS)
	assert_push_error_count(2)
