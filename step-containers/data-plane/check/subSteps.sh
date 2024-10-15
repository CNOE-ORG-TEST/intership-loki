. ./functions.sh
. ./log.sh

# assign new role (created in pull step) to service account
# $1 : arn of the role to assign
# $2 : region where deploy the cluster
# void
function assignRoleToServiceAccount () {
  echo "Assuming role: ${1}"
  local OLD_ROLE="$(aws sts get-caller-identity)"
  echo "Old role: ${OLD_ROLE}"
  aws sts assume-role --role-arn "${1}" --role-session-name=session-role-dataplane-$$ --region "${2}" --duration-seconds 3600
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
    echo "Checking datapanel version accross infrpanel version.\nInfrpanel version ${INFRPANEL_K8S_VERSION}"
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

# check if the values passed are available and if don't set use default parameter
# void
function checkCFAvailableDefaultParameters(){
  checkADSubnetAz
  checkADNodeVolumeSize
  checkADNodeVolumeIOPS
  checkADNodeVolumeThroughput
  checkADNodeVolumeType
  checkADMaxPods
  checkADLabels
  checkADNodeInstanceType
  checkADNodeAsgSize
  checkADInstanceParallel
  checkADOnDemandCapacity
}

# if we are updating check no mandatory values
# void
function checkCFNoMandatoryParameters() {
    echo "Checking Cloudformation NOT mandatory parameters:"
      # 5 NOT MANDATORY
      # - BACKUP_PARAMETER
      # - NODE_INSTANCE_TYPE
      # - NODE_ASG_DESIRED_CAPACITY
      # - NODE_ASG_MAX_SIZE
      # - NODE_ASG_MIN_SIZE
    checkNMPBackupParam
    checkNMPNodeInstanceType
    checkNMPNodeImageIDSSM
    checkNMPNodeAsgDesiredCapacity
    checkNMPNodeAsgMaxSize
    checkNMPNodeAsgMinSize
    checkNMPNodeImgId
    checkNMPNodeVolumeSize
    checkNMPNodeVolumeType
    checkNMPNodeVolumeIOPS
    checkNMPOnDemandBaseCapacity
}


# if we are updating check mandatory values
# void
function checkCFMandatoryParameters() {
  BACKUP_PARAMETER_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="BackupParameter") | .ParameterValue')"
  BOOTSTRAP_ARGUMENTS_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="BootstrapArguments") | .ParameterValue')"
  CLUSTER_API_ENDPOINT_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" |  jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="ClusterAPIEndpoint") | .ParameterValue')"
  CLUSTER_CONTROLPLANE_SECURITYGROUP_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="ClusterControlPlaneSecurityGroup") | .ParameterValue')"
  CLUSTER_NAME_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="ClusterName") | .ParameterValue')"
  CUSTOMER_TAG_PARAMETER_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="CustomerTagParameter") | .ParameterValue')"
  ENVIRONMENT_TAG_PARAMETER_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="EnvironmentTagParameter") | .ParameterValue')"
  KEY_NAME_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="KeyName") | .ParameterValue')"
  NODE_ASG_DESIRED_CAPACITY_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeAutoScalingGroupDesiredCapacity") | .ParameterValue')"
  NODE_ASG_MAX_SIZE_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeAutoScalingGroupMaxSize") | .ParameterValue')"
  NODE_ASG_MIN_SIZE_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeAutoScalingGroupMinSize") | .ParameterValue')"
  NODEGROUP_NAME_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeGroupName") | .ParameterValue')"
  NODEGROUP_TYPE_PARAMETER_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeGroupTypeParameter") | .ParameterValue')"
  NODE_IMAGE_ID_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeImageId") | .ParameterValue')"
  NODE_IMAGE_IDSSM_PARAM_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeImageIdSSMParam") | .ParameterValue')"
  NODE_VOLUME_SIZE_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeVolumeSize") | .ParameterValue')"
  NODE_VOLUME_TYPE_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeVolumeType") | .ParameterValue')"
  NODE_VOLUME_IOPS_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeVolumeIops") | .ParameterValue')"
  SECURITY_GROUP_IDS_PARAMETER_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="SecurityGroupIdsParameter") | .ParameterValue')"
  BE_SUBNET_IDS_PARAMETER_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="Subnets") | .ParameterValue')"
  VPC_ID_PARAMETER_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="VpcId") | .ParameterValue')"
  ONDEMAND_BASE_CAPACITY_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="OnDemandBaseCapacity") | .ParameterValue')"

  checkEKSVersion
  checkTains

  BOOTSTRAP_ARGUMENTS="$( echo "--use-max-pods false --kubelet-extra-args \"${KUBELET_EXTRA_ARGS}\" --apiserver-endpoint ${CLUSTER_API_ENDPOINT} --b64-cluster-ca ${CA_DATA_B64}" | tr -s " ")"
  BOOTSTRAP_ARGUMENTS_CHECK_NO_MAXPODS="$(echo ${BOOTSTRAP_ARGUMENTS_CHECK} | sed -e 's/[[:space:]]*--max-pods=[0-9]*//g' | tr -s " ")"

  setNodeIstancesTypeToCheck

  # ALL CHECKS
  # 20 MANDATORY
  echo "Checking Cloudformation mandatory parameters:"

  checkMPBootstrapArguments
  checkMPClusterAPIEndpoint
  checkMPClusterControlplaneSecurityGroups
  checkMPClusterName
  checkMPEnvironmentTagParameter
  checkMPKeyName
  checkMPNodeGroupName
  checkMPSecurityGroupsIds
  checkMPSubnets
  checkMPVpcID
}

# check CF datapanel parameters
# void
function checkDataPanelCF(){
  cd /shared
  local NUMBER_REGEXPR="^[0-9]+$"
  for i in $(seq 0 $((NODEGROUPS_NUMBER-1)));
  do
    DATAPANEL_CLOUDFORMATION_NAME="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].datapanel_cloudformation_name' automation_conf.json)"
    NODEGROUP_NAME="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.tag_nodegroup_name' automation_conf.json)"
    SUBNET_AZ="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.subnet_az' automation_conf.json)"
    BACKUP_PARAMETER="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.backup_parameter' automation_conf.json)"
    NODE_ASG_MAX_SIZE="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_max' automation_conf.json)"
    NODE_ASG_MIN_SIZE="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_min' automation_conf.json)"
    NODE_ASG_DESIRED_CAPACITY="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_desidered' automation_conf.json)"
    NODE_VOLUME_SIZE="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_volume.size' automation_conf.json)"
    NODE_VOLUME_TYPE="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_volume.type' automation_conf.json)"
    NODE_VOLUME_IOPS="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_volume.iops' automation_conf.json)"
    NODE_VOLUME_THROUGHPUT="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_volume.throughput' automation_conf.json)"
    ONDEMAND_BASE_CAPACITY="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.ondemand_base_capacity' automation_conf.json)"
    IS_SPOT="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.is_spot' automation_conf.json)"
    IS_GRAVITON="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.is_graviton' automation_conf.json)"
    IS_GPU="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.is_gpu' automation_conf.json)"
    TAINTS="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.taints' automation_conf.json)"
    LABELS="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.labels' automation_conf.json)"
    MAX_PODS="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.max_pods' automation_conf.json)"
    mapfile -t NODE_INSTANCE_TYPE_ARR< <(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.machine_size[]' automation_conf.json)
    NODE_INSTANCE_TYPE="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.machine_size[]' automation_conf.json | tr "\n" ",")"
    NODE_IMAGE_ID=""
    INSTANCE_IN_PARALLEL="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.instances_in_parallel' automation_conf.json)"
    PAUSE_TIME="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.pause_time' automation_conf.json)"

    checkCFAvailableDefaultParameters
  
    echo "Data panel cloudformation:\n${DATAPANEL_CLOUDFORMATION_NAME}"
    
    
    
    set +e
    DATAPANEL_CLOUDFORMATION="$(aws cloudformation describe-stacks --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region="${DEPLOY_AWS_REGION}" 2>&1)"
    RETURN_CODE=$?
    set -e
    
    if [ "${RETURN_CODE}" -ne 0 ] && [[ "${DATAPANEL_CLOUDFORMATION}" == *"Stack with id ${DATAPANEL_CLOUDFORMATION_NAME} does not exist"* ]]; then
      echo "Data panel cloudformation with name ${DATAPANEL_CLOUDFORMATION_NAME} doesn't exist"
      echo "OK: Cloudformation ${DATAPANEL_CLOUDFORMATION_NAME} will be created in next deploy step."
      #jq -r --arg i "${i}" --arg machine_size_parameter "${NODE_INSTANCE_TYPE}" '.nodegroups[$i|tonumber].cloudformation_options.machine_size_parameter |= $machine_size_parameter' deploy_and_release_variables.json > deploy_and_release_variables.json.tmp && mv deploy_and_release_variables.json.tmp deploy_and_release_variables.json
    else 
      echo "Checking before update cloudformation => DATAPANEL_CLOUDFORMATION_NAME=${DATAPANEL_CLOUDFORMATION_NAME}"
      #echo "DATAPANEL_CLOUDFORMATION"
      #echo "${DATAPANEL_CLOUDFORMATION}"
  
      if [ "${IS_SPOT}" = "true" ]; then
        echo "The nodegroup is of type spot"
        NODEGROUP_TYPE_PARAMETER="spot"
        NODE_IMAGE_IDSSM_PARAM="/aws/service/eks/optimized-ami/${DEPLOY_DATAPANEL_VERSION}/amazon-linux-2/recommended/image_id"
      elif { [ "${IS_GRAVITON}" = "true" ] && [ "${IS_GPU}" = "true" ]; } || [ "${IS_SPOT}" = "true" ]; then
        >&2 colorEcho "error" "You have configured incorrectly the repo: the type of ami can be or spot, or graviton, or gpu or simply ondemand"
        exit 1
      elif  [ "${IS_GRAVITON}" = "true" ] && [ "${IS_GPU}" = "true" ]; then
        >&2 colorEcho "error" "You have configured incorrectly the repo: you can choose or graviton, or gpu not together"
        exit 1
      else
        echo "The nodegroup is of type ondemand"
        NODEGROUP_TYPE_PARAMETER="ondemand"
        NODE_IMAGE_IDSSM_PARAM="/aws/service/eks/optimized-ami/${DEPLOY_DATAPANEL_VERSION}/amazon-linux-2/recommended/image_id"
        if [ "${IS_GRAVITON}" = "true" ]; then
          echo "In particular graviton"
          NODE_IMAGE_IDSSM_PARAM="/aws/service/eks/optimized-ami/${DEPLOY_DATAPANEL_VERSION}/amazon-linux-2-arm64/recommended/image_id"
        elif [ "${IS_GPU}" = "true" ]; then
          echo "In particular gpu"
          NODE_IMAGE_IDSSM_PARAM="/aws/service/eks/optimized-ami/${DEPLOY_DATAPANEL_VERSION}/amazon-linux-2-gpu/recommended/image_id"
        fi
      fi
      checkCFMandatoryParameters
      checkCFNoMandatoryParameters
    fi
  done
}
