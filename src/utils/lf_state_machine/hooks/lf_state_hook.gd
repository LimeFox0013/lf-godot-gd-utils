## The empty base class of every `LFStateMachine` hook; create one of its subclasses instead.
##
## The subclasses are `LFTransitionGuard`, `LFStateExitHook`, `LFStateEnterHook` and
## `LFAfterTransitionHook`. An `LFStateHook` itself passed to a machine is reported and ignored.
class_name LFStateHook
extends RefCounted
