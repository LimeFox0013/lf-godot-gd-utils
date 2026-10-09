## Works out the tiers of a prerequisite graph, such as task dependencies, course prerequisites or a build order.
##
## The graph is given as a list of ids plus a "parents of" function you supply, so it can
## live in any data structure (a catalog, a scene, a save file). A parent is something
## that must come first (a prerequisite).
class_name LFGraph


## Walk-stack frame slot: the id being walked.
const _FRAME_ID := 0
## Walk-stack frame slot: that id's parents inside `ids`.
const _FRAME_PARENTS := 1
## Walk-stack frame slot: the index of the next parent to visit.
const _FRAME_NEXT := 2


## The layer depth of every id in `ids`: the length of the longest chain of parents that
## stays inside `ids` (0 = no parent inside `ids`). `parents_of.call(id)` returns an Array
## of parent ids (null counts as none); parents outside `ids` are ignored.
##
## Each id is visited once (memoised), so a dense graph costs about its edge count. A
## cycle terminates: a parent still being walked (the edge closing a cycle) is ignored, so
## every id still gets a depth. The walk is iterative, so a long chain can't overflow the
## call stack. Returns `{ id: depth }` in the order of `ids` (duplicates once).
static func layer_depths(ids: Array, parents_of: Callable) -> Dictionary:
	var members := {}
	for id: Variant in ids:
		members[id] = true
	var depths := {}
	# id -> true while it is on the walk stack.
	var walking := {}
	for root: Variant in ids:
		if depths.has(root):
			continue
		walking[root] = true
		var stack: Array = [[root, _parents_within(root, parents_of, members), 0]]
		while not stack.is_empty():
			var frame: Array = stack[-1]
			var parents: Array = frame[_FRAME_PARENTS]
			if frame[_FRAME_NEXT] < parents.size():
				var parent: Variant = parents[frame[_FRAME_NEXT]]
				frame[_FRAME_NEXT] += 1
				if not depths.has(parent) and not walking.has(parent):
					walking[parent] = true
					stack.append([parent, _parents_within(parent, parents_of, members), 0])
				continue
			var depth := 0
			for parent: Variant in parents:
				if depths.has(parent):
					depth = maxi(depth, depths[parent] + 1)
			depths[frame[_FRAME_ID]] = depth
			walking.erase(frame[_FRAME_ID])
			stack.pop_back()
	var ordered := {}
	for id: Variant in ids:
		ordered[id] = depths[id]
	return ordered


static func _parents_within(id: Variant, parents_of: Callable, members: Dictionary) -> Array:
	var parents: Variant = parents_of.call(id)
	var within: Array = []
	if parents == null:
		return within
	for parent: Variant in parents:
		if members.has(parent):
			within.append(parent)
	return within
