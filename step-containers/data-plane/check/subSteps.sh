# assign new role (created in pull step) to service account
# $1 : arn of the role to assign
# $2 : region where deploy the cluster
# void
function assignRoleToServiceAccount () {
  echo "Assuming role: ${1}"
  local OLD_ROLE="$(aws sts get-caller-identity)"
  echo "Old role: ${OLD_ROLE}"
  aws sts assume-role --role-arn "${1}" --role-session-name=session-role-controlplane-$$ --region "${2}" --duration-seconds 3600
  local ROLE_ASSUMED="$(aws sts get-caller-identity)"
  echo "Role assumed: ${ROLE_ASSUMED}"
}

# check if exist subnet
# $1 : id of the subnet to check
# return : string ( "true" if subnet exist, "false" otherwise )
function existSubnet () {
    set +e
    local SUB=$(aws ec2 describe-subnets --subnet-ids ${1} --query "Subnets[0].SubnetId" --output text 2>&1)
    local RETURN_CODE=$?
    set -e

    if [[ "${SUB}" == *"InvalidSubnetID.NotFound"* ]]; then
        echo "false"
    elif [ "${RETURN_CODE}" -ne 0 ]; then
        >&2 echo "Error: ${SUB}"
        exit 1
    else
        echo "true"
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

# check if exist backend subnets
# $1 : ids of backend subnets
# void
function checkBeSubnets () {
  echo "Checking backend subnets"
  local BE_SUBNETS=$(echo "${2}" | tr "," " ")
  mapfile -t ARR_SUBNETS_BE < <(aws ec2 describe-subnets --subnet-ids ${BE_SUBNETS} | jq -cr '.Subnets[].Tags[] | select(.Key=="Name") | .Value | @sh')

  echo "Checking backend subnets ${ARR_SUBNETS_BE[*]}"
  for SUBNET in ${BE_SUBNETS}; do
      if [ "$(existSubnet "${SUBNET}")" = "true" ]; then
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
  local CF
  CF="$(aws cloudformation describe-stacks --stack-name "${1}" --region="${2}" 2>&1)"
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -ne 0 ] && [[ "${CF}" == *"Stack with id ${1} does not exist"* ]]; then
    echo "false"
  elif [ "${RETURN_CODE}" -ne 0 ]; then
    >&2 colorEcho "error" "${CF}"
    exit 1
  else
    echo "true"
  fi
}


# check if exist cluster
# $1 : name of the cluster to check
# return : string ( "true" if cluster exist, "false" otherwise )
function existCluster () {
  set +e
  local EKS_DESCRIPTION
  EKS_DESCRIPTION="$(aws eks describe-cluster --name "${1}" 2>&1)"
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -ne 0 ] && [[ "${EKS_DESCRIPTION}" == *"ResourceNotFoundException"* ]]; then
    echo "false"
  elif [ "${RETURN_CODE}" -ne 0 ]; then
    >&2 colorEcho "error" "${EKS_DESCRIPTION}"
    exit 1
  else
    echo "true"
  fi
}


# check if dataplane version is compatible with controlplane version
# $1 : name of the cluster to check
# $2 : dataplane version to deploy
# void
function checkDatapanelVsControlpanel () {
    #CHECK CONTROL PANEL VERSION WITH CURRENT DATA PANEL VERSIONS
    echo "Checking datapanel version accross controlpanel versions"
    local CONTROLPANEL_VERSION="$(aws eks describe-cluster --name "${1}" | jq -r '.cluster.version')"
    local CONTROLPANEL_NEXT_VERSION=$( (echo "$CONTROLPANEL_VERSION + 0.01") | bc )
    local CONTROLPANEL_PERMITTED_VERSIONS=( "${CONTROLPANEL_VERSION}" "${CONTROLPANEL_NEXT_VERSION}" )
    if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ ${2} ]]; then
      >&2 colorEcho "error" "${2} NOT permitted! Please check your controlplane version.\nExiting..."
      exit 1
    fi
}

# check if dataplane version is compatible with infrplane version
# $1 : name of the cluster to check
# $2 : controlplane version to deploy
# void
function checkDatapanelVsInfrpanel () {
  set +e
  # local INFRPANEL_K8S_VERSION="$(kubectl --kubeconfig="${ACTUAL_KUBECONF}" --context="${DOMAIN}" get cm cm-version -n kube-system -o "jsonpath={.data.version}")"
  local INFRPANEL_K8S_VERSION="$(kubectl get cm cm-infrplane-data -n kube-system -o "jsonpath={.data.version}")"
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -eq 0 ]; then
    echo "Checking controlpanel version accross infrpanel version.\nInfrpanel version ${INFRPANEL_K8S_VERSION}"
    local DATAPANEL_NEXT_VERSION=$( (echo "$INFRPANEL_K8S_VERSION + 0.01") | bc )
    local CONTROLPANEL_PERMITTED_VERSIONS=( "${INFRPANEL_K8S_VERSION}" "${DATAPANEL_NEXT_VERSION}" )
    if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ ${2} ]]; then
      >&2 colorEcho "error" "${2} NOT permitted! Please check your infrplane version.\nExiting..."
      exit 1
    fi
  else
    colorEcho "warning" "Control of compatibility between controlplane version and  infrpanel version not possible, the config map cm-infrplane-data isn't present on cluster ${1}."
  fi
}


#TODO implements from row (620-...)
function checkCFMandatoryParameters() {

}

#TODO implements CHECK DATAPANEL CLOUDFORMATIONS (rows 333-615)
function checkDataPanelCF(){

}
