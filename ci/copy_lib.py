"""Copies the library into a throwaway project for the scripts in ci/ (standard library only).

    python3 -I copy_lib.py <library> <destination>             the working tree, minus tooling
    python3 -I copy_lib.py --release <library> <destination>   what a release archive ships

The first form leaves out .git, .github, .idea, .claude and ci/ (tests stay in). The
second form copies what git tracks or would track, minus `export-ignore` paths and files
deleted in the working tree: the contents of the release zip, uncommitted changes included.
It replaces rsync, which Windows does not have.
"""
import os
import shutil
import subprocess
import sys

SKIPPED_ANYWHERE = {".git", ".idea"}
SKIPPED_AT_ROOT = {".github", ".claude", "ci"}


def copy_working_tree(library: str, destination: str) -> None:
    library = os.path.abspath(library)

    def ignore(directory: str, names: list) -> set:
        skipped = {name for name in names if name in SKIPPED_ANYWHERE}
        if os.path.abspath(directory) == library:
            skipped |= {name for name in names if name in SKIPPED_AT_ROOT}
        return skipped

    shutil.copytree(library, destination, ignore=ignore, dirs_exist_ok=True)


def release_files(library: str) -> list:
    listed = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=library,
            check=True, stdout=subprocess.PIPE).stdout
    if not listed:
        return []
    attributes = subprocess.run(["git", "check-attr", "-z", "--stdin", "export-ignore"], cwd=library,
            check=True, input=listed, stdout=subprocess.PIPE).stdout.split(b"\0")
    files = []
    # check-attr -z prints <path> NUL <attribute> NUL <value> NUL for each path.
    for i in range(0, len(attributes) - 2, 3):
        path = attributes[i].decode()
        if attributes[i + 2] != b"set" and os.path.lexists(os.path.join(library, path)):
            files.append(path)
    return files


def copy_release(library: str, destination: str) -> None:
    for path in release_files(library):
        target = os.path.join(destination, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(library, path), target)


def main() -> None:
    args = sys.argv[1:]
    release = bool(args) and args[0] == "--release"
    if release:
        args = args[1:]
    if len(args) != 2:
        sys.exit(__doc__)
    (copy_release if release else copy_working_tree)(args[0], args[1])


main()
