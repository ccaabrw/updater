#!/bin/sh
#
# update.sh - Make a shallow clone of a git repository in a temporary
# directory, let the user edit a file, then commit and push the change
# back to the source repository. The temporary clone is removed if all
# steps succeed; on error it is kept so that the work is not lost.
#
# Usage: update.sh [-b branch] [-m message] <repository> <file>
#
#   <repository>  URL or path of the existing git repository
#   <file>        path of the file to edit, relative to the repository root
#   -b branch     branch to clone and push to (default: remote default branch)
#   -m message    commit message (default: prompt for one)
#
# The editor is taken from $VISUAL, then $EDITOR, falling back to vi.

set -u

usage() {
    echo "Usage: $(basename "$0") [-b branch] [-m message] <repository> <file>" >&2
    exit 2
}

branch=""
message=""
while getopts "b:m:h" opt; do
    case "$opt" in
        b) branch="$OPTARG" ;;
        m) message="$OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[ $# -eq 2 ] || usage
repo="$1"
file="$2"

command -v git >/dev/null 2>&1 || { echo "Error: git is not installed or not on PATH" >&2; exit 1; }

# A local path must be given as a file:// URL for --depth to be honoured.
if [ -d "$repo" ]; then
    repo="file://$(cd "$repo" && pwd)"
fi

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/updater.XXXXXX") || { echo "Error: could not create temporary directory" >&2; exit 1; }

fail() {
    echo "Error: $1" >&2
    echo "Temporary clone left in: $tmpdir" >&2
    exit 1
}

# If the user interrupts, keep the clone and say where it is.
trap 'echo; fail "interrupted"' INT TERM

echo "Cloning $repo into $tmpdir ..."
if [ -n "$branch" ]; then
    set -- --branch "$branch"
else
    set --
fi
if ! git clone --depth 1 "$@" -- "$repo" "$tmpdir"; then
    rm -rf "$tmpdir"
    echo "Error: clone failed" >&2
    exit 1
fi

cd "$tmpdir" || fail "cannot change to $tmpdir"

newfile=0
if [ ! -e "$file" ]; then
    printf "File '%s' does not exist in the repository. Create it? [y/N] " "$file"
    read -r answer
    case "$answer" in
        [Yy]*) { mkdir -p "$(dirname -- "$file")" && : > "$file"; } || fail "cannot create $file"
               newfile=1 ;;
        *) cd / && rm -rf "$tmpdir"
           echo "Error: file '$file' not found" >&2
           exit 1 ;;
    esac
fi

editor="${VISUAL:-${EDITOR:-vi}}"
# $editor is intentionally unquoted so that values such as "code --wait" work.
# shellcheck disable=SC2086
$editor "$file" || fail "editor exited with an error"

no_changes() {
    echo "No changes made to $file; nothing to commit."
    cd / && rm -rf "$tmpdir"
    exit 0
}

# A newly created file that is still empty is treated as unchanged.
if [ "$newfile" -eq 1 ] && [ ! -s "$file" ]; then
    no_changes
fi

git add -- "$file" || fail "git add failed"
git diff --cached --quiet && no_changes

if [ -z "$message" ]; then
    printf "Commit message [Update %s]: " "$file"
    read -r message
    [ -n "$message" ] || message="Update $file"
fi

git commit -m "$message" || fail "git commit failed"
git push origin HEAD || fail "git push failed"

{ cd / && rm -rf "$tmpdir"; } || { echo "Warning: could not remove $tmpdir" >&2; exit 1; }
echo "Changes pushed successfully; temporary clone removed."
