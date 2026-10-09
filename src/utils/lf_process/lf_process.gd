## Runs an external program (a command-line tool, a helper server) and looks after it.
##
## Each line the program prints arrives as a signal on the main thread (`output_received` for its
## standard output, "stdout"; `error_output_received` for its error output, "stderr"). The program is
## killed on [method stop] or when this object is freed, and with [member auto_restart] it is
## started again after it exits, waiting a little longer each time (a "backoff").
## [method run] runs a command once and returns its output, with an optional timeout.
class_name LFProcess
extends RefCounted

## The exit code `exited` reports for a process that stop() (or freeing) killed.
const STOPPED := -1
## Default for restart_backoff_ms, in milliseconds.
const DEFAULT_RESTART_BACKOFF_MS := 1500
## Default for max_backoff_ms, in milliseconds.
const DEFAULT_MAX_BACKOFF_MS := 30000
## Default for max_line_bytes, in bytes (64 KiB).
const DEFAULT_MAX_LINE_BYTES := 65536
## Default for max_pending_lines.
const DEFAULT_MAX_PENDING_LINES := 10000
## Default for terminate()'s grace_ms, in milliseconds.
const DEFAULT_TERMINATE_GRACE_MS := 2000

## Prefix of the generated id shown in log lines.
const _UID_PREFIX := 'lf-process'
## First part of every log line.
const _LOG_TAG := '[LFProcess]'
## Second part of every log line: the id; %s is the id.
const _LOG_UID_FORMAT := '(%s):'
## OS feature tag of Windows.
const _FEATURE_WINDOWS := 'windows'
## Extensions (lower-cased) of Windows batch files, which start() refuses.
const _BATCH_EXTENSIONS := ['bat', 'cmd']
## An environment variable name may not contain this.
const _ENV_NAME_FORBIDDEN := '='
## Unix command that signals a process.
const _KILL := 'kill'
## The signal flag terminate() sends: SIGTERM.
const _SIGTERM_FLAG := '-TERM'
## The Windows shell.
const _WINDOWS_SHELL := 'cmd.exe'
## cmd.exe flag: run the line that follows, then exit.
const _WINDOWS_SHELL_RUN_FLAG := '/C'
## The Unix shell.
const _UNIX_SHELL := '/bin/sh'
## sh flag: run the line that follows.
const _UNIX_SHELL_RUN_FLAG := '-c'
## OS.execute_with_pipe() key: the child's pid.
const _PIPE_PID := 'pid'
## OS.execute_with_pipe() key: the stdin/stdout pipe.
const _PIPE_STDIO := 'stdio'
## OS.execute_with_pipe() key: the stderr pipe.
const _PIPE_STDERR := 'stderr'
## Byte that ends a line ('\n').
const _NEWLINE_BYTE := 10
## Byte a Windows line ending puts before the newline ('\r'), dropped from a line's end.
const _CARRIAGE_RETURN_BYTE := 13
## How long terminate() sleeps between liveness checks, in milliseconds.
const _TERMINATE_POLL_MS := 10
## How long a reader sleeps while the main thread's queue is full, in milliseconds.
const _QUEUE_FULL_POLL_MS := 2
## How long the monitor sleeps between liveness checks and restart-wait checks, in milliseconds.
const _MONITOR_POLL_MS := 50
## How long a waiter sleeps between checks for drained pipes or finished threads, in milliseconds.
const _SHORT_POLL_MS := 5

## Restart the process after an exit that stop() didn't cause.
var auto_restart: bool = false
## Maximum auto-restarts since the last start(); -1 means unlimited.
var max_restart_attempts: int = -1
## Wait before auto-restart N is restart_backoff_ms * N, capped at max_backoff_ms.
var restart_backoff_ms: int = DEFAULT_RESTART_BACKOFF_MS
## Upper bound for the wait before any auto-restart.
var max_backoff_ms: int = DEFAULT_MAX_BACKOFF_MS
## A line longer than this many bytes is delivered in pieces of at most this size.
var max_line_bytes: int = DEFAULT_MAX_LINE_BYTES
## Lines read but not yet delivered on the main thread, per process; past it the reader
## waits, and the child blocks on its full pipe until the main thread catches up.
var max_pending_lines: int = DEFAULT_MAX_PENDING_LINES
## Pipe stdin/stdout/stderr (true), or let the child inherit this process's stdout/stderr
## and run with no reader threads (false: no `output_received`/`error_output_received`, no write_line).
var capture_output: bool = true

var _uid := LFUuid.gen(_UID_PREFIX)
var _logger := LFLogger.new([_LOG_TAG, _LOG_UID_FORMAT % [_uid]])

var _pid: int = -1
var _stdio: FileAccess = null
var _reader_thread: Thread = null
var _stderr_thread: Thread = null
var _monitor_thread: Thread = null
## One per start(): { stop: bool, pending: int, lock: Mutex }. Worker threads hold the
## dictionary, never this object, so dropping the last reference elsewhere still frees it.
var _session: Dictionary = _new_session()
## The current child: { pid, alive, code, lock: Mutex, out_done, err_done }. `lock` guards
## reaping and killing, so a pid is never signalled after the OS may have reused it.
var _child: Dictionary = {}
## How long stop()/a respawn waits for each worker thread before detaching it. A pump
## blocked on a pipe that a grandchild still holds open never wakes, and is detached.
const _JOIN_GRACE_MS := 500
## How long the monitor waits, after the child exits, for the readers to drain its pipes.
const _DRAIN_GRACE_MS := 500
## Most bytes one pipe read asks for.
const _READ_CHUNK := 4096
## Worker threads that outlived their grace period; joined once they finish.
static var _detached: Array[Thread] = []
static var _detached_lock := Mutex.new()
var _restart_count: int = 0
var _command_path: String
var _command_args: PackedStringArray = []
var _env: Dictionary = {}

## One non-empty stdout line, without its line ending (emitted on the main thread).
signal output_received(pid: int, line: String)
## One non-empty stderr line, without its line ending (emitted on the main thread).
signal error_output_received(pid: int, line: String)
## A process was spawned (by start, restart_now or an auto-restart).
signal started(pid: int)
## The process ended: its exit code, or STOPPED when stop() killed it. Lines it wrote are
## delivered first, unless its pipes stay open more than ~0.5 s after it exits (a grandchild
## holding them); lines read after that can arrive after this signal.
signal exited(pid: int, exit_code: int)
## An auto-restart spawned a new process; attempt counts restarts since start().
signal restarted(pid: int, attempt: int)
## An auto-restart was due but the command could not be spawned; supervision ends.
signal restart_failed(attempt: int)


## Creates an idle process runner. [param uid] is the id shown in its log lines; empty
## (the default) uses a generated "lf-process-..." id.
func _init(uid: String = '') -> void:
	if uid:
		set_uid(uid)


## Changes the id shown at the start of this runner's log lines.
func set_uid(uid: String) -> void:
	_uid = uid
	_logger.set_prefix([_LOG_TAG, _LOG_UID_FORMAT % [_uid]])


## Stops whatever this instance started before (a running child, a pending restart), then
## saves the command for restarts, resets the restart count and spawns it. Returns false,
## spawning nothing and leaving no command for restart_now, when `path` doesn't resolve to an executable (LFOS.resolve_executable),
## is a Windows .bat/.cmd (use run_shell), or an `env` key is empty or contains '='.
func start(path: String, args: PackedStringArray = [], env: Dictionary = {}) -> bool:
	_cancel()
	_command_path = ''
	var resolved := LFOS.resolve_executable(path)
	if resolved.is_empty():
		_logger.error('not an executable: %s' % path)
		return false
	if OS.has_feature(_FEATURE_WINDOWS) and resolved.get_extension().to_lower() in _BATCH_EXTENSIONS:
		_logger.error('batch files run through cmd.exe and its own parsing; use run_shell(): %s' % path)
		return false
	for key: Variant in env:
		if not (key is String) or key.is_empty() or key.contains(_ENV_NAME_FORBIDDEN):
			_logger.error('invalid environment variable name: %s' % str(key))
			return false
	_command_path = resolved
	_command_args = args.duplicate()
	_env = env.duplicate()
	_restart_count = 0
	_session = _new_session()
	return _spawn()


## Kills the process (not its own children), cancels any pending restart, joins the worker
## threads (detaching a reader still blocked after a short grace) and drops the pipes.
## `exited` then reports STOPPED unless the child had already exited. Lines read but not
## yet delivered are dropped.
func stop() -> void:
	_cancel()


## Asks the process to exit (SIGTERM on Unix), waits up to `grace_ms` for it, then stop()s.
## Blocks the calling thread for up to `grace_ms` plus what stop() waits. Windows has no polite signal for a
## console process, so there it is stop().
func terminate(grace_ms: int = DEFAULT_TERMINATE_GRACE_MS) -> void:
	if not _child.is_empty() and not OS.has_feature(_FEATURE_WINDOWS):
		var child := _child
		child['lock'].lock()
		if child['alive']:
			OS.execute(_KILL, [_SIGTERM_FLAG, str(child['pid'])])
		child['lock'].unlock()
		var deadline := Time.get_ticks_msec() + grace_ms
		while Time.get_ticks_msec() < deadline and LFProcess._child_alive(child):
			OS.delay_msec(_TERMINATE_POLL_MS)
	_cancel()


## Writes one line to the child's stdin and flushes. False without a running, captured
## child or when the write fails. stdin can't be closed on its own: the pipe shares one
## handle with stdout, so a child that reads stdin to EOF ends only when stopped.
func write_line(text: String) -> bool:
	if _stdio == null or not is_running():
		return false
	if not _stdio.store_line(text):
		return false
	_stdio.flush()
	return true


## True while this instance's child is running.
func is_running() -> bool:
	return _pid > 0 and LFProcess._child_alive(_child)


## The current child's pid; -1 when there is none or once its `exited` has been delivered.
func get_pid() -> int:
	return _pid


## Stops the running process, then spawns the saved command again. Unlike start(), keeps
## the restart count. Returns the spawn result (false when nothing was started before).
func restart_now() -> bool:
	_logger.log('restarting process...')
	_cancel()
	if _command_path.is_empty():
		return false
	_session = _new_session()
	return _spawn()


## Starts [param cmd_line] through the system shell (cmd.exe /C on Windows, /bin/sh -c
## elsewhere), e.g. run_shell("npm run start:dev"). Returns what [method start] returns.
## The shell interprets the whole line (pipes, $variables, quotes): never build it from
## untrusted input — pass such values as start() args instead.
func run_shell(cmd_line: String) -> bool:
	if OS.has_feature(_FEATURE_WINDOWS):
		return start(_WINDOWS_SHELL, [_WINDOWS_SHELL_RUN_FLAG, cmd_line])
	return start(_UNIX_SHELL, [_UNIX_SHELL_RUN_FLAG, cmd_line])


## Runs `path` once and collects its output: awaits until it exits, or kills it once
## `timeout_ms` has passed (0 or less waits forever). Returns { started: bool, code: int,
## timed_out: bool, stdout: PackedStringArray, stderr: PackedStringArray }; `code` is STOPPED
## when it didn't start or timed out. Needs a running SceneTree (it awaits frames): without
## one nothing is spawned and `started` is false.
static func run(path: String, args: PackedStringArray = [], timeout_ms: int = 0) -> Dictionary:
	var result := { 'started': false, 'code': STOPPED, 'timed_out': false,
		'stdout': PackedStringArray(), 'stderr': PackedStringArray() }
	var out_lines: Array[String] = []
	var err_lines: Array[String] = []
	var finished := [false, STOPPED]
	var on_exit := func(_exited_pid: int, code: int) -> void:
		finished[0] = true
		finished[1] = code
	var tree := LFUtils.tree_root
	if tree == null:
		return result
	var proc := LFProcess.new()
	proc.output_received.connect(func(_line_pid: int, line: String) -> void: out_lines.append(line))
	proc.error_output_received.connect(func(_line_pid: int, line: String) -> void: err_lines.append(line))
	proc.exited.connect(on_exit)
	if not proc.start(path, args):
		return result
	result['started'] = true
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not finished[0]:
		if timeout_ms > 0 and Time.get_ticks_msec() >= deadline:
			result['timed_out'] = true
			break
		await tree.process_frame
	proc.stop()
	if not result['timed_out']:
		result['code'] = finished[1]
	result['stdout'] = PackedStringArray(out_lines)
	result['stderr'] = PackedStringArray(err_lines)
	return result


static func _new_session() -> Dictionary:
	return { 'stop': false, 'pending': 0, 'lock': Mutex.new() }


## Ends the current session: kills a live child, flags the workers and any pending restart
## to stop, joins the workers and drops the pipes.
func _cancel() -> void:
	# Kill before flagging: the monitor reads the flag, and a killed child must already be
	# marked dead (code STOPPED) when it does.
	LFProcess._kill_child(_child)
	_session['stop'] = true
	_pid = -1
	LFProcess._join_bounded([_reader_thread, _stderr_thread, _monitor_thread])
	_reader_thread = null
	_stderr_thread = null
	_monitor_thread = null
	_stdio = null


func _spawn() -> bool:
	# Checked again on every spawn: on Unix a launch of a missing file still forks and
	# "starts", so an executable deleted since start() would restart as a failing child.
	if LFOS.resolve_executable(_command_path).is_empty():
		_logger.error('not an executable: %s' % _command_path)
		return false
	# A previous spawn of this session (an auto-restart) has finished its workers by now.
	# Joined before `_env` is applied, so the environment changes only for the spawn itself.
	LFProcess._join_bounded([_reader_thread, _stderr_thread, _monitor_thread])

	var previous_env := _apply_env()

	var child_pid := -1
	var stdio: FileAccess = null
	var stderr: FileAccess = null
	if capture_output:
		var info := OS.execute_with_pipe(_command_path, _command_args)
		child_pid = int(info.get(_PIPE_PID, -1))
		stdio = info.get(_PIPE_STDIO, null)
		stderr = info.get(_PIPE_STDERR, null)
	else:
		child_pid = OS.create_process(_command_path, _command_args)
	_restore_env(previous_env)
	if child_pid <= 0:
		_logger.error("Failed to start process: %s %s" % [_command_path, str(_command_args)])
		return false

	_pid = child_pid
	_stdio = stdio
	_child = { 'pid': child_pid, 'alive': true, 'code': STOPPED, 'lock': Mutex.new(),
		'out_done': not capture_output, 'err_done': not capture_output }

	_start_readers(stdio, stderr)
	_start_monitor()

	_logger.log('successfully started process PID = ', _pid)
	started.emit(_pid)
	return true


## The child inherits this process's environment at spawn, so `_env` is applied only around
## the spawn and the previous values are restored right after. Returns those previous values
## (null marks a variable that was unset) for `_restore_env`.
func _apply_env() -> Dictionary:
	var previous_env := {}
	for key: Variant in _env:
		var previous: Variant = null
		if OS.has_environment(key):
			previous = OS.get_environment(key)
		previous_env[key] = previous
		OS.set_environment(key, str(_env[key]))
	return previous_env


static func _restore_env(previous_env: Dictionary) -> void:
	for key: Variant in previous_env:
		if previous_env[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, previous_env[key])


## Starts the two reader threads over the child's pipes (a no-op without `capture_output`).
## Workers run static functions over plain values and method Callables (which hold no
## reference), never this object itself.
func _start_readers(stdio: FileAccess, stderr: FileAccess) -> void:
	if !capture_output:
		return
	var session := _session
	var deliver := _deliver_line
	_reader_thread = Thread.new()
	_reader_thread.start(LFProcess._pump.bind(_reader_context(stdio, output_received.get_name(), 'out_done', session, deliver)))
	_stderr_thread = Thread.new()
	_stderr_thread.start(LFProcess._pump.bind(_reader_context(stderr, error_output_received.get_name(), 'err_done', session, deliver)))


func _start_monitor() -> void:
	var attempt := _restart_count + 1
	var restart := {
		'enabled': auto_restart and (max_restart_attempts < 0 or _restart_count < max_restart_attempts),
		'attempt': attempt,
		'wait_ms': mini(restart_backoff_ms * attempt, max_backoff_ms),
	}
	_monitor_thread = Thread.new()
	_monitor_thread.start(LFProcess._monitor.bind(_child, _session, _deliver_exit,
		restart, _deferred_restart))


func _reader_context(stream: FileAccess, signal_name: String, done_key: String, session: Dictionary, deliver: Callable) -> Dictionary:
	return {
		'stream': stream, 'signal': signal_name, 'done_key': done_key, 'child': _child,
		'session': session, 'deliver': deliver,
		'max_line': maxi(max_line_bytes, 1), 'max_pending': maxi(max_pending_lines, 1),
	}


## Reads a pipe in chunks until EOF (every writer closed it) and hands each line to the main
## thread. A chunk read returns whatever is available, so an empty line is never mistaken
## for the end of the stream. Static: a worker never refers to the process object.
static func _pump(ctx: Dictionary) -> void:
	var stream: FileAccess = ctx['stream']
	var session: Dictionary = ctx['session']
	var max_line: int = ctx['max_line']
	var buffer := PackedByteArray()
	while stream != null and not session['stop']:
		var chunk := stream.get_buffer(_READ_CHUNK)	# blocks until data or EOF
		if chunk.is_empty() or session['stop']:
			break
		buffer.append_array(chunk)
		var newline := buffer.find(_NEWLINE_BYTE)
		while newline != -1 or buffer.size() > max_line:
			var cut := newline if newline != -1 and newline <= max_line else LFText.utf8_safe_cut(buffer, max_line)
			_emit_line(ctx, buffer.slice(0, cut))
			buffer = buffer.slice(cut + 1 if cut == newline else cut)
			newline = buffer.find(_NEWLINE_BYTE)
	if not session['stop'] and not buffer.is_empty():
		_emit_line(ctx, buffer)
	ctx['child'][ctx['done_key']] = true


## Queues one line for the main thread, waiting while too many are already queued.
static func _emit_line(ctx: Dictionary, bytes: PackedByteArray) -> void:
	if not bytes.is_empty() and bytes[bytes.size() - 1] == _CARRIAGE_RETURN_BYTE:
		bytes.resize(bytes.size() - 1)
	if bytes.is_empty():
		return
	var session: Dictionary = ctx['session']
	var lock: Mutex = session['lock']
	while not session['stop']:
		lock.lock()
		var room: bool = session['pending'] < ctx['max_pending']
		if room:
			session['pending'] += 1
		lock.unlock()
		if room:
			var deliver: Callable = ctx['deliver']
			deliver.call_deferred(ctx['signal'], ctx['child']['pid'], LFText.decode_utf8_lossy(bytes), session)
			return
		OS.delay_msec(_QUEUE_FULL_POLL_MS)


## Polls the child; once it has exited and the readers have drained its pipes, reports
## `exited` and — unless stopped — schedules the restart `restart` allows, after its wait.
## Static, for the same reason as `_pump`.
static func _monitor(child: Dictionary, session: Dictionary, deliver_exit: Callable, restart: Dictionary, restart_call: Callable) -> void:
	while not session['stop'] and _child_alive(child):
		OS.delay_msec(_MONITOR_POLL_MS)
	var drain_deadline := Time.get_ticks_msec() + _DRAIN_GRACE_MS
	var lock: Mutex = session['lock']
	while not session['stop'] and not (child['out_done'] and child['err_done']) \
			and Time.get_ticks_msec() < drain_deadline:
		OS.delay_msec(_SHORT_POLL_MS)
		# Lines queued for the main thread mean a reader is held back by the backlog cap,
		# not by a pipe a grandchild keeps open: the grace restarts while the main thread
		# is still delivering them.
		lock.lock()
		var backlog: int = session['pending']
		lock.unlock()
		if backlog > 0:
			drain_deadline = Time.get_ticks_msec() + _DRAIN_GRACE_MS
	child['lock'].lock()
	var code: int = STOPPED if child['alive'] else child['code']
	child['lock'].unlock()
	deliver_exit.call_deferred(child['pid'], code)

	if not session['stop'] and restart['enabled']:
		var deadline := Time.get_ticks_msec() + int(restart['wait_ms'])
		while Time.get_ticks_msec() < deadline and not session['stop']:
			OS.delay_msec(_MONITOR_POLL_MS)
		if not session['stop']:
			# Deferred to the main thread: _spawn() joins the outgoing monitor thread,
			# i.e. this one — which cannot join itself.
			restart_call.call_deferred(session, int(restart['attempt']))


## True while the child runs; on its exit, records the code and marks it dead (reaped).
static func _child_alive(child: Dictionary) -> bool:
	if child.is_empty():
		return false
	var lock: Mutex = child['lock']
	lock.lock()
	if child['alive'] and not OS.is_process_running(child['pid']):
		child['alive'] = false
		child['code'] = OS.get_process_exit_code(child['pid'])
	var alive: bool = child['alive']
	lock.unlock()
	return alive


## Kills the child if it is still this instance's live child; never a reaped (reusable) pid.
static func _kill_child(child: Dictionary) -> void:
	if child.is_empty():
		return
	var lock: Mutex = child['lock']
	lock.lock()
	if child['alive'] and OS.is_process_running(child['pid']):
		OS.kill(child['pid'])
		child['code'] = STOPPED
	elif child['alive']:
		child['code'] = OS.get_process_exit_code(child['pid'])
	child['alive'] = false
	lock.unlock()


func _deliver_line(signal_name: String, line_pid: int, line: String, session: Dictionary) -> void:
	var lock: Mutex = session['lock']
	lock.lock()
	session['pending'] -= 1
	var stopped: bool = session['stop']
	lock.unlock()
	if not stopped:
		emit_signal(signal_name, line_pid, line)


func _deliver_exit(exited_pid: int, code: int) -> void:
	if exited_pid == _pid:
		_pid = -1
	exited.emit(exited_pid, code)


func _deferred_restart(session: Dictionary, attempt: int) -> void:
	# A start()/stop() since the monitor queued this belongs to a new session; and
	# auto_restart or the attempt limit may have changed since the spawn.
	if not is_same(session, _session) or session['stop']:
		return
	if not auto_restart or (max_restart_attempts >= 0 and attempt > max_restart_attempts):
		_logger.log('restart cancelled (auto_restart or max_restart_attempts changed)')
		return
	_restart_count = attempt
	if _spawn():
		restarted.emit(_pid, _restart_count)
		_logger.log('restarted with PID =', _pid, 'restart count =', _restart_count)
	else:
		restart_failed.emit(attempt)


## Joins each started thread, waiting at most _JOIN_GRACE_MS overall. A thread still
## running after that (a pump blocked on a pipe a grandchild keeps open) is parked in
## _detached and joined by a later call once it has finished, instead of blocking forever.
static func _join_bounded(threads: Array) -> void:
	_detached_lock.lock()
	for t: Variant in _detached.duplicate():
		if not t.is_alive():
			t.wait_to_finish()
			_detached.erase(t)
	_detached_lock.unlock()
	var deadline := Time.get_ticks_msec() + _JOIN_GRACE_MS
	for t: Variant in threads:
		if t == null or not t.is_started():
			continue
		while t.is_alive() and Time.get_ticks_msec() < deadline:
			OS.delay_msec(_SHORT_POLL_MS)
		if t.is_alive():
			_detached_lock.lock()
			_detached.append(t)
			_detached_lock.unlock()
		else:
			t.wait_to_finish()


## Dropped without `stop()`: kill the child and join the workers, so neither outlives this
## object. Safe from any thread, since no worker refers to it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Static calls only: an object being deleted can't call its own methods.
		LFProcess._kill_child(_child)
		_session['stop'] = true
		LFProcess._join_bounded([_reader_thread, _stderr_thread, _monitor_thread])
