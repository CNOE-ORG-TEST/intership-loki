. /log.sh
. /functions.sh

# show values of variables in variables.json and automation_conf.json files
#void
function showVariables(){
  cd /shared
  echo "common variables:"
  cat ./variables.json
  echo "group node variables:"
  cat ./automation_conf.json
  cd /
}

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


# check if exist cloud formation
# $1 : name of the cloud formation to check
# $2 : region where deploy the cf
# return : string ( "true" if CF exist, "false" otherwise )
function existCF () {
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


# retrieve EKS parameters
# $1 : cluster name
# define global variables
function retrieveEksParameters(){
  local EKS_DESCRIPTION="$(aws eks describe-cluster --name "${1}" 2>&1)"
  echo "Retrieving parameters from eks cluster..."
  CLUSTER_API_ENDPOINT="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.endpoint')"
  CA_DATA_B64="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.certificateAuthority.data')"
  CLUSTER_CONTROLPLANE_SECURITYGROUP="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.resourcesVpcConfig.clusterSecurityGroupId')"
}


# configure access to cluster
# $1 : name of the cluster
# $2 : region where cluster is deployed
# void
function configureClusterAccess() {
    aws eks update-kubeconfig --region "${2}" --name "${1}"
}

# check if group node need to be updated
# groupNode id
# return : string ( "true" if group node need to be updated, "false" otherwise )
function needToUpdateGroupNode(){
  echo "$(jq -r --arg i "${1}" '.nodegroups[$i|tonumber].update' ./automation_conf.json)"
}

function createNodeGroup(){
  echo "Deploying cloudformation ${DATAPANEL_CLOUDFORMATION_NAME}"
  aws cloudformation create-stack --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --parameters file://cloudformation_parameters.json --template-body "${TEMPLATE_BODY}" --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND" --region "${DEPLOY_AWS_REGION}"
  aws cloudformation wait stack-create-complete --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region "${DEPLOY_AWS_REGION}"
}


function updateNodeGroup(){
  #CHECK CHANGE SET: IF EXISTS A CHANGE SET WITH ACTION DELETE -> ERROR
  echo "Checking if change are present before to update the stack ${DATAPANEL_CLOUDFORMATION_NAME}"
  CHANGE_SETS_NAME="change-set-update-$RANDOM"
  aws cloudformation create-change-set --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --change-set-name ${CHANGE_SETS_NAME} --change-set-type UPDATE  --parameters file://cloudformation_parameters.json  --template-body "${TEMPLATE_BODY}" --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND" --region "${DEPLOY_AWS_REGION}"
  set +e
  aws cloudformation wait change-set-create-complete --change-set-name ${CHANGE_SETS_NAME} --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region "${DEPLOY_AWS_REGION}"
  RETURN_CODE=$?
  set -e
  CHANGE_SETS="$(aws cloudformation describe-change-set --change-set-name ${CHANGE_SETS_NAME} --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region="${DEPLOY_AWS_REGION}" 2>&1)"
  if [ "${RETURN_CODE}" -ne 0 ]; then
    CHANGE_SETS_STATUS="$(echo "${CHANGE_SETS}" | jq -r '.Status')"
    CHANGE_SETS_REASON="$(echo "${CHANGE_SETS}" | jq -r '.StatusReason')"
    if [ "${CHANGE_SETS_STATUS}" = "FAILED" ] && [[ "${CHANGE_SETS_REASON}" == *"Submit different information to create a change set"* ]]; then
      echo "The submitted information didn't contain changes. Submit different information to create a change set."
    else
      >&2 colorEcho "error" "Changeset is in ERROR state, please check on AWS Console. Exiting..."
      exit 1
    fi
  fi
  set +e
  mapfile -t ACTIONS < <(echo "${CHANGE_SETS}" | jq -r '.Changes[].ResourceChange.Action')
  set -e
  if [ "${ACTIONS[*]}" != "" ] && [ "${ACTIONS[*]}" != "null" ]; then
    echo "ChangeSet are present, checking if are safe"
    DELETED_RESOURCES=$(echo "${CHANGE_SETS}" | jq -r '.Changes[].ResourceChange | select( (.Action == "Delete") or (.Action == "Remove") )  | .ResourceType')
    if [[ "${DELETED_RESOURCES[*]}" != "AWS::AutoScaling::LaunchConfiguration" ]] && [[ "${DELETED_RESOURCES[*]}" != "" ]] &&  [[ "${DELETED_RESOURCES[*]}" != "null" ]]; then
    #if [[ "${ACTIONS[*]}" == *"Remove"* ]] || [[ "${ACTIONS[*]}" == *"Delete"* ]]; then
      >&2 colorEcho "error" "
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗    ██╗███╗   ██╗████████╗███████╗██████╗ ██████╗ ██╗   ██╗██████╗ ████████╗███████╗██████╗ ██╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝    ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██║   ██║██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██║
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗      ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝██████╔╝██║   ██║██████╔╝   ██║   █████╗  ██║  ██║██║
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝      ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██╔══██╗██║   ██║██╔═══╝    ██║   ██╔══╝  ██║  ██║╚═╝
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗    ██║██║ ╚████║   ██║   ███████╗██║  ██║██║  ██║╚██████╔╝██║        ██║   ███████╗██████╔╝██╗
╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝    ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝        ╚═╝   ╚══════╝╚═════╝ ╚═╝
      "
      >&2 colorEcho "error" "Attention, a resource could be deleted, the update will be interrupted! Please, check you params! Exiting ..."
      mapfile -t PHYSICAL_RESOURCES_TO_REMOVE_ID < <(echo "${CHANGE_SETS}" | jq -r '.Changes[] | select(.ResourceChange.Action=="Remove") | .ResourceChange.PhysicalResourceId')
      >&2 colorEcho "error" "PHYSICAL_RESOURCES_TO_REMOVE_ID = ${PHYSICAL_RESOURCES_TO_REMOVE_ID[*]}"
      exit 1
    else
      echo "All change sets are safe!\nUpdating cloudformation ${DATAPANEL_CLOUDFORMATION_NAME}..."
    fi
  else
    echo "ChangeSet are NOT present"
  fi
  aws cloudformation delete-change-set --change-set-name ${CHANGE_SETS_NAME} --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region "${DEPLOY_AWS_REGION}"

  #Print logs continuously to avoid Bamboo hand during large CF deployments
  export cf_name="${DATAPANEL_CLOUDFORMATION_NAME}"
  python /waiting_logs.py &  #Start waiting logs
  set +e
  update_output=$(aws cloudformation update-stack --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --parameters file://cloudformation_parameters.json --template-body "${TEMPLATE_BODY}" --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND" --region "${DEPLOY_AWS_REGION}"  --role-arn "${ROLE_ARN}" 2>&1)
  status=$?
  echo "${update_output}"
  set -e

  init_timestamp=""
  if [ $status -ne 0 ] ; then
    if [[ $update_output == *"ValidationError"* && $update_output == *"No updates"* ]] ; then
      echo "Finished create/update - no updates to be performed"
    elif [[ $update_output == *"ValidationError"* ]]; then
      >&2 colorEcho "error" "Cloudformation can not be updated due to ValidationError. Exiting..."
      rm -f $cf_deploy_flag_file
      exit 1
    else
      set +e
      wait_response=$(aws cloudformation wait stack-update-complete --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region "${DEPLOY_AWS_REGION}" 2>&1)
      set -e
      count=1
      while [[ ${wait_response} == *"Max attempts exceeded"* ]] && [ ${count} -le 15 ]; do
        echo "Tentative number: ${count} "
        set +e
        wait_response=$(aws cloudformation wait stack-update-complete --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region "${DEPLOY_AWS_REGION}" 2>&1)
        set -e
        ((count++))
      done
      >&2 aws cloudformation describe-stack-events --stack "${DATAPANEL_CLOUDFORMATION_NAME}" --query "StackEvents[?Timestamp > \`${init_timestamp}\`] | sort_by(@, &Timestamp)" --max-items 50 --region "${DEPLOY_AWS_REGION}" | jq -r '.[] | .Timestamp + " - " + .ResourceType + " - " + .ResourceStatus + " - " + .LogicalResourceId + " - " + .ResourceStatusReason'
      rm -f $cf_deploy_flag_file
      exit 1
    fi
  else
    set +e
    wait_response=$(aws cloudformation wait stack-update-complete --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region "${DEPLOY_AWS_REGION}" 2>&1)
    set -e
    count=1
    while [[ ${wait_response} == *"Max attempts exceeded"* ]] && [ ${count} -le 15 ]; do
      echo "Tentative number: ${count} "
      set +e
      wait_response=$(aws cloudformation wait stack-update-complete --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region "${DEPLOY_AWS_REGION}" 2>&1)
      set -e
      ((count++))
    done
    if [[ "${wait_response}" == *"failed"* ]]; then
      >&2 colorEcho "error" "Cloudformation is in failed state. Please check logs in console.(wait_response=${wait_response})"
      >&2 aws cloudformation describe-stack-events --stack "${DATAPANEL_CLOUDFORMATION_NAME}" --query "StackEvents[?Timestamp > \`${init_timestamp}\`] | sort_by(@, &Timestamp)" --max-items 50 --region "${DEPLOY_AWS_REGION}" | jq -r '.[] | .Timestamp + " - " + .ResourceType + " - " + .ResourceStatus + " - " + .LogicalResourceId + " - " + .ResourceStatusReason'
      rm -f $cf_deploy_flag_file
      exit 1
    fi
  fi
}


# attach group node to cluster
# void
function attachGroupNodeToCluster() {
  echo "Checking if this nodegroup is attached to cluster ${CLUSTER_NAME}..."
  DATAPANEL_CLOUDFORMATION="$(aws cloudformation describe-stacks --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region="${DEPLOY_AWS_REGION}" 2>&1)"
  NODE_INSTANCE_ROLE_ARN="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="NodeInstanceRole") | .OutputValue')"
  ROLE="    - rolearn: ${NODE_INSTANCE_ROLE_ARN}\n      username: system:node:{{EC2PrivateDNSName}}\n      groups:\n        - system:bootstrappers\n        - system:nodes"
  set +e
  AWS_AUTH="$(kubectl get -n kube-system configmap/aws-auth -o yaml 2>&1)"
  set -e
  if [[ "${AWS_AUTH}" == *"configmaps \"aws-auth\" not found"* ]]; then
    echo "Config map aws-auth not found. Will be created.."
    generateAwsAuthConfigMap
  fi

  if [[ "${AWS_AUTH}" != *"${NODE_INSTANCE_ROLE_ARN}"* ]]; then
    echo "Attaching this nodegroup to cluster ${CLUSTER_NAME}"
    kubectl get -n kube-system configmap/aws-auth -o yaml | awk "/mapRoles: \|/{print;print \"${ROLE}\";next}1" > /tmp/aws-auth-patch.yml
    kubectl patch configmap/aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yml)"
    echo "NodeGroup attached..."
  else
    echo "This nodegroup is already attached to cluster ${CLUSTER_NAME}"
  fi
}

# create/update group node
# datapanel cloudformation name
# groupNode id
# void
function createOrUpdateGroupNode() {
  local DATAPANEL_CLOUDFORMATION_NAME=${1}
  local i=${2}

  echo "The cloudformation \"${DATAPANEL_CLOUDFORMATION_NAME}\" will be updated. Update flag is true."
  duplicateFileToDeploy

  echo "Retrieving parameters from automation_conf.json..."

  cd /shared
  BACKUP_PARAMETER="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.backup_parameter' automation_conf.json)"
  NODEGROUP_NAME="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.tag_nodegroup_name' automation_conf.json)"
  SUBNET_AZ="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.subnet_az' automation_conf.json)"
  NODE_ASG_MAX_SIZE="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_max' automation_conf.json)"
  NODE_ASG_MIN_SIZE="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_min' automation_conf.json)"
  NODE_ASG_DESIRED_CAPACITY="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_desidered' automation_conf.json)"
  NODE_VOLUME_SIZE="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_volume.size' automation_conf.json)"
  NODE_VOLUME_TYPE="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_volume.type' automation_conf.json)"
  NODE_VOLUME_IOPS="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_volume.iops' automation_conf.json)"
  NODE_VOLUME_THROUGHPUT="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.node_volume.throughput' automation_conf.json)"
  ONDEMAND_BASE_CAPACITY="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.ondemand_base_capacity' automation_conf.json)"
  MAX_PODS="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.max_pods' automation_conf.json)"
  IS_SPOT="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.is_spot' automation_conf.json)"
  IS_GRAVITON="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.is_graviton' automation_conf.json)"
  IS_GPU="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.is_gpu' automation_conf.json)"
  TAINTS="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.taints' automation_conf.json)"
  LABELS="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.labels' automation_conf.json)"
  #NODE_INSTANCE_TYPE_ARR=( $(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.machine_size_parameter' automation_conf.json | tr "," " ") )
  mapfile -t NODE_INSTANCE_TYPE_ARR< <(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.machine_size[]' automation_conf.json)
  NODE_INSTANCE_TYPE="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.machine_size[]' automation_conf.json | tr "\n" ",")"
  NODE_IMAGE_ID=""
  INSTANCE_IN_PARALLEL="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.instances_in_parallel' automation_conf.json)"
  PAUSE_TIME="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_options.pause_time' automation_conf.json)"
  CUSTOM_KUBELET_EXTRA_ARGS="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].cloudformation_parameters.custom_kubelet_extra_args' automation_conf.json)"
  ONLY_MAJOR="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].only_major' automation_conf.json)"
  cd /

  setCFNodeInstanceType
  setCFKubeletExtraArgs
  BOOTSTRAP_ARGUMENTS="--use-max-pods false --kubelet-extra-args \\\\\"${KUBELET_EXTRA_ARGS}\\\\\" --apiserver-endpoint ${CLUSTER_API_ENDPOINT} --b64-cluster-ca ${CA_DATA_B64}"
  setCFNodeImgAndNodeGroupType
  if [ "$(existCF "${DATAPANEL_CLOUDFORMATION_NAME}" "${DEPLOY_AWS_REGION}")" = "false" ]; then
    echo "Cloudformation ${DATAPANEL_CLOUDFORMATION} doesn't exist.\nWill be created in this step!"
  else
    setCFAMI
  fi
  setCFNodeVolume
  setCFASG
  setCFOnDemandBaseCapacity
  CLUSTER_API_ENDPOINT_NOHTTPS="$(echo "${CLUSTER_API_ENDPOINT}" | sed 's|https://||g')"

  sed -i -e "s?__BACKUP_PARAMETER__?${BACKUP_PARAMETER}?g" /cloudformation_parameters.json
  sed -i -e "s?__BOOTSTRAP_ARGUMENTS__?${BOOTSTRAP_ARGUMENTS}?g" /cloudformation_parameters.json
  sed -i -e "s?__CLUSTER_API_ENDPOINT__?${CLUSTER_API_ENDPOINT_NOHTTPS}?g" /cloudformation_parameters.json
  sed -i -e "s?__CLUSTER_CONTROLPLANE_SECURITYGROUP__?${CLUSTER_CONTROLPLANE_SECURITYGROUP}?g" /cloudformation_parameters.json
  sed -i -e "s?__CLUSTER_NAME__?${CLUSTER_NAME_EXTENDED}?g" /cloudformation_parameters.json
  sed -i -e "s?__ENVIRONMENT_TAG_PARAMETER__?${ENVIRONMENT_TAG_PARAMETER}?g" /cloudformation_parameters.json
  sed -i -e "s?__KEY_NAME__?${KEY_NAME}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODE_ASG_DESIRED_CAPACITY__?${NODE_ASG_DESIRED_CAPACITY}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODE_ASG_MAX_SIZE__?${NODE_ASG_MAX_SIZE}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODE_ASG_MIN_SIZE__?${NODE_ASG_MIN_SIZE}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODEGROUP_NAME__?${NODEGROUP_NAME}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODEGROUP_TYPE_PARAMETER__?${NODEGROUP_TYPE_PARAMETER}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODE_IMAGE_ID__?${NODE_IMAGE_ID}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODE_IMAGE_IDSSM_PARAM__?${NODE_IMAGE_IDSSM_PARAM}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODE_INSTANCE_TYPE__?${NODE_INSTANCE_TYPE}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODE_VOLUME_SIZE__?${NODE_VOLUME_SIZE}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODE_VOLUME_TYPE__?${NODE_VOLUME_TYPE}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODE_VOLUME_IOPS__?${NODE_VOLUME_IOPS}?g" /cloudformation_parameters.json
  sed -i -e "s?__NODE_VOLUME_THROUGHPUT__?${NODE_VOLUME_THROUGHPUT}?g" /cloudformation_parameters.json
  sed -i -e "s?__ONDEMAND_BASE_CAPACITY__?${ONDEMAND_BASE_CAPACITY}?g" /cloudformation_parameters.json
  #sed -i -e "s?__PROJECT_TAG_PARAMETER__?${PROJECT_TAG_PARAMETER}?g" /cloudformation_parameters.json
  #sed -i -e "s?__RUNNING_TAG_PARAMETER__?${RUNNING_TAG_PARAMETER}?g" /cloudformation_parameters.json
  sed -i -e "s?__SECURITY_GROUP_IDS_PARAMETER__?${SECURITY_GROUP_IDS_PARAMETER}?g" /cloudformation_parameters.json
  sed -i -e "s?__VPC_ID__?${VPC_ID_PARAMETER}?g" /cloudformation_parameters.json
  #sed -i -e "s?__CLUSTER_TYPE__?${CLUSTER_TYPE}?g" /cloudformation_parameters.json


  yq -i eval '.Resources.NodeGroup.UpdatePolicy.AutoScalingRollingUpdate.PauseTime = "PT'${PAUSE_TIME}'M"' /cloudformation_template.yaml
  yq -i eval '.Resources.NodeGroup.UpdatePolicy.AutoScalingRollingUpdate.MaxBatchSize = "'${INSTANCE_IN_PARALLEL}'"' /cloudformation_template.yaml
  if [ "${SUBNET_AZ}" != "" ] && [ "${SUBNET_AZ}" != "null" ]; then
   echo "The parameter subnet_az is not empty. This means that this cloudformation ${DATAPANEL_CLOUDFORMATION_NAME} deploy a nodegroup with single az."
   SUSPEND_PROCESSES="          - \"AZRebalance\""
   echo "Adding SuspendProcesses option to cloudformation"
   yq e -i '.Resources.NodeGroup.UpdatePolicy.AutoScalingRollingUpdate.SuspendProcesses |= "__SUSPEND_PROCESSES__"' /cloudformation_template.yaml
   sed -i -e "s?__SUSPEND_PROCESSES__?\n${SUSPEND_PROCESSES}?g" /cloudformation_template.yaml
   sed -i -e "s?__SUBNETS__?${SUBNET_AZ}?g" /cloudformation_parameters.json
  else
   sed -i -e "s?__SUBNETS__?${BE_SUBNET_IDS_PARAMETER}?g" /cloudformation_parameters.json
  fi


  echo "CF parameters:"
  cat /cloudformation_parameters.json

  TEMPLATE_BODY="file://cloudformation_template.yaml"
  export cf_deploy_flag_file=$(mktemp)
  if [ "$(existCF "${DATAPANEL_CLOUDFORMATION_NAME}" "${DEPLOY_AWS_REGION}")" = "false" ]; then
    createNodeGroup
  else
    updateNodeGroup
  fi

  echo "Removing flag file"
  rm -f $cf_deploy_flag_file
  rm -f ./cloudformation_parameters.json ./cloudformation_template.yaml

  attachGroupNodeToCluster

}