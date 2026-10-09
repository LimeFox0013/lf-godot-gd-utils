## Creates an LF component scene from its short name, such as `"layout_control"`.
##
## The name is turned into a path by the naming convention
## `lf_<name>/lf_<name>.tscn`, found next to this script wherever the library is
## installed. Static: call its functions on the class, never `.new()` it.
class_name LFComponents

## Prefix every component folder and scene name carries before the short name.
const _NAME_PREFIX := 'lf_'
## File extension of a component scene.
const _SCENE_EXTENSION := '.tscn'
## Separator between the parts of a resource path.
const _PATH_SEPARATOR := '/'

static var _log := LFLogger.new()

## Cached result of `components_dir()`.
static var _components_dir := ""


## The folder holding the component folders: the parent of this script's own folder
## (wherever the library is installed), with a trailing slash.
static func components_dir() -> String:
	if _components_dir.is_empty():
		var script_path: String = (LFComponents as Script).resource_path
		_components_dir = script_path.get_base_dir().get_base_dir() + _PATH_SEPARATOR
	return _components_dir


## Instantiates `lf_<component_name>/lf_<component_name>.tscn` and returns the new node,
## not yet added to the tree. Returns null and pushes an error when the name is not a
## plain identifier (ASCII letters, digits and `_`, not starting with a digit) or that
## component has no scene.
static func init_component(component_name: String) -> Node:
	if not component_name.is_valid_identifier():
		_log.error('LFComponents: "%s" is not a component name' % component_name)
		return null
	var prefixed_name := _NAME_PREFIX + component_name
	var path := components_dir() + prefixed_name + _PATH_SEPARATOR + prefixed_name + _SCENE_EXTENSION
	if not ResourceLoader.exists(path):
		_log.error('LFComponents: "%s" has no scene at %s' % [component_name, path])
		return null
	return load(path).instantiate()


## Instantiates the component (as `init_component` does), adds it as a child of
## `parent_node` and returns it. Returns null and pushes an error when `parent_node` is
## null (nothing is created then) or the component has no scene. Its `_ready()` has run
## on return only when `parent_node` is in the tree.
static func create_component(component_name: String, parent_node: Node) -> Node:
	if parent_node == null:
		_log.error('LFComponents: no parent to add "%s" to' % component_name)
		return null
	var component := init_component(component_name)
	if component == null:
		return null
	parent_node.add_child(component)
	return component
