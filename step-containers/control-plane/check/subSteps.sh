. /log.sh
. /function.sh


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

# check if exist subnet
# $1 : id of the subnet to check
# return : string ( "true" if subnet exist, "false" otherwise )
function existSubnet () {
  #echo "checking if vpc: ${1} exist ..."
  local VPC_EXISTS=$(aws ec2 describe-vpcs --filters "Name=vpc-id,Values=${1}" --query "Vpcs" --output text)
  if [[ -n "$VPC_EXISTS" ]]; then
      echo "true"
  else
      echo "false"
  fi
}

# check if exist vpc
# $1 : id of the vpc to check
# void
function checkVPC () {
  local VPC_EXISTS=$(aws ec2 describe-vpcs --filters "Name=vpc-id,Values=${1}" --query "Vpcs" --output text)

  if [[ -n "$VPC_EXISTS" ]]; then
      echo "VPC ${1} exist"
  else
      >&2 colorEcho "error" "VPC ${1} doesn't exist."
      exit 1
  fi
}

# check if exist frontend/backend subnet
# $1 : ids of frontend subnet
# $2 : ids of backend subnet
# void
function checkSubnets () {
  echo "Checking subnets frontend/backend"
  local FE_SUBNETS=$(echo "${1}" | tr "," " ")
  mapfile -t ARR_SUBNETS_FE < <(aws ec2 describe-subnets --subnet-ids ${FE_SUBNETS} | jq -cr '.Subnets[].Tags[] | select(.Key=="Name") | .Value | @sh')
  local BE_SUBNETS=$(echo "${2}" | tr "," " ")
  mapfile -t ARR_SUBNETS_BE < <(aws ec2 describe-subnets --subnet-ids ${BE_SUBNETS} | jq -cr '.Subnets[].Tags[] | select(.Key=="Name") | .Value | @sh')

  echo "Checking frontend subnets ${ARR_SUBNETS_BE[*]}"
  for SUBNET in ${FE_SUBNETS}; do
      if [[ "$(existSubnet "${SUBNET}")" == "true" ]]; then
          SUBNET_NAME=$(aws ec2 describe-subnets --subnet-ids "${SUBNET}" | jq -cr '.Subnets[].Tags[] | select(.Key=="Name") | .Value | @sh')
          echo "Subnet ${SUBNET} exist with name: ${SUBNET_NAME}"
      else
          >&2 colorEcho "error" "Subnet ${SUBNET} doesn't exist."
          exit 1
      fi
  done

  echo "Checking backend subnets ${ARR_SUBNETS_BE[*]}"
  for SUBNET in ${BE_SUBNETS}; do
      if [[ "$(existSubnet "${SUBNET}")" == "true" ]]; then
          SUBNET_NAME=$(aws ec2 describe-subnets --subnet-ids "${SUBNET}" | jq -cr '.Subnets[].Tags[] | select(.Key=="Name") | .Value | @sh')
          echo "Subnet ${SUBNET} exist with name: ${SUBNET_NAME}"
      else
          >&2 colorEcho "error" "Subnet ${SUBNET} doesn't exist."
          exit 1
      fi
  done
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

# check if exist cluster
# $1 : name of the cluster to check
# $2 : region where cluster is deployed
# void
function configureClusterAccess() {
    aws eks update-kubeconfig --region "${2}" --name "${1}"
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
    >&2 colorEcho "error" "${2} NOT permitted! Please check your controlpanel version.\nExiting..."
    exit 1
  fi
}

# check if controlplane version is compatible with infrplane version
# $1 : name of the cluster to check
# $2 : controlplane version to deploy
# void
function checkControlpanelVsInfrpanel () {
  set +e
  # local INFRPANEL_K8S_VERSION="$(kubectl --kubeconfig="${ACTUAL_KUBECONF}" --context="${DOMAIN}" get cm cm-version -n kube-system -o "jsonpath={.data.version}")"
  local INFRPANEL_K8S_VERSION="$(kubectl get cm cm-infrplane-data -n kube-system -o "jsonpath={.data.version}")"
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -eq 0 ]; then
    echo "Checking controlpanel version accross infrpanel version.\nInfrpanel version ${INFRPANEL_K8S_VERSION}"
    local CONTROLPANEL_NEXT_VERSION=$( (echo "$INFRPANEL_K8S_VERSION + 0.01") | bc )
    local CONTROLPANEL_PERMITTED_VERSIONS=( "${INFRPANEL_K8S_VERSION}" "${CONTROLPANEL_NEXT_VERSION}" )
    if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ ${2} ]]; then
      >&2 colorEcho "error" "${2} NOT permitted! Please check your infrplane version.\nExiting..."
      exit 1
    fi
  else
    >&2 colorEcho "error" "Control of compatibility between controlplane version and  infrpanel version not possible, the config map cm-infrplane-data isn't present on cluster ${1}."
    exit 1
  fi
}

# check if controlplane version is compatible with dataplane version
# $1 : name of the cluster to check
# $2 : controlplane version to deploy
# $3 : region where deploy
# void
function checkControlpanelVsDatapanel () {
    #CHECK CONTROL PANEL VERSION WITH CURRENT DATA PANEL VERSIONS
    echo "Checking controlpanel version accross datapanel versions"
    downloadAutomationConfJson "${GITHUB_ORG}/${1}Dataplane" "${GITHUB_TOKEN}"
    if [ "$(repoExist "${GITHUB_ORG}/${1}Dataplane" "${GITHUB_TOKEN}")" = "true" ]; then
        echo "The datapanel exits, checking the versions"
        mapfile -t ALL_NODEGROUPS_NAMES_CF< <(jq -r '.nodegroups[].datapanel_cloudformation_name' "automation_conf.json")
        for NODEGROUP_NAME_CF in "${ALL_NODEGROUPS_NAMES_CF[@]}"; do
          set +e
          local INFO_NODEGROUP_NAME_CF="$(aws cloudformation describe-stacks --stack-name "${NODEGROUP_NAME_CF}" --region="${3}" 2>&1)"
          local RETURN_CODE=$?
          set -e

          if [ "${RETURN_CODE}" -eq 0 ] && [[ "${INFO_NODEGROUP_NAME_CF}" != *"Stack with id ${INFO_NODEGROUP_NAME_CF} does not exist"* ]]; then
            local NODEGROUP_VERSION="$(echo "${INFO_NODEGROUP_NAME_CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeImageIdSSMParam") | .ParameterValue' | cut -d "/" -f6 )"
            echo "Name stack datapanel ${NODEGROUP_NAME_CF} has the version: ${NODEGROUP_VERSION}"
            local CONTROLPANEL_NEXT_VERSION=$( (echo "$NODEGROUP_VERSION + 0.01") | bc )
            local CONTROLPANEL_PERMITTED_VERSIONS=("${NODEGROUP_VERSION}" "${CONTROLPANEL_NEXT_VERSION}")
            if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ ${DEPLOY_CONTROLPANEL_VERSION} ]]; then
              >&2 colorEcho "error" "${2} NOT permitted! Please check your datapanel version.\nExiting..."
              exit 1
            fi
          else
            echo "Stack of datapanel with name ${NODEGROUP_NAME_CF} doesn't exist"
          fi
        done

    else
      echo "The datapanel doesn't exist! No check with version necessary."
    fi
}

# check correspondence of mandatory values
# (parameters are read from global scope)
# void
function checkCFMandatoryParameters () {
  # check VPC_ID_PARAMETER
  if [ "${VPC_ID_PARAMETER}" = "${VPC_ID_PARAMETER_TO_CHECK}" ]; then
    echo "VPC_ID_PARAMETER check OK: ${VPC_ID_PARAMETER}"
  else
    >&2 colorEcho "error" "VPC_ID_PARAMETER check KO (plan_param - cf_param): ${VPC_ID_PARAMETER} - ${VPC_ID_PARAMETER_TO_CHECK}"
    exit 1
  fi

  # check BE_SUBNET_IDS_PARAMETER
  BE_SUBNET_IDS_PARAMETER_SORTED="$(echo ${BE_SUBNET_IDS_PARAMETER} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  BE_SUBNET_IDS_PARAMETER_TO_CHECK_SORTED="$(echo ${BE_SUBNET_IDS_PARAMETER_TO_CHECK} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  if [ "${BE_SUBNET_IDS_PARAMETER_SORTED}" =  "${BE_SUBNET_IDS_PARAMETER_TO_CHECK_SORTED}" ]; then
    echo "BE_SUBNET_IDS_PARAMETER check OK: ${BE_SUBNET_IDS_PARAMETER}"
  else
    >&2 colorEcho "error" "BE_SUBNET_IDS_PARAMETER check KO (plan_param - cf_param): ${BE_SUBNET_IDS_PARAMETER} - ${BE_SUBNET_IDS_PARAMETER_TO_CHECK}"
    exit 1
  fi

  # check ENVIRONMENT_TAG_PARAMETER
  if [ "${ENVIRONMENT_TAG_PARAMETER}" = "${ENVIRONMENT_TAG_PARAMETER_TO_CHECK}" ]; then
    echo "ENVIRONMENT_TAG_PARAMETER check OK: ${ENVIRONMENT_TAG_PARAMETER}"
  else
    >&2 colorEcho "error" "ENVIRONMENT_TAG_PARAMETER check KO (plan_param - cf_param): ${ENVIRONMENT_TAG_PARAMETER} - ${ENVIRONMENT_TAG_PARAMETER_TO_CHECK}"
    exit 1
  fi

  # check CLUSTER_NAME
  if [ "${CLUSTER_NAME}" = "${CLUSTER_NAME_TO_CHECK}" ]; then
    echo "CLUSTER_NAME check OK: ${CLUSTER_NAME}"
  else
    >&2 colorEcho "error" "CLUSTER_NAME check KO (plan_param - cf_param): ${CLUSTER_NAME} - ${CLUSTER_NAME_TO_CHECK}"
    exit 1
  fi

  # check SECURITY_GROUP_IDS_PARAMETER
  SECURITY_GROUP_IDS_PARAMETER_SORTED="$(echo ${SECURITY_GROUP_IDS_PARAMETER} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  SECURITY_GROUP_IDS_PARAMETER_TO_CHECK_SORTED="$(echo ${SECURITY_GROUP_IDS_PARAMETER_TO_CHECK} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  if [ "${SECURITY_GROUP_IDS_PARAMETER_SORTED}" = "${SECURITY_GROUP_IDS_PARAMETER_TO_CHECK_SORTED}" ]; then
    echo "SECURITY_GROUP_IDS_PARAMETER check OK: ${SECURITY_GROUP_IDS_PARAMETER}"
  else
    >&2 colorEcho "error" "SECURITY_GROUP_IDS_PARAMETER check KO (plan_param - cf_param): ${SECURITY_GROUP_IDS_PARAMETER} - ${SECURITY_GROUP_IDS_PARAMETER_TO_CHECK}"
    exit 1
  fi
}
