#!/bin/sh
# Stop hook for the testing skills. Blocks the end of a turn while a mutation marker is in the project, so a
# mutation that reaches the project's files by mistake must be restored before Claude can finish.
#
# Usage: check-mutation-markers.sh <glob>...   (for example '*.sol' '*.ts'; defaults to '*.sol')
# Exit 0 when the project is clean. Exit 2, with the files on stderr, when a marker remains.

marker='MUTANT-DO-NOT-COMMIT'
root="${CLAUDE_PROJECT_DIR:-$PWD}"
[ "$#" -gt 0 ] || set -- '*.sol'

if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  # Tracked and untracked files; ignored paths and submodules are skipped.
  hits=$(git -C "$root" grep -lI --untracked -e "$marker" -- "$@")
else
  hits=$(for glob in "$@"; do
    grep -rlI --include="$glob" --exclude-dir=node_modules --exclude-dir=lib -e "$marker" "$root"
  done)
fi

if [ -n "$hits" ]; then
  printf 'Mutation markers remain in the project:\n%s\nRestore these files, then finish.\n' "$hits" >&2
  exit 2
fi
