extends GutTest

## Keeps LF_INDEX.md honest: every folder under `src/` is a module group, every module
## folder (`src/<group>/lf_*`) has a README and GUT tests, every `class_name` the library
## declares (tests excluded) and every public inner class declared at the top level of a
## script (`Outer.Inner`) is named in the first cell of a class-table row, and every table
## in the index has the same cell count in its header, separator and rows. Also keeps the
## library installable anywhere: every relative Markdown link `[text](target)` resolves
## (links with a title or a space, reference-style links and HTML `src=` are not checked),
## and no file names the folder the library is installed in, as a `res://` path or, when
## that folder is nested (`res://a/b`), as the bare `a/b`. Hidden folders and folders with
## a `.gdignore` are not scanned. The root README's module count and module list match the
## folders.

## The folder that holds the module groups, relative to the library root.
const SOURCE_DIR := "src"
const GROUPS := ["components", "2D", "3D", "utils"]
## Text files checked for the install folder's path.
const TEXT_EXTENSIONS := ["gd", "tscn", "tres", "md", "cfg", "json", "sh", "yml"]

var _lib_dir: String
var _index: String
## Every name written in backticks in the first cell of a class-table row.
var _row_names := {}


func before_all():
	# This file sits at <lib>/tests/, wherever the library is installed.
	_lib_dir = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	_index = FileAccess.get_file_as_string(_lib_dir.path_join("LF_INDEX.md"))
	var name_regex := RegEx.create_from_string("`([A-Za-z_][\\w.]*)`")
	for table in _tables():
		if table[0].cells.is_empty() or table[0].cells[0] != "Class":
			continue
		for row in table.slice(2):
			for found in name_regex.search_all(row.cells[0]):
				_row_names[found.get_string(1)] = true


func test_the_index_exists():
	assert_false(_index.is_empty(), "LF_INDEX.md is readable at the library root")


func test_the_library_has_modules():
	assert_gt(_modules().size(), 0)


func test_the_index_has_class_tables():
	assert_gt(_row_names.size(), 0, "LF_INDEX.md has tables headed `| Class | … |`")


func test_every_source_folder_is_a_group():
	# A folder outside GROUPS would hide its modules from every check below.
	for name in DirAccess.get_directories_at(_lib_dir.path_join(SOURCE_DIR)):
		assert_true(name in GROUPS, "%s/%s is one of the module groups %s" % [SOURCE_DIR, name, GROUPS])


func test_every_module_has_a_readme():
	for module in _modules():
		assert_true(FileAccess.file_exists(module.path_join("README.md")), "%s has a README.md" % module)


func test_every_module_has_gut_tests():
	for module in _modules():
		var tests := DirAccess.get_files_at(module.path_join("tests"))
		var gut_tests := Array(tests).filter(func(f: String): return f.begins_with("test_") and f.ends_with(".gd"))
		assert_gt(gut_tests.size(), 0, "%s has tests/test_*.gd" % module)


func test_the_readme_states_the_module_count_and_names_every_module():
	var readme := FileAccess.get_file_as_string(_lib_dir.path_join("README.md"))
	var modules := _modules()
	assert_true(readme.contains("**%d small GDScript modules" % modules.size()), "README.md states %d modules in its headline" % modules.size())
	assert_true(readme.contains("%d modules in four groups" % modules.size()), "README.md states %d modules in What's inside" % modules.size())
	for module in modules:
		assert_true(readme.contains("`%s`" % module.get_file()), "README.md names %s" % module.get_file())


func test_every_class_is_the_first_cell_of_a_row():
	for entry in _declared_classes():
		assert_true(_row_names.has(entry.name), "%s (%s) is named in the first cell of a row in LF_INDEX.md" % [entry.name, entry.file])


func test_every_relative_link_in_the_docs_resolves():
	var link_regex := RegEx.create_from_string("\\]\\(([^)\\s]+)\\)")
	for doc in _files(_lib_dir, ["md"]):
		var source := FileAccess.get_file_as_string(doc)
		for found in link_regex.search_all(source):
			var target := found.get_string(1).get_slice("#", 0)
			if target.is_empty() or target.contains("://") or target.begins_with("mailto:"):
				continue
			var resolved := doc.get_base_dir().path_join(target).simplify_path()
			assert_true(FileAccess.file_exists(resolved) or DirAccess.dir_exists_absolute(resolved),
				"%s: the link to %s resolves" % [doc.trim_prefix(_lib_dir + "/"), found.get_string(1)])


func test_no_file_names_the_install_folder():
	# Wherever the library sits, nothing in it may depend on that place: scenes reference
	# their scripts by file name or uid, and code resolves paths from resource_path.
	if _lib_dir.ends_with("://"):
		pass_test("installed at the project root, which every res:// path names")
		return
	var install := _lib_dir.trim_suffix("/")
	var patterns := ["(?<![\\w.-])%s(?![\\w-])" % _escape(install)]
	var relative := install.trim_prefix("res://")
	if relative.contains("/"):
		patterns.append("(?<![\\w.:/-])%s(?![\\w-])" % _escape(relative))
	for file in _files(_lib_dir, TEXT_EXTENSIONS):
		var source := FileAccess.get_file_as_string(file)
		for pattern in patterns:
			assert_true(RegEx.create_from_string(pattern).search(source) == null,
				"%s does not name the install folder %s" % [file.trim_prefix(_lib_dir + "/"), install])


func test_scenes_reference_resources_relatively():
	var absolute_regex := RegEx.create_from_string("path=\"res://")
	for scene in _files(_lib_dir.path_join(SOURCE_DIR), ["tscn", "tres"]):
		assert_true(absolute_regex.search(FileAccess.get_file_as_string(scene)) == null,
			"%s references its resources by file name or uid, not a res:// path" % scene.trim_prefix(_lib_dir + "/"))


func test_every_table_has_one_cell_count():
	for table in _tables():
		var header: Dictionary = table[0]
		assert_gt(table.size(), 1, "the table at LF_INDEX.md:%d has a separator row" % header.line)
		if table.size() < 2:
			continue
		assert_true(table[1].separator, "LF_INDEX.md:%d is a separator row under its header" % table[1].line)
		for row in table:
			assert_eq(row.cells.size(), header.cells.size(),
				"LF_INDEX.md:%d has as many cells as its table's header (LF_INDEX.md:%d)" % [row.line, header.line])


## Each `class_name` in the library's scripts (any folder but `tests/`), and each inner
## class at a script's top level whose name does not start with `_`, as `Outer.Inner`;
## with the file it is declared in.
func _declared_classes() -> Array[Dictionary]:
	var top_regex := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	var inner_regex := RegEx.create_from_string("(?m)^class\\s+([A-Za-z]\\w*)")
	var found: Array[Dictionary] = []
	for script_path in _files(_lib_dir, ["gd"]):
		var file := script_path.trim_prefix(_lib_dir + "/")
		if file.begins_with("tests/") or file.contains("/tests/"):
			continue
		var source := FileAccess.get_file_as_string(script_path)
		var top := top_regex.search(source)
		if top:
			found.append({name = top.get_string(1), file = file})
		for inner in inner_regex.search_all(source):
			var outer := top.get_string(1) + "." if top else ""
			found.append({name = outer + inner.get_string(1), file = file})
	return found


## The index's Markdown tables: each an Array of rows, a row being
## `{line, cells, separator}`, starting at the header.
func _tables() -> Array:
	var tables := []
	var current := []
	var lines := _index.split("\n")
	for i in lines.size():
		var text := lines[i].strip_edges()
		if not text.begins_with("|"):
			if not current.is_empty():
				tables.append(current)
				current = []
			continue
		var cells := Array(text.replace("\\|", "").trim_prefix("|").trim_suffix("|").split("|")).map(
			func(c: String) -> String: return c.strip_edges())
		var separator := cells.all(func(c: String) -> bool: return c.begins_with("---") or c.begins_with(":-"))
		current.append({line = i + 1, cells = cells, separator = separator})
	if not current.is_empty():
		tables.append(current)
	return tables


## Every `src/<group>/lf_*` folder.
func _modules() -> Array[String]:
	var found: Array[String] = []
	for group in GROUPS:
		var group_dir := _lib_dir.path_join(SOURCE_DIR).path_join(group)
		for name in DirAccess.get_directories_at(group_dir):
			if name.begins_with("lf_"):
				found.append(group_dir.path_join(name))
	return found


## Every file under `dir` with one of `extensions`, skipping hidden folders and folders
## Godot ignores (a `.gdignore` marks third-party tooling, such as the copy of GUT CI uses).
func _files(dir: String, extensions: Array) -> Array[String]:
	var found: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in extensions:
			found.append(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with(".") and not FileAccess.file_exists(dir.path_join(sub).path_join(".gdignore")):
			found.append_array(_files(dir.path_join(sub), extensions))
	return found


## `text` with every regex metacharacter escaped.
func _escape(text: String) -> String:
	var escaped := ""
	for c in text:
		escaped += "\\" + c if c in "\\^$.|?*+()[]{}" else c
	return escaped
