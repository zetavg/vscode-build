#!/usr/bin/env bash

set -e

# Check if MS_TAG is provided as argument
if [[ -z "$1" ]]; then
    echo "Usage: $0 <MS_TAG>" >&2
    echo "Example: $0 1.102.3" >&2
    exit 1
fi

MS_TAG="$1"

# Support for GitHub Enterprise
GH_HOST="${GH_HOST:-github.com}"

# Set default repository
RELEASES_REPOSITORY="VSCodium/vscodium"

# Get GitHub token from environment
if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GITHUB_TOKEN}" ]] && [[ -z "${GH_ENTERPRISE_TOKEN}" ]] && [[ -z "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
    echo "Warning: No GitHub token found. API requests may be rate limited." >&2
    GITHUB_TOKEN=""
else
    GITHUB_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-${GH_ENTERPRISE_TOKEN:-${GITHUB_ENTERPRISE_TOKEN}}}}"
fi

# Function to make API request with optional authentication
make_api_request() {
    local url="$1"
    if [[ -n "${GITHUB_TOKEN}" ]]; then
        curl -s -H "Authorization: token ${GITHUB_TOKEN}" "${url}"
    else
        curl -s "${url}"
    fi
}

# Function to get releases page by page
get_releases() {
    local page=1
    local per_page=100
    local found_release=""

    while true; do
        local api_url="https://api.${GH_HOST}/repos/${RELEASES_REPOSITORY}/releases?page=${page}&per_page=${per_page}"
        local response

        response=$(make_api_request "${api_url}")

        # Check if we got a valid response
        if [[ -z "${response}" ]] || echo "${response}" | jq -e '.message' > /dev/null 2>&1; then
            echo "Error: Failed to fetch releases from ${RELEASES_REPOSITORY}" >&2
            if echo "${response}" | jq -e '.message' > /dev/null 2>&1; then
                echo "API Error: $(echo "${response}" | jq -r '.message')" >&2
            fi
            exit 1
        fi

        # Parse releases and look for matching version
        local releases_count
        releases_count=$(echo "${response}" | jq '. | length')

        if [[ "${releases_count}" -eq 0 ]]; then
            # No more releases to check
            break
        fi

        # Look for releases that match the MS_TAG pattern
        found_release=$(echo "${response}" | jq -r --arg ms_tag "${MS_TAG}" '
            map(select(.tag_name | test("^" + $ms_tag + "[0-9]+(-insider)?$"))) |
            sort_by(.tag_name) |
            reverse |
            .[0].tag_name // empty
        ')

        if [[ -n "${found_release}" ]]; then
            echo "${found_release}"
            return 0
        fi

        # Move to next page
        ((page++))

        # Safety check to avoid infinite loop (GitHub has a max of 1000 releases per repo)
        if [[ ${page} -gt 10 ]]; then
            break
        fi
    done

    # If no matching release found, return empty
    echo ""
    return 1
}

# Get the latest matching release
LATEST_MATCHING_RELEASE=$(get_releases)

if [[ -z "${LATEST_MATCHING_RELEASE}" ]]; then
    echo "Error: No matching release found for MS_TAG: ${MS_TAG}" >&2
    echo "Searched in repository: ${RELEASES_REPOSITORY}" >&2
    exit 1
fi

# Extract time patch from the release version
# For stable: 1.102.35058 -> extract 5058
# For insider: 1.102.35058-insider -> extract 5058
if [[ "${LATEST_MATCHING_RELEASE}" =~ ^${MS_TAG//./\.}([0-9]+)(-insider)?$ ]]; then
    TIME_PATCH="${BASH_REMATCH[1]}"
    echo "${LATEST_MATCHING_RELEASE}"
else
    echo "Error: Could not parse time patch from release: ${LATEST_MATCHING_RELEASE}" >&2
    exit 1
fi
