#!/usr/bin/env bash
# shellcheck disable=SC2129

# Env Paramaters
# CHECK_ALL: yes | no
# CHECK_REH: yes | no
# CHECK_ONLY_REH: yes | no
# FORCE_LINUX_SNAP: true

set -e

if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GITHUB_TOKEN}" ]] && [[ -z "${GH_ENTERPRISE_TOKEN}" ]] && [[ -z "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
  echo "Will not build because no GITHUB_TOKEN defined"
  exit 0
else
  GITHUB_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-${GH_ENTERPRISE_TOKEN:-${GITHUB_ENTERPRISE_TOKEN}}}}"
fi

# Support for GitHub Enterprise
GH_HOST="${GH_HOST:-github.com}"

APP_NAME_LC="$( echo "${APP_NAME}" | awk '{print tolower($0)}' )"

if [[ "${SHOULD_DEPLOY}" == "no" ]]; then
  ASSETS="null"
else
  # If RELEASE_VERSION is already set (from workflow input), use that specific version
  # Otherwise query the latest release
  if [[ -n "${RELEASE_VERSION}" ]]; then
    # Construct the tag name with patch suffix
    RELEASE_TAG="${RELEASE_VERSION}-p${PATCHES_COMMIT:0:7}"
    echo "Checking specific release '${RELEASE_TAG}' from GitHub API for repository ${ASSETS_REPOSITORY}..."
    GITHUB_RESPONSE=$( curl -s -H "Authorization: token ${GITHUB_TOKEN}" "https://api.${GH_HOST}/repos/${ASSETS_REPOSITORY}/releases/tags/${RELEASE_TAG}" )
    LATEST_VERSION="${RELEASE_VERSION}"
    PATCHES_COMMIT_SHORT_HASH="${PATCHES_COMMIT:0:7}"
  else
    echo "Checking latest release from GitHub API for repository ${ASSETS_REPOSITORY}..."
    GITHUB_RESPONSE=$( curl -s -H "Authorization: token ${GITHUB_TOKEN}" "https://api.${GH_HOST}/repos/${ASSETS_REPOSITORY}/releases/latest" )
    LATEST_VERSION=$( echo "${GITHUB_RESPONSE}" | jq -c -r '.tag_name' )

    # If the tag format is `<version>-p<hash>`, e.g. `1.85.1-pabc1234`
    # Extract the patch commit short hash and strip the suffix for later comparison
    if [[ "${LATEST_VERSION}" =~ -p([0-9a-f]+)$ ]]; then
      PATCHES_COMMIT_SHORT_HASH="${BASH_REMATCH[1]}"
      LATEST_VERSION="${LATEST_VERSION%-p${PATCHES_COMMIT_SHORT_HASH}}"
    else
      PATCHES_COMMIT_SHORT_HASH=""
    fi
  fi

  RECHECK_ASSETS="${SHOULD_BUILD}"

  if [[ "${LATEST_VERSION}" =~ ^([0-9]+\.[0-9]+\.[0-5]) ]]; then
    if [[ "${MS_TAG}" != "${BASH_REMATCH[1]}" ]]; then
      echo "New VSCode version, new build"
      export SHOULD_BUILD="yes"
    elif [[ -n "${PATCHES_COMMIT_SHORT_HASH}" ]] && [[ "${PATCHES_COMMIT}" != "${PATCHES_COMMIT_SHORT_HASH}"* ]]; then
      echo "Patches have been updated, new build"
      export SHOULD_BUILD="yes"
    elif [[ "${NEW_RELEASE}" == "true" ]]; then
      echo "New release build"
      export SHOULD_BUILD="yes"
    elif [[ "${VSCODE_QUALITY}" == "insider" ]]; then
      BODY=$( echo "${GITHUB_RESPONSE}" | jq -c -r '.body' )

      if [[ "${BODY}" =~ \[([a-z0-9]+)\] ]]; then
        if [[ "${MS_COMMIT}" != "${BASH_REMATCH[1]}" ]]; then
          echo "New VSCode Insiders version, new build"
          export SHOULD_BUILD="yes"
        fi
      fi
    fi

    if [[ "${SHOULD_BUILD}" != "yes" ]]; then
      export RELEASE_VERSION="${LATEST_VERSION}"
      echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "${GITHUB_ENV}"

      echo "Switch to release version: ${RELEASE_VERSION}"

      ASSETS=$( echo "${GITHUB_RESPONSE}" | jq -c '.assets | map(.name)?' )
    elif [[ "${RECHECK_ASSETS}" == "yes" ]]; then
      export SHOULD_BUILD="no"

      ASSETS=$( echo "${GITHUB_RESPONSE}" | jq -c '.assets | map(.name)?' )
    else
      ASSETS="null"
    fi
  else
    echo "can't check assets"
    exit 1
  fi
fi

contains() {
  # add " to match the end of a string so any hashs won't be matched by mistake
  echo "${ASSETS}" | grep "${1}\""
}

# shellcheck disable=SC2153
if [[ "${CHECK_ASSETS}" == "no" ]]; then
  echo "Don't check assets, yet"
elif [[ "${ASSETS}" != "null" ]]; then
  if [[ "${IS_SPEARHEAD}" == "yes" ]]; then
    if [[ -z $( contains "${APP_NAME}-${RELEASE_VERSION}-src.tar.gz" ) || -z $( contains "${APP_NAME}-${RELEASE_VERSION}-src.zip" ) ]]; then
      echo "Building because we have no SRC"
      export SHOULD_BUILD="yes"
      export SHOULD_BUILD_SRC="yes"
    fi
  # macos
  elif [[ "${OS_NAME}" == "osx" ]]; then
    . ./build/osx/check_tags.sh
  elif [[ "${OS_NAME}" == "windows" ]]; then
    . ./build/windows/check_tags.sh
  else
    if [[ "${OS_NAME}" == "linux" ]]; then
      . ./build/linux/check_tags.sh
    fi

    if [[ "${OS_NAME}" == "alpine" ]] || [[ "${OS_NAME}" == "linux" && "${CHECK_ALL}" == "yes" ]]; then
      . ./build/alpine/check_tags.sh
    fi
  fi
else
  if [[ "${IS_SPEARHEAD}" == "yes" ]]; then
    export SHOULD_BUILD_SRC="yes"
  elif [[ "${OS_NAME}" == "linux" ]]; then
    if [[ "${VSCODE_ARCH}" == "riscv64" ]]; then
      SHOULD_BUILD_DEB="no"
      SHOULD_BUILD_RPM="no"
      SHOULD_BUILD_CLI="no"
    elif [[ "${VSCODE_ARCH}" == "loong64" ]]; then
      SHOULD_BUILD_DEB="no"
      SHOULD_BUILD_RPM="no"
      SHOULD_BUILD_CLI="no"
    elif [[ "${VSCODE_ARCH}" == "s390x" ]]; then
      SHOULD_BUILD_DEB="no"
      SHOULD_BUILD_RPM="no"
      SHOULD_BUILD_CLI="no"
    fi
    if [[ "${VSCODE_ARCH}" != "x64" || "${DISABLE_APPIMAGE}" == "yes" ]]; then
      export SHOULD_BUILD_APPIMAGE="no"
    fi
  elif [[ "${OS_NAME}" == "windows" ]]; then
    if [[ "${VSCODE_ARCH}" == "arm64" ]]; then
      export SHOULD_BUILD_REH="no"
      export SHOULD_BUILD_REH_WEB="no"
    fi
    if [[ "${DISABLE_MSI}" == "yes" ]]; then
      export SHOULD_BUILD_MSI="no"
      export SHOULD_BUILD_MSI_NOUP="no"
    fi
  fi

  echo "Release assets do not exist at all, continuing build"
  export SHOULD_BUILD="yes"
fi


echo "SHOULD_BUILD=${SHOULD_BUILD}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_APPIMAGE=${SHOULD_BUILD_APPIMAGE}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_DEB=${SHOULD_BUILD_DEB}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_DMG=${SHOULD_BUILD_DMG}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_EXE_SYS=${SHOULD_BUILD_EXE_SYS}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_EXE_USR=${SHOULD_BUILD_EXE_USR}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_MSI=${SHOULD_BUILD_MSI}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_MSI_NOUP=${SHOULD_BUILD_MSI_NOUP}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_REH=${SHOULD_BUILD_REH}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_REH_WEB=${SHOULD_BUILD_REH_WEB}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_CLI=${SHOULD_BUILD_CLI}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_RPM=${SHOULD_BUILD_RPM}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_SNAP=${SHOULD_BUILD_SNAP}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_TAR=${SHOULD_BUILD_TAR}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_ZIP=${SHOULD_BUILD_ZIP}" >> "${GITHUB_ENV}"
echo "SHOULD_BUILD_SRC=${SHOULD_BUILD_SRC}" >> "${GITHUB_ENV}"
