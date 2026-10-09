#!/usr/bin/env bash
# Installs the release contents (what users download: no tests, no tooling) into an empty
# Godot project at res://vendor/library_under_test, imports it, and fails on any script or scene error or
# any default GDScript warning. This checks that the library installs cleanly, without GUT
# or anything else, and shows no warnings in the editor.
#
#   GODOT=/path/to/godot ci/check_install.sh   (LF_CHECK_KEEP=1 keeps the project to inspect)
set -euo pipefail

GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null || { echo "Godot not found: set GODOT=/path/to/godot" >&2; exit 1; }
command -v git >/dev/null || { echo "git is required." >&2; exit 1; }
CI="$(cd "$(dirname "$0")" && pwd)"
. "$CI/common.sh"
require_python
LIB="$(dirname "$CI")"
PROJECT="$(mktemp -d)"
if [ -n "${LF_CHECK_KEEP:-}" ]; then
	echo "Keeping the project at $PROJECT"
else
	trap 'rm -rf "$PROJECT"' EXIT
fi

# The files a release archive ships: everything in the working tree that git tracks or
# would track, minus export-ignore (uncommitted changes included; a tracked file deleted
# or renamed in the working tree is skipped).
mkdir -p "$PROJECT/vendor/library_under_test"
"$PYTHON" -I "$CI/copy_lib.py" --release "$(native "$LIB")" "$(native "$PROJECT")/vendor/library_under_test"
if [ -n "$(find "$PROJECT/vendor/library_under_test" -path '*/tests/*' -print -quit)" ]; then
	echo "The archive ships tests." >&2
	exit 1
fi

cat > "$PROJECT/project.godot" <<'GODOT'
config_version=5

[application]
config/name="lf-godot-gd-utils install check"
GODOT

# Every GDScript warning this Godot version enables by default (the yellow ones a user
# sees in the editor) is raised to an error, so the library must load with none.
cat > "$PROJECT/list_warnings.gd" <<'GD'
extends SceneTree

func _init() -> void:
	for property in ProjectSettings.get_property_list():
		var setting: String = property.name
		if setting.begins_with("debug/gdscript/warnings/") and typeof(ProjectSettings.get_setting(setting)) == TYPE_INT and ProjectSettings.get_setting(setting) == 1:
			print("WARNING_SETTING ", setting.trim_prefix("debug/"), "=2")
	quit()
GD
(cd "$PROJECT" && "$GODOT" --headless -s list_warnings.gd 2>/dev/null) | strip_cr | sed -n 's/^WARNING_SETTING //p' > "$PROJECT/warnings.txt"
if [ ! -s "$PROJECT/warnings.txt" ]; then
	echo "Could not list the default GDScript warnings." >&2
	exit 1
fi
# Godot silences warnings under res://addons by default; check the library there too, since a
# project may install it anywhere.
{ printf '\n[debug]\n'; printf 'gdscript/warnings/directory_rules={}\n'; cat "$PROJECT/warnings.txt"; } >> "$PROJECT/project.godot"
rm "$PROJECT/list_warnings.gd"

# Loads every script and scene once, so a parse error or a broken reference surfaces.
cat > "$PROJECT/load_all.gd" <<'GD'
extends SceneTree

func _init() -> void:
	var failed := 0
	var checked := 0
	var pending := ["res://vendor/library_under_test"]
	while not pending.is_empty():
		var dir: String = pending.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			pending.append(dir.path_join(sub))
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd") or file.ends_with(".tscn"):
				var path: String = dir.path_join(file)
				checked += 1
				if load(path) == null:
					printerr("FAILED ", path)
					failed += 1
	print("checked %d scripts and scenes, %d failed" % [checked, failed])
	quit(1 if failed > 0 else 0)
GD

cd "$PROJECT"
"$GODOT" --headless --import 2>&1 | tee import.log >/dev/null || true
"$GODOT" --headless -s load_all.gd 2>&1 | tee load.log
if grep -E "SCRIPT ERROR|Parse Error|Failed to load|Cannot open file|Invalid UID|unrecognized UID|treated as error" import.log load.log; then
	echo "Install check found errors." >&2
	exit 1
fi
