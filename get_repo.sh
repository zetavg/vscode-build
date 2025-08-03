#!/usr/bin/env bash
# shellcheck disable=SC2129

set -e

# git workaround
if [[ "${CI_BUILD}" != "no" ]]; then
  git config --global --add safe.directory "/__w/$( echo "${GITHUB_REPOSITORY}" | awk '{print tolower($0)}' )"
fi

if [[ -z "${RELEASE_VERSION}" ]]; then
  if [[ "${VSCODE_LATEST}" == "yes" ]] || [[ ! -f "./upstream/${VSCODE_QUALITY}.json" ]]; then
    echo "Retrieve lastest version"
    UPDATE_INFO=$( curl --silent --fail "https://update.code.visualstudio.com/api/update/darwin/${VSCODE_QUALITY}/0000000000000000000000000000000000000000" )
  else
    echo "Get version from ${VSCODE_QUALITY}.json"
    MS_COMMIT=$( jq -r '.commit' "./upstream/${VSCODE_QUALITY}.json" )
    MS_TAG=$( jq -r '.tag' "./upstream/${VSCODE_QUALITY}.json" )
  fi

  if [[ -z "${MS_COMMIT}" ]]; then
    MS_COMMIT=$( echo "${UPDATE_INFO}" | jq -r '.version' )
    MS_TAG=$( echo "${UPDATE_INFO}" | jq -r '.name' )

    if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
      MS_TAG="${MS_TAG/\-insider/}"
    fi
  fi

  # Get the latest matching release version from VSCodium/vscodium releases
  # This ensures we use a TIME_PATCH that corresponds to an existing release
  LATEST_MATCHING_RELEASE=$( ./get_time_patch.sh "${MS_TAG}" )

  if [[ -n "${LATEST_MATCHING_RELEASE}" ]]; then
    # Extract TIME_PATCH from the existing release
    if [[ "${LATEST_MATCHING_RELEASE}" =~ ^${MS_TAG//./\.}([0-9]+)(-insider)?$ ]]; then
      TIME_PATCH="${BASH_REMATCH[1]}"
      echo "Using TIME_PATCH from existing release: ${TIME_PATCH}"
    else
      echo "Error: Could not parse TIME_PATCH from VSCodium/vscodium version ${LATEST_MATCHING_RELEASE}."
      exit 1
    fi
  else
    echo "Error: No matching VSCodium/vscodium release found."
    exit 1
  fi

  if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
    RELEASE_VERSION="${MS_TAG}${TIME_PATCH}-insider"
  else
    RELEASE_VERSION="${MS_TAG}${TIME_PATCH}"
  fi
else
  if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
    if [[ "${RELEASE_VERSION}" =~ ^([0-9]+\.[0-9]+\.[0-5])[0-9]+-insider$ ]];
    then
      MS_TAG="${BASH_REMATCH[1]}"
    else
      echo "Error: Bad RELEASE_VERSION: ${RELEASE_VERSION}"
      exit 1
    fi
  else
    if [[ "${RELEASE_VERSION}" =~ ^([0-9]+\.[0-9]+\.[0-5])[0-9]+$ ]];
    then
      MS_TAG="${BASH_REMATCH[1]}"
    else
      echo "Error: Bad RELEASE_VERSION: ${RELEASE_VERSION}"
      exit 1
    fi
  fi

  if [[ "${MS_TAG}" == "$( jq -r '.tag' "./upstream/${VSCODE_QUALITY}.json" )" ]]; then
    MS_COMMIT=$( jq -r '.commit' "./upstream/${VSCODE_QUALITY}.json" )
  else
    echo "Error: No MS_COMMIT for ${RELEASE_VERSION}"
    exit 1
  fi
fi

echo "RELEASE_VERSION=\"${RELEASE_VERSION}\""

mkdir -p vscode
cd vscode || { echo "'vscode' dir not found"; exit 1; }

git init -q
git remote add origin https://github.com/Microsoft/vscode.git
git remote add patches https://github.com/zetavg/vscode.git

# figure out latest tag by calling MS update API
if [[ -z "${MS_TAG}" ]]; then
  UPDATE_INFO=$( curl --silent --fail "https://update.code.visualstudio.com/api/update/darwin/${VSCODE_QUALITY}/0000000000000000000000000000000000000000" )
  MS_COMMIT=$( echo "${UPDATE_INFO}" | jq -r '.version' )
  MS_TAG=$( echo "${UPDATE_INFO}" | jq -r '.name' )
elif [[ -z "${MS_COMMIT}" ]]; then
  REFERENCE=$( git ls-remote --tags | grep -x ".*refs\/tags\/${MS_TAG}" | head -1 )

  if [[ -z "${REFERENCE}" ]]; then
    echo "Error: The following tag can't be found: ${MS_TAG}"
    exit 1
  elif [[ "${REFERENCE}" =~ ^([[:alnum:]]+)[[:space:]]+refs\/tags\/([0-9]+\.[0-9]+\.[0-5])$ ]]; then
    MS_COMMIT="${BASH_REMATCH[1]}"
    MS_TAG="${BASH_REMATCH[2]}"
  else
    echo "Error: The following reference can't be parsed: ${REFERENCE}"
    exit 1
  fi
fi

echo "MS_TAG=\"${MS_TAG}\""
echo "MS_COMMIT=\"${MS_COMMIT}\""

# Since we are doing rebases, we need to set the user name and email
if [[ "${CI}" == "true" ]]; then
  git config --global user.email "ci@github.com"
  git config --global user.name "CI"
fi

echo "Fetching origin..."
git fetch --depth 20000 origin "${MS_COMMIT}"
echo "Fetching patches..."
git fetch --depth 100 patches main
echo "Preparing build branch..."
git checkout patches/main
PATCHES_COMMIT=$( git rev-parse HEAD )
git checkout -b ci-build
echo "Rebasing patches..."
git rebase "${MS_COMMIT}"

cd ..

# for GH actions
if [[ "${GITHUB_ENV}" ]]; then
  echo "MS_TAG=${MS_TAG}" >> "${GITHUB_ENV}"
  echo "MS_COMMIT=${MS_COMMIT}" >> "${GITHUB_ENV}"
  echo "PATCHES_COMMIT=${PATCHES_COMMIT}" >> "${GITHUB_ENV}"
  echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "${GITHUB_ENV}"
fi

export MS_TAG
export MS_COMMIT
export PATCHES_COMMIT
export RELEASE_VERSION
