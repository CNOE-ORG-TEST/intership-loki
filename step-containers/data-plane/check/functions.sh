
function checkADSubnetAz(){
  if [ "${SUBNET_AZ}" != "" ] && [ "${SUBNET_AZ}" != "null" ] && [ "${IS_SPOT}" = "true" ]; then
    >&2 colorEcho "error" "The nodegroup with single subnet cannot be of type spot.\nPlease check your params.\nExiting.."
    exit 1
  fi
}

function checkADNodeVolumeSize(){
  #NODE_VOLUME_SIZE default 100 if is empty or null
  if [ "${NODE_VOLUME_SIZE}" = "" ] || [ "${NODE_VOLUME_SIZE}" = "null" ]; then
    NODE_VOLUME_SIZE="100"
    echo "No volume size specified. Setting default value ${NODE_VOLUME_SIZE}"
  fi
  if ! [[ ${NODE_VOLUME_SIZE} =~ ${NUMBER_REGEXPR} ]] || ! [[ ${NODE_VOLUME_SIZE} =~ ${NUMBER_REGEXPR} ]]; then
    >&2 colorEcho "error" "node_volume_size parameter is not a number. Please check your params!\nExiting..."
    exit 1
  else
    echo "node_volume_size parameters OK"
  fi
}

function checkADNodeVolumeIOPS(){
  #NODE_VOLUME_IOPS default 3000 if is empty or null
  if [ "${NODE_VOLUME_IOPS}" = "" ] || [ "${NODE_VOLUME_IOPS}" = "null" ]; then
    NODE_VOLUME_IOPS="3000"
    echo "No volume iops specified. Setting default value ${NODE_VOLUME_IOPS}"
  fi
  if ! [[ ${NODE_VOLUME_IOPS} =~ ${NUMBER_REGEXPR} ]] || ! [[ ${NODE_VOLUME_IOPS} =~ ${NUMBER_REGEXPR} ]]; then
    colorEcho "error" "node_volume_iops parameter is not a number. Please check your params!\nExiting..."
    exit 1
  elif [ ${NODE_VOLUME_IOPS} -lt 3000 ]; then
    colorEcho "error" "node_volume_iops parameter cannot be less then 3000. Please check your params!\nExiting..."
    exit 1
  elif [ ${NODE_VOLUME_IOPS} -gt 10000 ]; then
    colorEcho "error" "node_volume_iops parameter cannot be greater then 10000. Please check your params!\nExiting..."
    exit 1
  else
    echo "node_volume_iops parameters OK"
  fi
}

function checkADNodeVolumeThroughput(){
  #NODE_VOLUME_THROUGHPUT default 125 if is empty or null
  if [ "${NODE_VOLUME_THROUGHPUT}" = "" ] || [ "${NODE_VOLUME_THROUGHPUT}" = "null" ]; then
    NODE_VOLUME_THROUGHPUT="125"
    echo "No volume throughput specified. Setting default value ${NODE_VOLUME_THROUGHPUT}"
  fi
  if ! [[ ${NODE_VOLUME_THROUGHPUT} =~ ${NUMBER_REGEXPR} ]] || ! [[ ${NODE_VOLUME_THROUGHPUT} =~ ${NUMBER_REGEXPR} ]]; then
    colorEcho "error" "NODE_VOLUME_THROUGHPUT parameter is not a number. Please check your params!\nExiting..."
    exit 1
  elif [ ${NODE_VOLUME_THROUGHPUT} -lt 125 ]; then
    colorEcho "error" "NODE_VOLUME_THROUGHPUT parameter cannot be less then 125. Please check your params!\nExiting..."
    exit 1
  elif [ ${NODE_VOLUME_THROUGHPUT} -gt 1000 ]; then
    colorEcho "error" "NODE_VOLUME_THROUGHPUT parameter cannot be greater then 1000. Please check your params!\nExiting..."
    exit 1
  else
    echo "NODE_VOLUME_THROUGHPUT parameters OK"
  fi
}

function checkADNodeVolumeType(){
  #NODE_VOLUME_TYPE default gp3 if is empty or null
  if [ "${NODE_VOLUME_TYPE}" = "" ] || [ "${NODE_VOLUME_TYPE}" = "null" ]; then
    NODE_VOLUME_TYPE="gp3"
    echo "No volume type specified. Setting default value ${NODE_VOLUME_TYPE}"
  fi

  NODE_VOLUME_TYPE_VALUES=("gp3" "gp2" "io2" "io1" "st1" "sc1")

  if [[ ! " ${NODE_VOLUME_TYPE_VALUES[*]} " =~ " ${NODE_VOLUME_TYPE,,} " ]]; then
    colorEcho "error" "Value \"${NODE_VOLUME_TYPE}\" for node_volume_type not allowed. Can be only: ${NODE_VOLUME_TYPE_VALUES[@]}"
    exit 1
  else
    echo "node_volume_type parameters OK"
  fi
}

function checkADMaxPods(){
  #MAX PODS CHECK -> MIN VALUE ACCEPTABLE 44
  if [[ "${MAX_PODS}" -ge 44 ]]; then
    echo "max_pods parameter OK: ${MAX_PODS}"
  else
    >&2 colorEcho "error" "max_pods parameter KO: max pods parameter must be at least equal to 44.\nPlease check your param!"
    exit 1
  fi
}

function checkADLabels(){
  LABELS_ARR=("${LABELS}")
  if [ "${#LABELS_ARR[*]}" = 0 ]; then
     >&2 colorEcho "labels parameter is empty. Please add at least one label..."
     exit 1
  else
    echo "labels parameter OK: ${LABELS_ARR[*]}"
  fi
}

function checkADNodeInstanceType(){
  #NODE_INSTANCE_TYPE MUST BE 1 IN CASE OF ONDEMAND MACHINE
  if [ "${#NODE_INSTANCE_TYPE_ARR[*]}" -gt 1 ] && [ "${IS_SPOT}" != "true" ]; then
    >&2 colorEcho "error" "Node type different from SPOT cannot support multiple instance type. Please make sure you have only one instance type for OnDemand nodes. Check machine_size[] parameter. Exiting..."
    exit 1
  else
    echo "machine_size[] parameter OK: ${NODE_INSTANCE_TYPE_ARR[*]}"
  fi
}

function checkADNodeAsgSize(){
  #CHECKS NODE_ASG_MAX_SIZE NODE_ASG_MIN_SIZE NODE_ASG_DESIRED_CAPACITY
  if [[ "${NODE_ASG_MAX_SIZE}" -lt 0 ]] || [[ "${NODE_ASG_MIN_SIZE}" -lt 0 ]] || [[ "${NODE_ASG_DESIRED_CAPACITY}" -lt 0 ]]; then
    >&2 colorEcho "error" "node_min/node_max/node_desidered cannot be less then 0. Please check your params!\nExiting..."
    exit 1
  elif [[ "${NODE_ASG_MIN_SIZE}" -gt "${NODE_ASG_MAX_SIZE}" ]]; then
    >&2 colorEcho "error" "node_min cannot be greater than node_max. Please check your params!\nExiting..."
    exit 1
  else
    echo "node_min/node_max/node_desidered parameters OK"
  fi
}

function checkADInstanceParallel(){
  if ! [[ ${INSTANCE_IN_PARALLEL} =~ ${NUMBER_REGEXPR} ]] || ! [[ ${PAUSE_TIME} =~ ${NUMBER_REGEXPR} ]]; then
    colorEcho "error" "instances_in_parallel/pause_time parameter is not a number. Please check your params!\nExiting..."
    exit 1
  else
    echo "instances_in_parallel/pause_time parameters OK"
  fi
}

function checkADOnDemandCapacity(){
  #ITSMS-657 - Esternalizzare base OnDemand
  if [ "${ONDEMAND_BASE_CAPACITY}" = "" ] || [ "${ONDEMAND_BASE_CAPACITY}" = "null" ]; then
    ONDEMAND_BASE_CAPACITY=0
  fi

  if [ ${ONDEMAND_BASE_CAPACITY} -lt 0 ] || [ ${ONDEMAND_BASE_CAPACITY} -gt ${NODE_ASG_MAX_SIZE} ]; then
    colorEcho "error" "Parameter \"ondemand_base_capacity\" not valid, because cannot be lower then 0 or greater then max node size. Please check your configuration."
    exit 1
  elif [ ${ONDEMAND_BASE_CAPACITY} -gt 0 ] && [ "${IS_SPOT}" != "true" ]; then
    colorEcho "error" "Parameter \"ondemand_base_capacity\" can be used only spot instances. Please check your configuration."
  else
    echo "Parameter \"ondemand_base_capacity\" OK"
  fi
}


checkMPEKSVersion(){
  ACTUAL_EKS_VERSION="$(echo ${NODE_IMAGE_IDSSM_PARAM_CHECK} | cut -d "/" -f 6 | cut -d "." -f2)"
  echo "Actual EKS version: 1.${ACTUAL_EKS_VERSION}"
  EKS_VERSION="$(echo ${DEPLOY_DATAPANEL_VERSION} | cut -d "." -f 2)"
  echo "EKS version to deploy: 1.${EKS_VERSION}"

  if [ "${EKS_VERSION}" -lt "${ACTUAL_EKS_VERSION}" ]; then
    >&2 colorEcho "error" "ATTENTION: the eks version on git repo (${EKS_VERSION}) is less then actual version (${ACTUAL_EKS_VERSION}). Please check your datapanel_version!\nExiting"
    exit 1
  fi
}

checkMPTains(){
  if [ -n "${TAINTS}" ]; then
    KUBELET_EXTRA_ARGS="--node-labels=k8s.amazonaws.com/eniConfig=\$AWS_AZ,${LABELS} --register-with-taints=${TAINTS}"
  elif [ -n "${LABELS}" ]; then
    KUBELET_EXTRA_ARGS="--node-labels=k8s.amazonaws.com/eniConfig=\$AWS_AZ,${LABELS}"
  else
    KUBELET_EXTRA_ARGS="--node-labels=k8s.amazonaws.com/eniConfig=\$AWS_AZ"
  fi
}


setNodeIstancesTypeToCheck(){
  NODE_INSTANCE_TYPE_CHECK_TEMPLATE="$(aws cloudformation get-template --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region="${DEPLOY_AWS_REGION}" | jq '.TemplateBody')"
  if [[ "${NODE_INSTANCE_TYPE_CHECK_TEMPLATE}" == *"HasNodeInstanceType"* ]]; then
    NODE_INSTANCE_TYPE_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeInstanceType") | .ParameterValue')"
    SKIP_NODEGROUP_TYPE_PARAMETER_CHECK="false"
  else
    if [ "${IS_SPOT}" = "true" ]; then
      NODE_INSTANCE_TYPE_CHECK="$(echo "${NODE_INSTANCE_TYPE_CHECK_TEMPLATE}" | awk '/- InstanceType:/ {print $3}' | sed 's/\\//g;s/\"//g' | tr "\n" ",")"
    else
      NODE_INSTANCE_TYPE_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeInstanceType") | .ParameterValue')"
    fi
    SKIP_NODEGROUP_TYPE_PARAMETER_CHECK="true"
  fi
  NODE_INSTANCE_TYPE_CHECK_ARR=( $(echo "${NODE_INSTANCE_TYPE_CHECK}" | tr "," " " ) )
}


checkMPBootstrapArguments(){
  if [ "${BOOTSTRAP_ARGUMENTS// /}" = "${BOOTSTRAP_ARGUMENTS_CHECK_NO_MAXPODS// /}" ]; then
    echo "BOOTSTRAP_ARGUMENTS check OK: ${BOOTSTRAP_ARGUMENTS}"
  else
    >&2 colorEcho "error" "BOOTSTRAP_ARGUMENTS check KO (plan_param - cf_param): ${BOOTSTRAP_ARGUMENTS} - ${BOOTSTRAP_ARGUMENTS_CHECK_NO_MAXPODS}"
    exit 1
  fi
}


checkMPClusterAPIEndpoint(){
  if [ "${CLUSTER_API_ENDPOINT}" = "${CLUSTER_API_ENDPOINT_CHECK}" ] || [ "${CLUSTER_API_ENDPOINT}" = "https://${CLUSTER_API_ENDPOINT_CHECK}" ]; then
    echo "CLUSTER_API_ENDPOINT check OK: ${CLUSTER_API_ENDPOINT}"
  else
    if [[ "${CLUSTER_API_ENDPOINT_CHECK}" = "" ]]; then #added for retrocompatibility cloudformation (cf without this parameter)
      echo "CLUSTER_API_ENDPOINT not present"
    else
      >&2 colorEcho "error" "CLUSTER_API_ENDPOINT check KO (plan_param - cf_param): ${CLUSTER_API_ENDPOINT} - ${CLUSTER_API_ENDPOINT_CHECK}"
      exit 1
    fi
  fi
}


checkMPClusterControlplaneSecurityGroups(){
  if [ "${CLUSTER_CONTROLPLANE_SECURITYGROUP}" = "${CLUSTER_CONTROLPLANE_SECURITYGROUP_CHECK}" ]; then
    echo "CLUSTER_CONTROLPLANE_SECURITYGROUP check OK: ${CLUSTER_CONTROLPLANE_SECURITYGROUP}"
  else
    >&2 colorEcho "error" "CLUSTER_CONTROLPLANE_SECURITYGROUP check KO (plan_param - cf_param): ${CLUSTER_CONTROLPLANE_SECURITYGROUP} - ${CLUSTER_CONTROLPLANE_SECURITYGROUP_CHECK}"
    exit 1
  fi
}


checkMPClusterName(){
  if [ "${CLUSTER_NAME}" = "${CLUSTER_NAME_CHECK}" ]; then
    echo "CLUSTER_NAME check OK: ${CLUSTER_NAME_EXTENDED}"
  else
    >&2 colorEcho "error" "CLUSTER_NAME check KO (plan_param - cf_param): ${CLUSTER_NAME_EXTENDED} - ${CLUSTER_NAME_EXTENDED_CHECK}"
    exit 1
  fi
}


checkMPEnvironmentTagParameter(){
  if [ "${ENVIRONMENT_TAG_PARAMETER}" = "${ENVIRONMENT_TAG_PARAMETER_CHECK}" ]; then
    echo "ENVIRONMENT_TAG_PARAMETER check OK: ${ENVIRONMENT_TAG_PARAMETER}"
  else
    >&2 colorEcho "error" "ENVIRONMENT_TAG_PARAMETER check KO (plan_param - cf_param): ${ENVIRONMENT_TAG_PARAMETER} - ${ENVIRONMENT_TAG_PARAMETER_CHECK}"
    exit 1
  fi
}

checkMPKeyName(){
  if [ "${KEY_NAME}" = "${KEY_NAME_CHECK}" ]; then
    echo "KEY_NAME check OK: ${KEY_NAME}"
  else
    >&2 colorEcho "KEY_NAME check KO (plan_param - cf_param): ${KEY_NAME} - ${KEY_NAME_CHECK}"
    exit 1
  fi
}

checkMPNodeGroupName(){
  if [ "${NODEGROUP_NAME}" = "${NODEGROUP_NAME_CHECK}" ]; then
    echo "NODEGROUP_NAME check OK: ${NODEGROUP_NAME}"
  else
    >&2 colorEcho "NODEGROUP_NAME check KO (plan_param - cf_param): ${NODEGROUP_NAME} - ${NODEGROUP_NAME_CHECK}"
    exit 1
  fi
  if [ "${SKIP_NODEGROUP_TYPE_PARAMETER_CHECK}" = "false" ]; then
    if [ "${NODEGROUP_TYPE_PARAMETER}" = "${NODEGROUP_TYPE_PARAMETER_CHECK}" ]; then
      echo "NODEGROUP_TYPE_PARAMETER check OK: ${NODEGROUP_TYPE_PARAMETER}"
    else
      >&2 colorEcho "error" "NODEGROUP_TYPE_PARAMETER check KO (plan_param - cf_param): ${NODEGROUP_TYPE_PARAMETER} - ${NODEGROUP_TYPE_PARAMETER_CHECK}"
      exit 1
    fi
  else
    echo "NODEGROUP_TYPE_PARAMETER check not possible due to old Cloudformation"
  fi
}


checkMPSecurityGroupsIds(){
  SECURITY_GROUP_IDS_PARAMETER_SORTED="$(echo ${SECURITY_GROUP_IDS_PARAMETER} | tr "," "\n" | sort | tr "\n" "," | sed 's/,$//')"
  SECURITY_GROUP_IDS_PARAMETER_CHECK_SORTED="$(echo ${SECURITY_GROUP_IDS_PARAMETER_CHECK} | tr "," "\n" | sort | tr "\n" "," | sed 's/,$//')"
  if [ "${SECURITY_GROUP_IDS_PARAMETER_SORTED}" = "${SECURITY_GROUP_IDS_PARAMETER_CHECK_SORTED}" ]; then
    echo "SECURITY_GROUP_IDS_PARAMETER check OK: ${SECURITY_GROUP_IDS_PARAMETER}"
  else
    >&2 colorEcho "error" "SECURITY_GROUP_IDS_PARAMETER check KO (plan_param - cf_param): ${SECURITY_GROUP_IDS_PARAMETER} - ${SECURITY_GROUP_IDS_PARAMETER_CHECK}"
    exit 1
  fi
}

checkMPSubnets(){
  if [ "${SUBNET_AZ}" != "" ] && [ "${SUBNET_AZ}" != "null" ]; then
    if [ "${SUBNET_AZ}" = "${BE_SUBNET_IDS_PARAMETER_CHECK}" ]; then
      echo "SUBNET_AZ check OK: ${SUBNET_AZ}"
    else
      >&2 colorEcho "error" "SUBNET_AZ check KO (plan_param - cf_param): ${SUBNET_AZ} - ${BE_SUBNET_IDS_PARAMETER_CHECK}"
      exit 1
    fi
  else
    BE_SUBNET_IDS_PARAMETER_SORTED="$(echo ${BE_SUBNET_IDS_PARAMETER} | tr "," "\n" | sort | tr "\n" "," | sed 's/,$//')"
    BE_SUBNET_IDS_PARAMETER_CHECK_SORTED="$(echo ${BE_SUBNET_IDS_PARAMETER_CHECK} | tr "," "\n" | sort | tr "\n" "," | sed 's/,$//')"
    if [ "${BE_SUBNET_IDS_PARAMETER_SORTED}" = "${BE_SUBNET_IDS_PARAMETER_CHECK_SORTED}" ]; then
      echo "BE_SUBNET_IDS_PARAMETER check OK: ${BE_SUBNET_IDS_PARAMETER}"
    else
      >&2 colorEcho "error" "BE_SUBNET_IDS_PARAMETER check KO (plan_param - cf_param): ${BE_SUBNET_IDS_PARAMETER} - ${BE_SUBNET_IDS_PARAMETER_CHECK}"
      exit 1
    fi
  fi
}


checkMPVpcID(){
  if [ "${VPC_ID_PARAMETER}" = "${VPC_ID_PARAMETER_CHECK}" ]; then
    echo "VPC_ID_PARAMETER check OK: ${VPC_ID_PARAMETER}"
  else
    >&2 colorEcho "error" "VPC_ID_PARAMETER check KO (plan_param - cf_param): ${VPC_ID_PARAMETER} - ${VPC_ID_PARAMETER_CHECK}"
    exit 1
  fi
}


checkNMPBackupParam(){
  if [ "${BACKUP_PARAMETER}" = "${BACKUP_PARAMETER_CHECK}" ]; then
    echo "BACKUP_PARAMETER check OK: ${BACKUP_PARAMETER}"
  else
    echo "BACKUP_PARAMETER check KO (plan_param - cf_param): ${BACKUP_PARAMETER} - ${BACKUP_PARAMETER_CHECK}"
  fi
}

checkNMPNodeInstanceType(){
  if [ "${NODE_INSTANCE_TYPE_ARR[*]}" = "${NODE_INSTANCE_TYPE_CHECK_ARR[*]}" ]; then
    echo "NODE_INSTANCE_TYPE check OK: ${NODE_INSTANCE_TYPE_ARR[*]}"
    #jq -r --arg i "${i}" --arg machine_size_parameter "${NODE_INSTANCE_TYPE_CHECK}" '.nodegroups[$i|tonumber].cloudformation_options.machine_size_parameter |= $machine_size_parameter' deploy_and_release_variables.json > deploy_and_release_variables.json.tmp && mv deploy_and_release_variables.json.tmp deploy_and_release_variables.json
  else
    echo "NODE_INSTANCE_TYPE check KO (plan_param - cf_param): ${NODE_INSTANCE_TYPE_ARR[*]} - ${NODE_INSTANCE_TYPE_CHECK_ARR[*]}"
    colorEcho "warning" "ATTENTION: IN NEXT STEP ALL NODES WILL BE RESTARTED!"
    #jq -r --arg i "${i}" --arg machine_size_parameter "${NODE_INSTANCE_TYPE}" '.nodegroups[$i|tonumber].cloudformation_options.machine_size_parameter |= $machine_size_parameter' deploy_and_release_variables.json > deploy_and_release_variables.json.tmp && mv deploy_and_release_variables.json.tmp deploy_and_release_variables.json
  fi
}

checkNMPNodeImageIDSSM(){
  if [ "${NODE_IMAGE_IDSSM_PARAM}" = "${NODE_IMAGE_IDSSM_PARAM_CHECK}" ]; then
    echo "NODE_IMAGE_IDSSM_PARAM check OK: ${NODE_IMAGE_IDSSM_PARAM}"
  else
    echo "NODE_IMAGE_IDSSM_PARAM check KO (plan_param - cf_param): ${NODE_IMAGE_IDSSM_PARAM} - ${NODE_IMAGE_IDSSM_PARAM_CHECK}"
    colorEcho "warning" "ATTENTION: IN NEXT STEP ALL NODES WILL BE RESTARTED FOR UPGRADE TO NEW EKS VERSION!"
  fi
}

checkNMPNodeAsgDesiredCapacity(){
  if [ "${NODE_ASG_DESIRED_CAPACITY}" = "${NODE_ASG_DESIRED_CAPACITY_CHECK}" ]; then
    echo "NODE_ASG_DESIRED_CAPACITY check OK: ${NODE_ASG_DESIRED_CAPACITY}"
  else
    echo "NODE_ASG_DESIRED_CAPACITY check KO (plan_param - cf_param): ${NODE_ASG_DESIRED_CAPACITY} - ${NODE_ASG_DESIRED_CAPACITY_CHECK}"
  fi
}

checkNMPNodeAsgMaxSize(){
  if [ "${NODE_ASG_MAX_SIZE}" = "${NODE_ASG_MAX_SIZE_CHECK}" ]; then
    echo "NODE_ASG_MAX_SIZE check OK: ${NODE_ASG_MAX_SIZE}"
  else
    echo "NODE_ASG_MAX_SIZE check KO (plan_param - cf_param): ${NODE_ASG_MAX_SIZE} - ${NODE_ASG_MAX_SIZE_CHECK}"
  fi
}

checkNMPNodeAsgMinSize(){
  if [ "${NODE_ASG_MIN_SIZE}" = "${NODE_ASG_MIN_SIZE_CHECK}" ]; then
    echo "NODE_ASG_MIN_SIZE check OK: ${NODE_ASG_MIN_SIZE}"
  else
    echo "NODE_ASG_MIN_SIZE check KO (plan_param - cf_param): ${NODE_ASG_MIN_SIZE} - ${NODE_ASG_MIN_SIZE_CHECK}"
  fi
}

checkNMPNodeImgId(){
  if [ "${NODE_IMAGE_ID}" = "${NODE_IMAGE_ID_CHECK}" ]; then
    echo "NODE_IMAGE_ID check OK: ${NODE_IMAGE_ID}"
  else
    echo "NODE_IMAGE_ID check KO (plan_param - cf_param): ${NODE_IMAGE_ID} - ${NODE_IMAGE_ID_CHECK}"
  fi
}

checkNMPNodeVolumeSize(){
  if [ "${NODE_VOLUME_SIZE}" = "${NODE_VOLUME_SIZE_CHECK}" ]; then
    echo "NODE_VOLUME_SIZE check OK: ${NODE_VOLUME_SIZE}"
  else
    colorEcho "warning" "NODE_VOLUME_SIZE check KO (plan_param - cf_param): ${NODE_VOLUME_SIZE} - ${NODE_VOLUME_SIZE_CHECK}"
  fi
}

checkNMPNodeVolumeType(){
  if [ "${NODE_VOLUME_TYPE_CHECK}" != "" ] && [ "${NODE_VOLUME_TYPE_CHECK}" != "null" ] ; then
    if [ "${NODE_VOLUME_TYPE}" = "${NODE_VOLUME_TYPE_CHECK}" ]; then
      echo "NODE_VOLUME_TYPE check OK: ${NODE_VOLUME_TYPE}"
    else
      colorEcho "warning" "NODE_VOLUME_TYPE check KO (plan_param - cf_param): ${NODE_VOLUME_TYPE} - ${NODE_VOLUME_TYPE_CHECK}"
    fi
  fi
}

checkNMPNodeVolumeIOPS(){
  if [ "${NODE_VOLUME_IOPS_CHECK}" != "" ] && [ "${NODE_VOLUME_IOPS_CHECK}" != "null" ] ; then
    if [ "${NODE_VOLUME_IOPS}" = "${NODE_VOLUME_IOPS_CHECK}" ]; then
      echo "NODE_VOLUME_IOPS check OK: ${NODE_VOLUME_IOPS}"
    else
      colorEcho "warning" "NODE_VOLUME_IOPS check KO (plan_param - cf_param): ${NODE_VOLUME_IOPS} - ${NODE_VOLUME_IOPS_CHECK}"
    fi
  fi
}

checkNMPOnDemandBaseCapacity(){
  if [ "${ONDEMAND_BASE_CAPACITY_CHECK}" != "" ] && [ "${ONDEMAND_BASE_CAPACITY_CHECK}" != "null" ] ; then
    if [ "${ONDEMAND_BASE_CAPACITY}" = "${ONDEMAND_BASE_CAPACITY_CHECK}" ]; then
      echo "ondemand_base_capacity check OK: ${ONDEMAND_BASE_CAPACITY}"
    else
      colorEcho "warning" "ondemand_base_capacity check KO (plan_param - cf_param): ${ONDEMAND_BASE_CAPACITY} - ${ONDEMAND_BASE_CAPACITY_CHECK}"
    fi
  fi
}