#!/usr/bin/env bash
# Runs the library's GUT suite in a throwaway Godot project, with the library installed at
# res://vendor/library_under_test (not where it is developed, so a hardcoded install path fails the run)
# and GUT at res://addons/gut.
#
#   GODOT=/path/to/godot ci/run_tests.sh [path/to/addons/gut]
#
# Without a GUT path, the copy of GUT kept in ci/gut is used, so the run needs no network.
# (ci/.gdignore keeps that copy out of any project that has this repository inside it.)
set -euo pipefail

GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null || { echo "Godot not found: set GODOT=/path/to/godot" >&2; exit 1; }
CI="$(cd "$(dirname "$0")" && pwd)"
. "$CI/common.sh"
require_python
LIB="$(dirname "$CI")"
PROJECT="$(mktemp -d)"
USER_DATA=""
trap 'rm -rf "$PROJECT"; [ -n "$USER_DATA" ] && rm -rf "$USER_DATA"' EXIT

mkdir -p "$PROJECT/addons" "$PROJECT/vendor"
"$PYTHON" -I "$CI/copy_lib.py" "$(native "$LIB")" "$(native "$PROJECT")/vendor/library_under_test"

cp -R "${1:-$LIB/ci/gut}" "$PROJECT/addons/gut"

# A name of its own per run, so runs at the same time never share a user:// folder.
cat > "$PROJECT/project.godot" <<GODOT
config_version=5

[application]
config/name="lf-godot-gd-utils tests $(basename "$PROJECT")"
GODOT

cat > "$PROJECT/.gutconfig.json" <<'GUT'
{ "dirs": ["res://vendor/library_under_test"], "include_subdirs": true, "should_exit": true }
GUT

cd "$PROJECT"
# Where this run's user:// lives, so the exit trap removes it too.
printf 'extends SceneTree\nfunc _init() -> void:\n\tprint("USER_DATA=", OS.get_user_data_dir())\n\tquit()\n' > user_dir.gd
USER_DATA="$("$GODOT" --headless -s user_dir.gd 2>/dev/null | strip_cr | sed -n 's/^USER_DATA=//p')"
rm user_dir.gd
# Registers every class_name before the tests parse.
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json -gexit 2>&1 | tee gut.log
if grep -qE "^Failing Tests +[1-9]" gut.log; then echo "Tests failed." >&2; exit 1; fi
grep -qE "^Passing Tests +[1-9]" gut.log || { echo "No passing tests were reported." >&2; exit 1; }
