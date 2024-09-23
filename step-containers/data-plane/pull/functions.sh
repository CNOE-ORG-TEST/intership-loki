#!/bin/bash -e

# check if exist role cloud formation
# $1 : name of the role cloud formation to check
# $2 : region where deploy the cluster
# return : string ( "true" if CF exist, "false" otherwise )
function existRoleCF() {
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
