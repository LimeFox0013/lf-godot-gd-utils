## Which teams fight on the same side: groups of mutually allied members, and a check for a pair.
##
## A member named in no group is allied with nobody except itself, even with another
## member named in no group. It knows nothing about what a member is: ids can be strings,
## numbers or anything that works as a dictionary key.
class_name LFAllianceGroups
extends RefCounted

var _group_of := {}


## Replaces every group. `groups` is an array of arrays; the members of one inner array are
## allied with each other. A member listed in several groups belongs to the last one.
func configure(groups: Array) -> void:
	_group_of.clear()
	for i in groups.size():
		for member: Variant in groups[i]:
			_group_of[member] = i


## Whether `a` and `b` are on the same side: the same member, or both in the same group.
func are_allied(a: Variant, b: Variant) -> bool:
	if a == b:
		return true
	var group: Variant = _group_of.get(a)
	return group != null and group == _group_of.get(b)
