. /functions.sh

# assign new role (created in pull step) to service account
# $1 : arn of the role to assign
# $2 : region where deploy the cluster
# void
function assignRoleToServiceAccount () {
  echo "Assuming role: ${$1}"
  aws sts assume-role --role-arn "${$1}" --role-session-name=session-role-controlplane-$$ --region "${$2}" --duration-seconds 43200
  local ROLE_ASSUMED="$(aws sts get-caller-identity)"
  echo "Role assumed: ${ROLE_ASSUMED}"
}

# check if exist cluster cloud formation
# $1 : name of the cluster cloud formation to check
# $2 : region where deploy the cluster
# return : string ( "true" if CF exist, "false" otherwise )
function existClusterCF () {
  set +e
  local CF="$(aws cloudformation describe-stacks --stack-name "${1}" --region="${2}" 2>&1)"
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -ne 0 ] && [[ "${CF}" == *"Stack with id ${CLOUDFORMATION_NAME} does not exist"* ]]; then
    echo "false"
  else
    echo "true"
  fi
}


# check if exist cluster
# $1 : name of the cluster to check
# return : string ( "true" if cluster exist, "false" otherwise )
function existCluster () {
  set +e
  local EKS_DESCRIPTION="$(aws eks describe-cluster --name "${1}" 2>&1)"
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -eq 0 ]; then
    echo "true"
  else
    echo "false"
  fi
}

# check if controlplane version
# $1 : name of the cluster to check
# $2 : controlplane version to deploy
# void
function checkNewControlpanelVersion () {
  echo "Checking controlpanel version"
  local CURRENT_CONTROLPANEL_VERSION="$(aws eks describe-cluster --name "${1}" | jq -r '.cluster.version')"
  local CONTROLPANEL_NEXT_VERSION=$( (echo "$CURRENT_CONTROLPANEL_VERSION + 0.01") | bc )
  local CONTROLPANEL_PERMITTED_VERSIONS=("${CURRENT_CONTROLPANEL_VERSION}" "${CONTROLPANEL_NEXT_VERSION}")

  echo "Permitted version controlpanel: ${CONTROLPANEL_PERMITTED_VERSIONS[*]}"
  if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ ${2} ]]; then
    >&2 echo "${DEPLOY_CONTROLPANEL_VERSION} NOT permitted! Please check your controlpanel version.\nExiting..."
    exit 1
  fi
}

# check if controlplane version is compatible with infoplane version
# $1 : name of the cluster to check
# $2 : controlplane version to deploy
# void
# TODO understend how use kubeconfig and secret (ACTUAL_KUBECONF, Domain)
function checkControlpanelVsInfrpanel () {
  set +e
  local INFRPANEL_K8S_VERSION="$(kubectl --kubeconfig="${ACTUAL_KUBECONF}" --context="${DOMAIN}" get cm cm-version -n kube-system -o "jsonpath={.data.version}")"
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -eq 0 ]; then
    echo "Checking controlpanel version accross infrpanel version.\nInfrpanel version ${INFRPANEL_K8S_VERSION}"
    local CONTROLPANEL_NEXT_VERSION=$( (echo "$INFRPANEL_K8S_VERSION + 0.01") | bc )
    local CONTROLPANEL_PERMITTED_VERSIONS=( "${INFRPANEL_K8S_VERSION}" "${CONTROLPANEL_NEXT_VERSION}" )
    if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ ${2} ]]; then
      >&2 echo "${DEPLOY_CONTROLPANEL_VERSION} NOT permitted! Please check your infrplane version.\nExiting..."
      exit 1
    fi
  else
    echo "Control of compatibility between controlplane version and  infrpanel version not possible, the config map cm-version isn't present on cluster ${1}."
  fi
}

function checkControlpanelVsDatapanel () {
  # TODO implement
}

function checkCFMandatoryParameters () {
  # TODO implement
}
