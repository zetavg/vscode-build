#!/usr/bin/env bash
# Resolve the actual git tag on Microsoft's vscode repo for a given MS_TAG.
#
# Usage: ./resolve_ms_tag.sh <MS_TAG> [git_remote]
#
# Examples:
#   ./resolve_ms_tag.sh 1.110.0          # outputs "1.110" if 1.110.0 doesn't exist but 1.110 does
#   ./resolve_ms_tag.sh 1.109.1          # outputs "1.109.1" (tag exists as-is)
#   ./resolve_ms_tag.sh 1.110.12345      # exits with error
#
# The git_remote can be a URL or a named remote (when run inside a git repo).
# Defaults to https://github.com/Microsoft/vscode.git

set -e

if [[ -z "$1" ]]; then
  echo "Usage: $0 <MS_TAG> [git_remote]" >&2
  exit 1
fi

MS_TAG="$1"
GIT_REMOTE="${2:-https://github.com/Microsoft/vscode.git}"

# Check if the exact tag exists
if git ls-remote --tags "${GIT_REMOTE}" "refs/tags/${MS_TAG}" 2>/dev/null | grep -q .; then
  echo "${MS_TAG}"
  exit 0
fi

# If the tag ends with .0, try without the .0 suffix
# (e.g., Microsoft may tag as 1.110 instead of 1.110.0)
if [[ "${MS_TAG}" =~ \.0$ ]]; then
  MS_TAG_SHORT="${MS_TAG%.0}"
  if git ls-remote --tags "${GIT_REMOTE}" "refs/tags/${MS_TAG_SHORT}" 2>/dev/null | grep -q .; then
    echo "${MS_TAG_SHORT}"
    exit 0
  fi
fi

echo "Error: No matching tag found for '${MS_TAG}' on ${GIT_REMOTE}" >&2
exit 1
