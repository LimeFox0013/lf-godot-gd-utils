## Small helpers for talking to the operating system and the machine the project runs on.
##
## Pick which build of a native helper program to launch (Metal, CUDA, Vulkan or CPU),
## ask whether any process id (pid: the number the OS gives each running program) is
## alive, find an executable by searching `PATH` as a shell does, build the command line that runs this
## same project again headless (without a window) and read its `--key=value` arguments
## back, and list this machine's network addresses.
## [LFOS.PidWatchdog] reports once a watched process is gone. All methods are static: call
## them on the class, e.g. `LFOS.is_pid_alive(pid)`.
class_name LFOS

## [method select_backend] result on macOS: Apple's Metal.
const BACKEND_METAL := 'metal'
## [method select_backend] result on Windows/Linux with an NVIDIA GPU: NVIDIA's CUDA.
const BACKEND_CUDA := 'cuda'
## [method select_backend] result when Godot itself renders through Vulkan.
const BACKEND_VULKAN := 'vulkan'
## [method select_backend] result when no GPU backend applies: run on the CPU.
const BACKEND_CPU := 'cpu'

## Extensions tried on Windows when `PATHEXT` is not set.
const _DEFAULT_PATHEXT := ['.COM', '.EXE', '.BAT', '.CMD']

## OS.get_name() lower-cased on macOS.
const _OS_MACOS := 'macos'
## OS.get_name() lower-cased on Windows.
const _OS_WINDOWS := 'windows'
## OS.get_name() lower-cased on Linux.
const _OS_LINUX := 'linux'
## Substring of the GPU vendor name that marks an NVIDIA GPU (matched case-insensitively).
const _VENDOR_NVIDIA := 'nvidia'
## Rendering driver name (lower-cased) of Vulkan.
const _DRIVER_VULKAN := 'vulkan'
## OS feature tag of Windows.
const _FEATURE_WINDOWS := 'windows'
## OS feature tag of the web export.
const _FEATURE_WEB := 'web'
## OS feature tag of Android.
const _FEATURE_ANDROID := 'android'
## OS feature tag of iOS.
const _FEATURE_IOS := 'ios'
## OS feature tag present when running from the editor.
const _FEATURE_EDITOR := 'editor'
## Exists only where a Linux-style /proc filesystem lists processes.
const _PROC_SELF := '/proc/self'
## A process's /proc folder; %d is the pid.
const _PROC_PID_FORMAT := '/proc/%d'
## Windows command that lists processes.
const _TASKLIST := 'tasklist'
## tasklist flag: filter the list (followed by the filter).
const _TASKLIST_FILTER_FLAG := '/FI'
## tasklist filter keeping only one pid; %d is the pid.
const _TASKLIST_PID_FILTER_FORMAT := 'PID eq %d'
## tasklist flag: no column header.
const _TASKLIST_NO_HEADER_FLAG := '/NH'
## tasklist flag: output format (followed by the format).
const _TASKLIST_FORMAT_FLAG := '/FO'
## tasklist output format: CSV.
const _TASKLIST_FORMAT_CSV := 'CSV'
## How the pid appears in tasklist's CSV output: a quoted field; %d is the pid.
const _TASKLIST_PID_FIELD_FORMAT := '"%d"'
## Unix command that signals a process.
const _KILL := 'kill'
## Signal 0: checks the process exists without signalling it.
const _KILL_CHECK_ONLY := '-0'
## kill's error when the process exists but belongs to another user.
const _KILL_NOT_PERMITTED := 'not permitted'
## Godot command-line flag: run without a window.
const _ARG_HEADLESS := '--headless'
## Godot command-line flag: the project folder to run (followed by the path).
const _ARG_PATH := '--path'
## Separates Godot's own arguments from the user arguments; also the user-argument prefix.
const _ARG_SEPARATOR := '--'
## Separates a user argument's key from its value.
const _ARG_VALUE_SEPARATOR := '='
## Scheme of project paths; alone, the project root.
const _RES_ROOT := 'res://'
## Scheme of user-data paths.
const _USER_ROOT := 'user://'
## Base64 text length is a multiple of this many characters.
const _BASE64_BLOCK := 4
## Matches standard base64 text, padding included.
const _BASE64_PATTERN := '^[A-Za-z0-9+/]*={0,2}\\z'
## Marks an IPv6 address (IPv4 addresses never contain it).
const _IPV6_MARK := ':'
## Prefix of an IPv4-mapped IPv6 address, lower case.
const _MAPPED_PREFIX := '::ffff:'
## Separates IPv4 octets.
const _IPV4_SEPARATOR := '.'
## RFC 6598 shared range 100.64/10: first octet.
const _SHARED_FIRST := 100
## RFC 6598 shared range 100.64/10: lowest second octet.
const _SHARED_SECOND_MIN := 64
## RFC 6598 shared range 100.64/10: highest second octet.
const _SHARED_SECOND_MAX := 127
## Lower-cased prefixes of IPv6 link-local addresses (fe80::/10).
const _IPV6_LINK_LOCAL_PREFIXES := ['fe8', 'fe9', 'fea', 'feb']
## Prefix of IPv4 link-local addresses (169.254/16).
const _IPV4_LINK_LOCAL_PREFIX := '169.254.'
## Directory separator on Unix (also accepted on Windows).
const _SEPARATOR := '/'
## Directory separator only Windows uses.
const _WINDOWS_SEPARATOR := '\\'
## Environment variable: the executable search path.
const _ENV_PATH := 'PATH'
## Environment variable: Windows' executable extensions.
const _ENV_PATHEXT := 'PATHEXT'
## Separates PATH and PATHEXT entries on Windows.
const _WINDOWS_LIST_SEPARATOR := ';'
## Separates PATH entries on Unix.
const _UNIX_LIST_SEPARATOR := ':'
## Execute permission bits for owner, group and others.
const _ANY_EXECUTE_BITS := 0b001_001_001
## Extension of a macOS application bundle.
const _APP_EXTENSION := '.app'
## A bundle's property list, relative to the bundle.
const _BUNDLE_PLIST := 'Contents/Info.plist'
## A bundle's executable folder, relative to the bundle.
const _BUNDLE_EXECUTABLE_DIR := 'Contents/MacOS'
## The plist key naming the bundle's executable.
const _PLIST_EXECUTABLE_KEY := '<key>CFBundleExecutable</key>'
## Opening tag of a plist string value.
const _PLIST_STRING_OPEN := '<string>'
## Closing tag of a plist string value.
const _PLIST_STRING_CLOSE := '</string>'


## Picks which build of a native helper program to launch (Metal, CUDA, Vulkan or CPU):
## - macOS → BACKEND_METAL
## - Windows/Linux with an NVIDIA GPU → BACKEND_CUDA
## - otherwise, when Godot is rendering through Vulkan → BACKEND_VULKAN
## - otherwise → BACKEND_CPU
## The defaults read the running engine: OS.get_name() lower-cased, the current rendering
## driver (rendering_driver '' = RenderingServer.get_current_rendering_driver_name()) and the
## GPU vendor. This is a naming rule, not a capability check: no runtime is probed.
static func select_backend(
	os_name: String = OS.get_name().to_lower(),
	rendering_driver := '',
	gpu_vendor: String = get_gpu_vendor(),
) -> String:
	if rendering_driver.is_empty():
		rendering_driver = RenderingServer.get_current_rendering_driver_name()
	if os_name == _OS_MACOS:
		return BACKEND_METAL
	if (os_name == _OS_WINDOWS or os_name == _OS_LINUX) and gpu_vendor.findn(_VENDOR_NVIDIA) != -1:
		return BACKEND_CUDA
	if rendering_driver.to_lower() == _DRIVER_VULKAN:
		return BACKEND_VULKAN
	return BACKEND_CPU


## The GPU vendor (lowercased), or '' when there is none.
static func get_gpu_vendor() -> String:
	return RenderingServer.get_video_adapter_vendor().to_lower()


## True while a process with this id exists — any process, not only a child of this one
## (`OS.is_process_running()` answers only for children). Linux checks `/proc/<pid>`;
## other Unix systems ask `kill -0` (a process owned by another user counts as alive);
## Windows asks `tasklist`. When `kill` or `tasklist` cannot be run, every other process
## reads as gone. An exited child that nobody has reaped yet (a zombie) still
## counts as alive. Android reads `/proc/<pid>` like Linux when `/proc` exists; on web and
## iOS only this process's own id is alive. Where [method pid_check_runs_command] is true it launches
## `kill` or `tasklist` and blocks the calling thread until that exits (`tasklist` on
## Windows is the slowest); call it off the main thread, or seldom ([LFOS.PidWatchdog]
## does the former).
static func is_pid_alive(pid: int) -> bool:
	if pid <= 0:
		return false
	if pid == OS.get_process_id():
		return true
	if DirAccess.dir_exists_absolute(_PROC_SELF):
		return DirAccess.dir_exists_absolute(_PROC_PID_FORMAT % pid)
	var out := []
	if OS.has_feature(_FEATURE_WINDOWS):
		var filter := _TASKLIST_PID_FILTER_FORMAT % pid
		var tasklist_args := [_TASKLIST_FILTER_FLAG, filter, _TASKLIST_NO_HEADER_FLAG, _TASKLIST_FORMAT_FLAG, _TASKLIST_FORMAT_CSV]
		if OS.execute(_TASKLIST, tasklist_args, out) != 0:
			return false
		return out.size() > 0 and str(out[0]).contains(_TASKLIST_PID_FIELD_FORMAT % pid)
	if OS.has_feature(_FEATURE_WEB) or OS.has_feature(_FEATURE_ANDROID) or OS.has_feature(_FEATURE_IOS):
		return false
	if OS.execute(_KILL, [_KILL_CHECK_ONLY, str(pid)], out, true) == 0:
		return true
	return out.size() > 0 and str(out[0]).findn(_KILL_NOT_PERMITTED) != -1


## Whether [method is_pid_alive] for another process's id launches a command (`kill -0`
## on Unix without `/proc`, such as macOS; `tasklist` on Windows) and so blocks until it
## exits. False on Linux (`/proc` is read directly) and where commands can't run.
static func pid_check_runs_command() -> bool:
	if DirAccess.dir_exists_absolute(_PROC_SELF):
		return false
	if OS.has_feature(_FEATURE_WINDOWS):
		return true
	return not (OS.has_feature(_FEATURE_WEB) or OS.has_feature(_FEATURE_ANDROID) or OS.has_feature(_FEATURE_IOS))


## The arguments that run this same project again: `--headless` (when `headless`), the project
## path when running from the editor (whose executable is Godot itself, not the project), then
## `--` and `user_args`, which the new process reads with OS.get_cmdline_user_args().
## Pair it with OS.get_executable_path().
static func self_launch_args(user_args: PackedStringArray = [], headless := true) -> PackedStringArray:
	var args := PackedStringArray()
	if headless:
		args.append(_ARG_HEADLESS)
	if OS.has_feature(_FEATURE_EDITOR):
		args.append_array([_ARG_PATH, ProjectSettings.globalize_path(_RES_ROOT)])
	args.append(_ARG_SEPARATOR)
	args.append_array(user_args)
	return args


## The `--key=value` and `--flag` arguments of `args` (e.g. OS.get_cmdline_user_args())
## as `{key: 'value', flag: true}`. The value is everything after the first `=`, so it
## may itself hold `=`. Arguments not starting with `--`, and a bare `--`, are skipped; a
## repeated key keeps its last value.
static func parse_user_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in args:
		if !arg.begins_with(_ARG_SEPARATOR) or arg.length() == _ARG_SEPARATOR.length():
			continue
		var body := arg.substr(_ARG_SEPARATOR.length())
		var equals := body.find(_ARG_VALUE_SEPARATOR)
		if equals == -1:
			parsed[body] = true
		else:
			parsed[body.substr(0, equals)] = body.substr(equals + 1)
	return parsed


## `parsed[key]` (from [method parse_user_args]) as an int, or `fallback` when the key is
## missing or a bare flag. Text that is not a number reads as 0, like `String.to_int`.
static func int_arg(parsed: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = parsed.get(key)
	return int(value) if value is String else fallback


## `value` as one command-line word: its JSON, base64-encoded (only letters, digits, `+`,
## `/` and `=`, none of which a POSIX shell treats specially), so any JSON value (a
## Dictionary, an Array, text with spaces or quotes) passes through argv unchanged. Read it
## back with decode_arg_value. JSON is lossy: numbers come back as floats.
static func encode_arg_value(value: Variant) -> String:
	return Marshalls.utf8_to_base64(JSON.stringify(value))


## The value encode_arg_value wrote into `text`, or null when `text` is not base64 of
## JSON. Quiet: bad input logs no engine error.
static func decode_arg_value(text: String) -> Variant:
	if text.is_empty() or text.length() % _BASE64_BLOCK != 0 or !_base64_pattern.search(text):
		return null
	return LFJson.parse(LFText.decode_utf8_lossy(Marshalls.base64_to_raw(text)))


static var _base64_pattern := RegEx.create_from_string(_BASE64_PATTERN)


## This machine's IP addresses (IP.get_local_addresses()), sorted. Link-local addresses
## (IPv6 `fe80::/10`, IPv4 `169.254.0.0/16`), which only reach the same network link and
## need a zone to bind, are left out unless `include_link_local`; `ipv4_only` drops IPv6.
static func local_addresses(include_link_local := false, ipv4_only := false) -> Array[String]:
	var found: Array[String] = []
	for address in IP.get_local_addresses():
		var v6 := address.contains(_IPV6_MARK)
		if ipv4_only and v6:
			continue
		if !include_link_local and _is_link_local(address, v6):
			continue
		found.append(address)
	found.sort()
	return found


## Whether `address` is an IPv4 address in a private (not publicly routed) range: 10/8, 172.16/12 or 192.168/16 (RFC 1918), plus, with
## `include_shared_range`, the 100.64/10 shared range (RFC 6598) used by carrier-grade
## NAT and by overlay or mesh VPNs. The address is read the way [method LFUrl.classify_host]
## reads a host: the legacy numeric forms (`2130706433`, `0x0a.1`, `10.1`) and an
## IPv4-mapped IPv6 address (`::ffff:10.0.0.1`) count as the IPv4 address they carry.
## Loopback, link-local, public, host-name and other IPv6 addresses are false. Being
## private does not prove another machine can reach it (a firewall, a VPN or
## carrier-grade NAT address may not be reachable from the LAN).
static func is_private_ipv4(address: String, include_shared_range := true) -> bool:
	var text := address.strip_edges().to_lower()
	var dotted := text
	if text.contains(_IPV6_MARK):
		if !text.begins_with(_MAPPED_PREFIX):
			return false
		dotted = _mapped_dotted(text.trim_prefix(_MAPPED_PREFIX))
	else:
		dotted = LFUrl.ipv4_to_dotted(text)
	if dotted.is_empty() or LFUrl.classify_host(dotted) != LFUrl.CLASS_PRIVATE:
		return false
	if include_shared_range:
		return true
	var octets := dotted.split(_IPV4_SEPARATOR)
	return !(int(octets[0]) == _SHARED_FIRST and int(octets[1]) >= _SHARED_SECOND_MIN and int(octets[1]) <= _SHARED_SECOND_MAX)


## The dotted-decimal form of what follows `::ffff:` (a dotted quad, or two hex groups), or ''.
static func _mapped_dotted(rest: String) -> String:
	if rest.contains(_IPV4_SEPARATOR):
		return rest if rest.is_valid_ip_address() else ''
	var groups := rest.split(_IPV6_MARK)
	if groups.size() != 2 or !groups[0].is_valid_hex_number() or !groups[1].is_valid_hex_number() or groups[0].length() > 4 or groups[1].length() > 4:
		return ''
	var high := groups[0].hex_to_int()
	var low := groups[1].hex_to_int()
	return '%d.%d.%d.%d' % [high >> 8, high & 255, low >> 8, low & 255]


static func _is_link_local(address: String, v6: bool) -> bool:
	if v6:
		var lower := address.to_lower()
		for prefix: String in _IPV6_LINK_LOCAL_PREFIXES:
			if lower.begins_with(prefix):
				return true
		return false
	return address.begins_with(_IPV4_LINK_LOCAL_PREFIX)


## The file a process launch of `path` would run, or '' when there is none. A bare name
## (no directory separator) is searched in `PATH`; a path is checked as given (relative to
## the working directory). Unix requires an execute permission bit. Windows also tries each
## `PATHEXT` extension on a name without one. A macOS `.app` bundle resolves to its
## `Contents/MacOS/<CFBundleExecutable>`. `res://` and `user://` paths are globalized.
static func resolve_executable(path: String) -> String:
	if path.is_empty():
		return ''
	if path.begins_with(_RES_ROOT) or path.begins_with(_USER_ROOT):
		path = LFFile.to_absolute(path)
	var windows := OS.has_feature(_FEATURE_WINDOWS)
	if path.contains(_SEPARATOR) or (windows and path.contains(_WINDOWS_SEPARATOR)):
		return _executable_at(path, windows)
	for dir in OS.get_environment(_ENV_PATH).split(_WINDOWS_LIST_SEPARATOR if windows else _UNIX_LIST_SEPARATOR, false):
		var found := _executable_at(dir.path_join(path), windows)
		if not found.is_empty():
			return found
	return ''


static func _executable_at(path: String, windows: bool) -> String:
	var trimmed := path.trim_suffix(_SEPARATOR)
	if trimmed.ends_with(_APP_EXTENSION) and DirAccess.dir_exists_absolute(trimmed):
		return _bundle_executable(trimmed)
	if windows:
		if not path.get_extension().is_empty() and FileAccess.file_exists(path):
			return path
		var extensions: Array = _DEFAULT_PATHEXT
		if OS.has_environment(_ENV_PATHEXT):
			extensions = Array(OS.get_environment(_ENV_PATHEXT).split(_WINDOWS_LIST_SEPARATOR, false))
		for extension: Variant in extensions:
			if FileAccess.file_exists(path + str(extension)):
				return path + str(extension)
		return ''
	if not FileAccess.file_exists(path) or (FileAccess.get_unix_permissions(path) & _ANY_EXECUTE_BITS) == 0:
		return ''
	return path


## A bundle's executable from its Info.plist (XML form), else the binary named after it.
static func _bundle_executable(bundle: String) -> String:
	var name := bundle.get_file().get_basename()
	var plist := FileAccess.get_file_as_string(bundle.path_join(_BUNDLE_PLIST))
	var key := plist.find(_PLIST_EXECUTABLE_KEY)
	if key != -1:
		var open := plist.find(_PLIST_STRING_OPEN, key)
		var close := plist.find(_PLIST_STRING_CLOSE, open)
		if open != -1 and close != -1:
			name = plist.substr(open + _PLIST_STRING_OPEN.length(), close - open - _PLIST_STRING_OPEN.length()).strip_edges()
	return _executable_at(bundle.path_join(_BUNDLE_EXECUTABLE_DIR).path_join(name), false)


## Watches a process — typically the one that launched this one — and reports once it is
## gone. Call `tick(delta)` every frame (e.g. from `_process`); it asks
## `LFOS.is_pid_alive` once per interval. Where that check launches a command
## ([method LFOS.pid_check_runs_command]) it runs on an [LFThread], so `tick` doesn't wait
## for it and the answer arrives on a later tick; without thread support it runs, blocking,
## inside that later tick.
class PidWatchdog extends RefCounted:
	## Default for the check interval, in seconds.
	const DEFAULT_CHECK_INTERVAL_SECONDS := 2.0

	static var _log := LFLogger.new()

	## The watched process id; 0 or less watches nothing (never gone).
	var pid: int
	## Seconds between liveness checks. A NaN is rejected: reported through `LFLogger` as an
	## error, and the interval keeps its value.
	var check_interval_seconds: float:
		get:
			return _check_interval_seconds
		set(value):
			if is_nan(value):
				_log.error('LFOS.PidWatchdog: a NaN check_interval_seconds is rejected; keeping %s' % _check_interval_seconds)
				return
			_check_interval_seconds = value
	var _check_interval_seconds := DEFAULT_CHECK_INTERVAL_SECONDS
	var _elapsed := 0.0
	var _gone := false
	## The check started by `tick` and not yet collected, or null.
	var _check: LFThread = null
	## The pid `_check` is asking about; a result for another pid is dropped.
	var _check_pid := 0

	## Watches `watched_pid` (0 or less watches nothing), checking every `interval_seconds`
	## seconds.
	func _init(watched_pid: int, interval_seconds: float = DEFAULT_CHECK_INTERVAL_SECONDS) -> void:
		pid = watched_pid
		check_interval_seconds = interval_seconds

	## Advances the clock by `delta` seconds and checks when an interval has passed.
	## True once the process is gone, and on every call after that. When the check runs
	## a command, the tick that starts it returns false and a later tick reports it; the
	## next interval is counted from when the answer arrived.
	func tick(delta: float) -> bool:
		if _gone or pid <= 0:
			return _gone
		if _check != null:
			_collect()
			return _gone
		_elapsed += delta
		if _elapsed < check_interval_seconds:
			return false
		_elapsed = 0.0
		if not LFOS.pid_check_runs_command():
			_gone = not LFOS.is_pid_alive(pid)
			return _gone
		# The task captures only the pid, never this object (see LFThread).
		var watched := pid
		_check_pid = watched
		_check = LFThread.new()
		_check.start(func() -> bool: return LFOS.is_pid_alive(watched))
		return false

	## Whether a liveness check started by `tick` is waiting to be collected: running on a
	## worker thread, or, without thread support (or with `LFThread.force_main_thread`),
	## waiting to run, blocking, inside the next tick.
	func is_checking() -> bool:
		return _check != null

	func _collect() -> void:
		_check.poll()
		if not _check.is_done():
			return
		var result: Variant = _check.get_result()
		_check = null
		# Only a definite false means gone; a check that produced nothing (its task hit a
		# script error) counts as alive.
		var alive: bool = not (result is bool) or result
		if _check_pid == pid: # `pid` was reassigned while the check ran: drop the stale answer
			_gone = not alive

	## True once a check has found the process gone.
	func is_gone() -> bool:
		return _gone
