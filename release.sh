#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GITHUB_TOKEN}" ]] && [[ -z "${GH_ENTERPRISE_TOKEN}" ]] && [[ -z "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
  echo "Will not release because no GITHUB_TOKEN defined"
  exit
fi

REPOSITORY_OWNER="${ASSETS_REPOSITORY/\/*/}"
REPOSITORY_NAME="${ASSETS_REPOSITORY/*\//}"

# Generate UTC timestamp for unique release identifier
RELEASE_TIMESTAMP=$(date -u +"%Y%m%d%H%M%S")
RELEASE_VERSION_WITH_PATCH="${RELEASE_VERSION}-p${PATCHES_COMMIT:0:7}"

npm install -g github-release-cli

if [[ $( gh release view "${RELEASE_VERSION_WITH_PATCH}" --repo "${ASSETS_REPOSITORY}" 2>&1 ) =~ "release not found" ]]; then
  echo "Creating release '${RELEASE_VERSION_WITH_PATCH}'"

  . ./utils.sh

  APP_NAME_LC="$( echo "${APP_NAME}" | awk '{print tolower($0)}' )"
  VERSION="${RELEASE_VERSION_WITH_PATCH%-insider}"

  if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
    NOTES="update vscode to [${MS_COMMIT}](https://github.com/microsoft/vscode/tree/${MS_COMMIT})"

    replace "s|@@APP_NAME@@|${APP_NAME}|g" release_notes.md
    replace "s|@@APP_NAME_LC@@|${APP_NAME_LC}|g" release_notes.md
    replace "s|@@APP_NAME_QUALITY@@|${APP_NAME}-Insiders|g" release_notes.md
    replace "s|@@ASSETS_REPOSITORY@@|${ASSETS_REPOSITORY}|g" release_notes.md
    replace "s|@@BINARY_NAME@@|${BINARY_NAME}|g" release_notes.md
    replace "s|@@PATCHES_COMMIT@@|${PATCHES_COMMIT}|g" release_notes.md
    replace "s|@@MS_TAG@@|${MS_COMMIT}|g" release_notes.md
    replace "s|@@MS_URL@@|https://github.com/microsoft/vscode/tree/${MS_COMMIT}|g" release_notes.md
    replace "s|@@QUALITY@@|-insider|g" release_notes.md
    replace "s|@@RELEASE_NOTES@@||g" release_notes.md
    replace "s|@@VERSION@@|${VERSION}|g" release_notes.md

    gh release create "${RELEASE_VERSION_WITH_PATCH}" --repo "${ASSETS_REPOSITORY}" --title "${RELEASE_VERSION_WITH_PATCH}" --notes-file release_notes.md
  else
    gh release create "${RELEASE_VERSION_WITH_PATCH}" --repo "${ASSETS_REPOSITORY}" --title "${RELEASE_VERSION_WITH_PATCH}" --generate-notes

    RELEASE_NOTES=$( gh release view "${RELEASE_VERSION_WITH_PATCH}" --repo "${ASSETS_REPOSITORY}" --json "body" --jq ".body" )

    replace "s|@@APP_NAME@@|${APP_NAME}|g" release_notes.md
    replace "s|@@APP_NAME_LC@@|${APP_NAME_LC}|g" release_notes.md
    replace "s|@@APP_NAME_QUALITY@@|${APP_NAME}|g" release_notes.md
    replace "s|@@ASSETS_REPOSITORY@@|${ASSETS_REPOSITORY}|g" release_notes.md
    replace "s|@@BINARY_NAME@@|${BINARY_NAME}|g" release_notes.md
    replace "s|@@PATCHES_COMMIT@@|${PATCHES_COMMIT}|g" release_notes.md
    replace "s|@@MS_TAG@@|${MS_TAG}|g" release_notes.md
    replace "s|@@MS_URL@@|https://code.visualstudio.com/updates/v$( echo "${MS_TAG//./_}" | cut -d'_' -f 1,2 )|g" release_notes.md
    replace "s|@@QUALITY@@||g" release_notes.md
    replace "s|@@RELEASE_NOTES@@|${RELEASE_NOTES//$'\n'/\\n}|g" release_notes.md
    replace "s|@@VERSION@@|${VERSION}|g" release_notes.md

    gh release edit "${RELEASE_VERSION_WITH_PATCH}" --repo "${ASSETS_REPOSITORY}" --notes-file release_notes.md
  fi
fi

cd assets

set +e

for FILE in *; do
  if [[ -f "${FILE}" ]] && [[ "${FILE}" != *.sha1 ]] && [[ "${FILE}" != *.sha256 ]]; then
    echo "::group::Uploading '${FILE}' at $( date "+%T" )"
    gh release upload --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION_WITH_PATCH}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

    EXIT_STATUS=$?
    echo "exit: ${EXIT_STATUS}"

    if (( "${EXIT_STATUS}" )); then
      for (( i=0; i<10; i++ )); do
        github-release delete --owner "${REPOSITORY_OWNER}" --repo "${REPOSITORY_NAME}" --tag "${RELEASE_VERSION_WITH_PATCH}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

        sleep $(( 15 * (i + 1)))

        echo "RE-Uploading '${FILE}' at $( date "+%T" )"
        gh release upload --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION_WITH_PATCH}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

        EXIT_STATUS=$?
        echo "exit: ${EXIT_STATUS}"

        if ! (( "${EXIT_STATUS}" )); then
          break
        fi
      done
      echo "exit: ${EXIT_STATUS}"

      if (( "${EXIT_STATUS}" )); then
        echo "'${FILE}' hasn't been uploaded!"

        github-release delete --owner "${REPOSITORY_OWNER}" --repo "${REPOSITORY_NAME}" --tag "${RELEASE_VERSION_WITH_PATCH}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

        exit 1
      fi
    fi

    echo "::endgroup::"
  fi
done

cd ..
