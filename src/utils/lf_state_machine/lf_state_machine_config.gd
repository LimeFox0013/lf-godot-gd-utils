## The setup an `LFStateMachine` is built from: its starting state, its transitions and its hooks.
class_name LFStateMachineConfig
extends RefCounted


## State the machine starts in.
var initial_state: int
## Every transition the machine knows.
var transitions: Array[LFStateTransition]
## Hooks indexed by the machine at construction; empty by default.
var hooks: Array[LFStateHook]


## A config starting in `start_state`, knowing `transition_list` and running `hook_list`
## (optional). The arrays are kept as given, not copied; the machine reads them once, when
## it is built.
func _init(
	start_state: int,
	transition_list: Array[LFStateTransition],
	hook_list: Array[LFStateHook] = [],
) -> void:
	initial_state = start_state
	transitions = transition_list
	hooks = hook_list
