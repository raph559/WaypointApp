#!/usr/bin/env bash

set -euo pipefail

readonly source_root="${1:-Waypoint}"
readonly line_limit="${SWIFT_FILE_LINE_LIMIT:-400}"

if [[ ! -d "$source_root" ]]; then
  echo "error: Swift source directory not found: $source_root" >&2
  exit 1
fi

violations=0
checked=0

while IFS= read -r -d '' file; do
  lines="$(wc -l < "$file" | tr -d ' ')"
  checked=$((checked + 1))

  if (( lines > line_limit )); then
    echo "error: $file has $lines lines (limit: $line_limit)" >&2
    violations=$((violations + 1))
  fi
done < <(find "$source_root" -type f -name '*.swift' -print0 | sort -z)

if (( violations > 0 )); then
  echo "Swift source-size check failed for $violations file(s)." >&2
  exit 1
fi

echo "Swift source-size check passed for $checked files (limit: $line_limit)."
