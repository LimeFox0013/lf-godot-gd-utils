# Sourced by the other scripts in this folder (bash on Linux and macOS, Git Bash on Windows).
#
# - PYTHON: the Python 3 interpreter (`python3`, or `python` where that is the name).
# - native PATH: a path in the form the platform's own programs read: under Git Bash,
#   `/tmp/x` becomes `C:/Users/.../x`; elsewhere it is unchanged.
# - strip_cr: removes carriage returns from piped text (Godot's Windows console build
#   ends lines with CRLF).

PYTHON=""
for candidate in python3 python; do
	if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3)' >/dev/null 2>&1; then
		PYTHON="$candidate"
		break
	fi
done

native() {
	if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

strip_cr() {
	tr -d '\r'
}

require_python() {
	[ -n "$PYTHON" ] || { echo "python3 is required." >&2; exit 1; }
}
