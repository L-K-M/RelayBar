#!/usr/bin/env bash
# Guards the two ways the task-spec registry has actually gone wrong.
#
# 1. The accepted list drifts from the files beside it. The list once carried
#    18 fewer entries than the directory, and labelled one spec with another
#    spec's number, so it silently stopped being a record of what is taken.
# 2. Two specs claim the same number. That is invisible in any single branch
#    and only appears once both have merged.
#
# Numbers are checked across accepted and active specs together, because a
# number held by an active spec is just as taken as an archived one.
# Portable to BSD userland: no GNU-only find predicates, since this repo is
# developed on macOS and only validated on a Linux runner.
set -euo pipefail
cd "$(dirname "$0")/.."

archive="docs/task-specs/archive"
active="docs/task-specs"
status=0

listed=$(grep -oE '\([0-9]{3}-[^)]+\.md\)' "$archive/README.md" | tr -d '()' | sort -u)
present=$(cd "$archive" && ls -1 [0-9][0-9][0-9]-*.md 2>/dev/null | sort -u)

unlisted=$(comm -13 <(printf '%s\n' "$listed") <(printf '%s\n' "$present"))
phantom=$(comm -23 <(printf '%s\n' "$listed") <(printf '%s\n' "$present"))

if [ -n "$unlisted" ]; then
  echo "Accepted specs missing from $archive/README.md:" >&2
  printf '  %s\n' $unlisted >&2
  status=1
fi
if [ -n "$phantom" ]; then
  echo "$archive/README.md links to files that do not exist:" >&2
  printf '  %s\n' $phantom >&2
  status=1
fi

# A label may not disagree with the file it links to.
mismatched=$(grep -oE '\- \[Task ([0-9]{3})[^]]*\]\(([0-9]{3})-[^)]+\.md\)' "$archive/README.md" \
  | sed -E 's/- \[Task ([0-9]{3})[^]]*\]\(([0-9]{3})-.*/\1 \2/' \
  | awk '$1 != $2 { print }')
if [ -n "$mismatched" ]; then
  echo "$archive/README.md entries whose label number differs from their link:" >&2
  printf '  %s\n' "$mismatched" >&2
  status=1
fi

all_specs=$( (cd "$archive" && ls -1 [0-9][0-9][0-9]-*.md 2>/dev/null
               cd "$OLDPWD/$active" && ls -1 [0-9][0-9][0-9]-*.md 2>/dev/null) | sort -u)
duplicates=$(printf '%s\n' "$all_specs" | cut -c1-3 | sort | uniq -d)
if [ -n "$duplicates" ]; then
  echo "Task numbers claimed by more than one spec:" >&2
  for n in $duplicates; do
    printf '  %s: %s\n' "$n" "$(printf '%s\n' "$all_specs" | grep "^$n-" | tr '\n' ' ')" >&2
  done
  status=1
fi

[ "$status" -eq 0 ] && echo "Task-spec registry is consistent."
exit "$status"
