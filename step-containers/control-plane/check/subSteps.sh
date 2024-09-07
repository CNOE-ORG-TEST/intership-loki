. /functions.sh


# TODO move to function.sh or log.sh
function colorEcho(){
  if [ "${1}" = "error" ]; then
    echo -e "\033[31mError: ${2}\033[0m"
  elif [ "${1}" = "warning" ]; then
    echo -e "\033[33mWarning: ${2}\033[0m"
  elif [ "${1}" = "red" ]; then
    echo -e "\033[31m${2}\033[0m"
  elif [ "${1}" = "yellow" ]; then
    echo -e "\033[33m${2}\033[0m"
  else
    echo "${@}"
  fi
}


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
    colorEcho "error" "${DEPLOY_CONTROLPANEL_VERSION} NOT permitted! Please check your controlpanel version.\nExiting..."
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
      colorEcho "error" "${DEPLOY_CONTROLPANEL_VERSION} NOT permitted! Please check your infrplane version.\nExiting..."
      exit 1
    fi
  else
    echo "Control of compatibility between controlplane version and  infrpanel version not possible, the config map cm-version isn't present on cluster ${1}."
  fi
}

function checkControlpanelVsDatapanel () {
  # TODO implement
}

# TODO verify all parameters
# check correspondence of mandatory values
# (parameters are read from global scope)
# void
function checkCFMandatoryParameters () {
  # check VPC_ID_PARAMETER
  if [ "${VPC_ID_PARAMETER}" = "${VPC_ID_PARAMETER_CHECK}" ]; then
    echo "VPC_ID_PARAMETER check OK: ${VPC_ID_PARAMETER}"
  else
    >&2 colorEcho "error" "VPC_ID_PARAMETER check KO (plan_param - cf_param): ${VPC_ID_PARAMETER} - ${VPC_ID_PARAMETER_CHECK}"
    exit 1
  fi

  # check BE_SUBNET_IDS_PARAMETER
  BE_SUBNET_IDS_PARAMETER_SORTED="$(echo ${BE_SUBNET_IDS_PARAMETER} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  BE_SUBNET_IDS_PARAMETER_CHECK_SORTED="$(echo ${BE_SUBNET_IDS_PARAMETER_CHECK} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  if [ "${BE_SUBNET_IDS_PARAMETER_SORTED}" =  "${BE_SUBNET_IDS_PARAMETER_CHECK_SORTED}" ]; then
    echo "BE_SUBNET_IDS_PARAMETER check OK: ${BE_SUBNET_IDS_PARAMETER}"
  else
    >&2 colorEcho "error" "BE_SUBNET_IDS_PARAMETER check KO (plan_param - cf_param): ${BE_SUBNET_IDS_PARAMETER} - ${BE_SUBNET_IDS_PARAMETER_CHECK}"
    exit 1
  fi

  # check ENVIRONMENT_TAG_PARAMETER
  if [ "${ENVIRONMENT_TAG_PARAMETER}" = "${ENVIRONMENT_TAG_PARAMETER_CHECK}" ]; then
    echo "ENVIRONMENT_TAG_PARAMETER check OK: ${ENVIRONMENT_TAG_PARAMETER}"
  else
    colorEcho "error" "ENVIRONMENT_TAG_PARAMETER check KO (plan_param - cf_param): ${ENVIRONMENT_TAG_PARAMETER} - ${ENVIRONMENT_TAG_PARAMETER_CHECK}"
    exit 1
  fi

  # check CLUSTER_NAME
  if [ "${CLUSTER_NAME}" = "${CLUSTER_NAME_CHECK}" ]; then
    echo "CLUSTER_NAME check OK: ${CLUSTER_NAME}"
  else
    colorEcho "error" "CLUSTER_NAME check KO (plan_param - cf_param): ${CLUSTER_NAME} - ${CLUSTER_NAME_CHECK}"
    exit 1
  fi

  # check SECURITY_GROUP_IDS_PARAMETER
  SECURITY_GROUP_IDS_PARAMETER_SORTED="$(echo ${SECURITY_GROUP_IDS_PARAMETER} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  SECURITY_GROUP_IDS_PARAMETER_CHECK_SORTED="$(echo ${SECURITY_GROUP_IDS_PARAMETER_CHECK} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  if [ "${SECURITY_GROUP_IDS_PARAMETER_SORTED}" = "${SECURITY_GROUP_IDS_PARAMETER_CHECK_SORTED}" ]; then
    echo "SECURITY_GROUP_IDS_PARAMETER check OK: ${SECURITY_GROUP_IDS_PARAMETER}"
  else
    colorEcho "error" "SECURITY_GROUP_IDS_PARAMETER check KO (plan_param - cf_param): ${SECURITY_GROUP_IDS_PARAMETER} - ${SECURITY_GROUP_IDS_PARAMETER_CHECK}"
    exit 1
  fi
}
