#!/usr/bin/env bash
# Smoke-tests LFHttp against a real local HTTP/1.1 server (127.0.0.1, ephemeral port):
# the max_body_bytes limit, Authorization dropped on a cross-origin redirect, and the
# frame counter advancing while a 5 MiB body is read. Needs python3.
#
#   GODOT=/path/to/godot ci/http_smoke.sh
#
# Like run_tests.sh, it installs the library in a throwaway project (no GUT needed).
# (ci/.gdignore keeps these files out of any project that has this repository inside it.)
set -euo pipefail

GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null || { echo "Godot not found: set GODOT=/path/to/godot" >&2; exit 1; }
CI="$(cd "$(dirname "$0")" && pwd)"
. "$CI/common.sh"
require_python
LIB="$(dirname "$CI")"
PROJECT="$(mktemp -d)"
SERVER_PID=""
trap '[ -n "$SERVER_PID" ] && { kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; } || true; rm -rf "$PROJECT"' EXIT

mkdir -p "$PROJECT/vendor"
"$PYTHON" -I "$CI/copy_lib.py" "$(native "$LIB")" "$(native "$PROJECT")/vendor/library_under_test"
cp "$CI/http_smoke.gd" "$PROJECT/http_smoke.gd"
cat > "$PROJECT/project.godot" <<GODOT
config_version=5

[application]
config/name="lf-godot-gd-utils http smoke $(basename "$PROJECT")"
GODOT

"$PYTHON" -I "$(native "$CI")/http_smoke_server.py" "$(native "$PROJECT")/port" &
SERVER_PID=$!
for _ in $(seq 300); do [ -s "$PROJECT/port" ] && break; sleep 0.1; done
[ -s "$PROJECT/port" ] || { echo "FAIL server did not start" >&2; exit 1; }
export LF_SMOKE_PORT="$(tr -d '\r\n' < "$PROJECT/port")"

cd "$PROJECT"
"$GODOT" --headless --import >/dev/null 2>&1 || true
if "$GODOT" --headless -s http_smoke.gd 2>&1 | tee smoke.log | grep -E "^(PASS|FAIL)"; then :; fi
if [ "${PIPESTATUS[0]}" -ne 0 ] || grep -q "^FAIL" smoke.log || ! grep -q "^PASS" smoke.log; then
	echo "FAIL http smoke" >&2; cat smoke.log >&2; exit 1
fi
echo "PASS http smoke"
