#!/bin/bash -e

# check if exist role cloud formation
# $1 : name of the role cloud formation to check
# $2 : region where deploy the cluster
# return : string ( "true" if CF exist, "false" otherwise )
function existRoleCF () {
  set +e
  local CF="$(aws cloudformation describe-stacks --stack-name "${1}" --region="${2}" 2>&1)"
  local RETURN_CODE=$?
  set -e

  if [[ "${CF}" == *"Stack with id ${1} does not exist"* ]]; then
    echo "false"
  elif [ "${RETURN_CODE}" -ne 0 ]; then
    >&2 echo "Error: ${CF}"
    exit 1
  else
    echo "true"
  fi
}

# download variables.json and automation_conf.json
# void
function downloadVariablesFiles() {
  cd /shared
  curl -H "Authorization: Bearer ${GITHUB_TOKEN}" -L "https://raw.githubusercontent.com/${GITHUB_REPO}/main/automation_conf.json" > /shared/automation_conf.json
  cp /etc/config/variables.json /shared/variables.json
  echo "variables.json parameters:"
  cat variables.json

  echo "automation_conf.json parameters:"
  cat automation_conf.json
  cd /
}
