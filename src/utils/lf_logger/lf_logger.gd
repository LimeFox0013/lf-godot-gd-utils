## Prints log lines, warnings and errors that start with a fixed tag, like `[Loader]`.
##
## Each instance prints (or pushes to the debugger) its prefix plus a space-joined message
## through `log`/`warning`/`error`. Each can be silenced on its own with `enabled`, and
## each level for every logger at once with the static switches. Info lines (`log`) are
## off until `enable_print_logs` is turned on; warnings and errors report by default.
class_name LFLogger
extends RefCounted

## Put between consecutive message parts.
const _SEPARATOR := " "

## Whether `log` prints, for every logger in the process (a static switch). Off by
## default, so the library's info-level lines stay quiet until the game opts in.
static var enable_print_logs := false
## Whether `warning` reports, for every logger in the process (a static switch).
static var enable_print_warnings := true
## Whether `error` reports, for every logger in the process (a static switch).
static var enable_print_errors := true

## This logger alone; off silences it whatever the process-wide switches say.
var enabled := true

var _prefix: Array = []


## A logger starting every message with the parts of `prefix` (copied).
func _init(prefix: Array = []) -> void:
	set_prefix(prefix)


## Replaces the parts every message starts with (copied, so later edits to `prefix` don't
## leak in).
func set_prefix(prefix: Array = []) -> void:
	_prefix = prefix.duplicate()


## Prints the prefix and `messages` (any values, turned to text), space-separated, when
## this logger and `enable_print_logs` are on.
func log(...messages: Array) -> void:
	if enabled and LFLogger.enable_print_logs:
		print.callv(_parts(messages))


## Reports a warning (`push_warning`: yellow in the debugger) with the prefix and
## `messages`, when this logger and `enable_print_warnings` are on.
func warning(...messages: Array) -> void:
	if enabled and LFLogger.enable_print_warnings:
		push_warning.callv(_parts(messages))


## Reports an error (`push_error`: red in the debugger, and it does not stop the game) with
## the prefix and `messages`, when this logger and `enable_print_errors` are on.
func error(...messages: Array) -> void:
	if enabled and LFLogger.enable_print_errors:
		push_error.callv(_parts(messages))


## The prefix and `messages` with one space between consecutive parts; never empty.
func _parts(messages: Array) -> Array:
	var all := _prefix + messages
	if all.is_empty():
		return [""]
	var parts := []
	for i in all.size():
		if i > 0:
			parts.append(_SEPARATOR)
		parts.append(all[i])
	return parts
