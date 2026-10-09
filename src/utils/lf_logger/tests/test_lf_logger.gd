extends GutTest

## The enable switches are process-wide statics, so every test restores the values it
## found, to avoid leaking state into the rest of the suite.

var _saved: Array


func before_each():
	_saved = [LFLogger.enable_print_logs, LFLogger.enable_print_warnings, LFLogger.enable_print_errors]
	LFLogger.enable_print_logs = true
	LFLogger.enable_print_warnings = true
	LFLogger.enable_print_errors = true


func after_each():
	LFLogger.enable_print_logs = _saved[0]
	LFLogger.enable_print_warnings = _saved[1]
	LFLogger.enable_print_errors = _saved[2]


func test_warning_produces_output_when_enabled():
	var logger = LFLogger.new(["[test]"])
	LFLogger.enable_print_warnings = true
	logger.warning("something")
	assert_push_warning("something")


func test_warning_produces_no_output_when_disabled():
	var logger = LFLogger.new(["[test]"])
	LFLogger.enable_print_warnings = false
	logger.warning("something")
	assert_push_warning_count(0)


func test_error_produces_output_when_enabled():
	var logger = LFLogger.new(["[test]"])
	LFLogger.enable_print_errors = true
	logger.error("broken")
	assert_push_error("broken")


func test_error_produces_no_output_when_disabled():
	var logger = LFLogger.new(["[test]"])
	LFLogger.enable_print_errors = false
	logger.error("broken")
	assert_push_error_count(0)


func test_message_parts_are_space_separated_without_a_trailing_space():
	LFLogger.new(["[p]"]).warning("a", "b")
	assert_push_warning("[p] a b")


func test_warning_includes_the_prefix_before_the_message():
	var logger = LFLogger.new(["[test]"])
	logger.warning("something")
	assert_push_warning("[test] something")


func test_error_includes_the_prefix_before_the_message():
	var logger = LFLogger.new(["[test]"])
	logger.error("broken")
	assert_push_error("[test] broken")


func test_set_prefix_replaces_the_prefix_used_by_later_messages():
	var logger = LFLogger.new(["[old]"])
	logger.set_prefix(["[new]"])
	logger.warning("something")
	assert_push_warning("[new] something")
	assert_push_warning_count(1, "the old prefix must be gone, not kept alongside")


func test_the_prefix_is_copied_not_shared():
	var prefix := ["[a]"]
	var logger := LFLogger.new(prefix)
	prefix.append("[b]")
	logger.warning("x")
	assert_push_warning("[a] x")


func test_a_message_with_no_parts_logs_just_the_prefix():
	LFLogger.new(["[p]"]).error()
	assert_push_error("[p]")
	LFLogger.new().error()
	assert_push_error_count(2, "even with no prefix it reports, without a script error")


func test_an_instance_can_be_silenced_on_its_own():
	var quiet := LFLogger.new(["[q]"])
	quiet.enabled = false
	quiet.warning("hidden")
	LFLogger.new(["[l]"]).warning("shown")
	assert_push_warning("[l] shown")
	assert_push_warning_count(1)


func test_log_prints_without_warning_or_error_and_honours_its_switches():
	var logger := LFLogger.new(["[p]"])
	logger.log("a", 1)
	logger.log()
	LFLogger.enable_print_logs = false
	logger.log("hidden")
	logger.enabled = false
	LFLogger.enable_print_logs = true
	logger.log("hidden")
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_info_logs_are_off_by_default_while_warnings_and_errors_report():
	# A separate compile of the class's source (minus its global name), so the suite's own
	# toggling of the shared statics can't hide the declared defaults.
	var copy := GDScript.new()
	copy.source_code = (LFLogger as GDScript).source_code.replace("class_name LFLogger", "")
	assert_eq(copy.reload(), OK)
	assert_eq(copy.get("enable_print_logs"), false, "info lines are opt-in")
	assert_eq(copy.get("enable_print_warnings"), true)
	assert_eq(copy.get("enable_print_errors"), true)


## Records every line the engine prints while installed with `OS.add_logger`.
class _PrintCapture:
	extends Logger
	var lines: Array[String] = []
	var _mutex := Mutex.new()

	func _log_message(message: String, error: bool) -> void:
		if error:
			return
		_mutex.lock()
		lines.append(message.strip_edges())
		_mutex.unlock()

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, _error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		pass

	func has_line(text: String) -> bool:
		_mutex.lock()
		var found := lines.has(text)
		_mutex.unlock()
		return found


func test_log_prints_the_prefix_and_parts_only_while_both_switches_are_on():
	var capture := _PrintCapture.new()
	OS.add_logger(capture)
	var logger := LFLogger.new(["[cap]"])
	logger.log("shown", 1, Vector2i(2, 3))
	LFLogger.enable_print_logs = false
	logger.log("hidden by the switch")
	LFLogger.enable_print_logs = true
	logger.enabled = false
	logger.log("hidden by the instance")
	OS.remove_logger(capture)

	assert_true(capture.has_line("[cap] shown 1 (2, 3)"), 'values of any type are turned to text')
	assert_false(capture.has_line("[cap] hidden by the switch"))
	assert_false(capture.has_line("[cap] hidden by the instance"))


func test_a_silenced_instance_reports_no_error_and_non_text_parts_become_text():
	var quiet := LFLogger.new(["[q]"])
	quiet.enabled = false
	quiet.error("hidden")
	assert_push_error_count(0)
	LFLogger.new(["[n]"]).error(42, null, [1])
	assert_push_error("[n] 42 <null> [1]")
