
function duplicateFileToDeploy() {
  cd /shared
  cp ./nodegroups_parameter.json /cloudformation_parameters.json
  cp ./cloudformation_nodegroups.yaml /cloudformation_template.yaml
  cd /
}


function setCFNodeInstanceType(){
  if [ "${#NODE_INSTANCE_TYPE_ARR[*]}" -gt 1 ] && [ "${IS_SPOT}" != "true" ]; then
    >&2 colorEcho "error" "Node type different from SPOT cannot support multiple instance type. Please make sure you have only one instance type for OnDemand nodes. Exiting..."
    exit 1
  fi

  if [ "${#NODE_INSTANCE_TYPE_ARR[@]}" -eq "1" ]; then
    NODE_INSTANCE_TYPE="$(echo "${NODE_INSTANCE_TYPE_ARR[*]}" | tr " " ","),,"
  else
    NODE_INSTANCE_TYPE="$(echo "${NODE_INSTANCE_TYPE_ARR[*]}" | tr " " ","),"
  fi
}


function setCFKubeletExtraArgs(){
  if [ -n "${TAINTS}" ]; then
    KUBELET_EXTRA_ARGS="--node-labels=k8s.amazonaws.com/eniConfig=\$AWS_AZ,${LABELS} --register-with-taints=${TAINTS} --max-pods=${MAX_PODS}"
  elif [ -n "${LABELS}" ]; then
    KUBELET_EXTRA_ARGS="--node-labels=k8s.amazonaws.com/eniConfig=\$AWS_AZ,${LABELS} --max-pods=${MAX_PODS}"
  else
    KUBELET_EXTRA_ARGS="--node-labels=k8s.amazonaws.com/eniConfig=\$AWS_AZ --max-pods=${MAX_PODS}"
  fi

  if [ "${CUSTOM_KUBELET_EXTRA_ARGS}" != "null" ] && [ "${CUSTOM_KUBELET_EXTRA_ARGS}" != "" ]; then
    KUBELET_EXTRA_ARGS="${KUBELET_EXTRA_ARGS} ${CUSTOM_KUBELET_EXTRA_ARGS}"
    echo "Custom kubelet extra args: ${KUBELET_EXTRA_ARGS}"
  fi
}


function setCFNodeImgAndNodeGroupType(){
  if [ "${IS_SPOT}" = "true" ]; then
    echo "The nodegroup is of type spot"
    NODEGROUP_TYPE_PARAMETER="spot"
    NODE_IMAGE_IDSSM_PARAM="/aws/service/eks/optimized-ami/${DEPLOY_DATAPANEL_VERSION}/amazon-linux-2/recommended/image_id"
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

  echo "The NODE_IMAGE_IDSSM_PARAM is: ${NODE_IMAGE_IDSSM_PARAM}"
}


function setCFAMI(){
  NODE_IMAGE_IDSSM_PARAM_CHECK="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeImageIdSSMParam") | .ParameterValue')"
  ACTUAL_EKS_VERSION="$(echo ${NODE_IMAGE_IDSSM_PARAM_CHECK} | cut -d "/" -f 6 | cut -d "." -f2)"
  echo "Actual EKS version: 1.${ACTUAL_EKS_VERSION}"
  EKS_VERSION="$(echo ${DEPLOY_DATAPANEL_VERSION} | cut -d "." -f 2)"
  echo "EKS version to deploy: 1.${EKS_VERSION}"

  #OLD AMI
  if [ "${ONLY_MAJOR}" = "true" ] && [ "${ACTUAL_EKS_VERSION}" = "${EKS_VERSION}" ]; then
    echo "Only major is true and eks version is the same. Will be used old recommended ami"
    AMI="$(echo "${DATAPANEL_CLOUDFORMATION}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeImageIdSSMParam") | .ResolvedValue')"
    echo "AMI used is ${AMI}"
    NODE_IMAGE_ID="${AMI}"
  #NEW AMI
  else
    echo "Only major is false. Will be used new recommended ami"
  fi
}


function setCFNodeVolume(){
  #NODE_VOLUME_SIZE default 100 if is empty or null
  if [ "${NODE_VOLUME_SIZE}" = "" ] || [ "${NODE_VOLUME_SIZE}" = "null" ]; then
    NODE_VOLUME_SIZE="100"
    echo "No volume size specified. Setting default value ${NODE_VOLUME_SIZE}"
  fi
  #NODE_VOLUME_IOPS default 3000 if is empty or null
  if [ "${NODE_VOLUME_IOPS}" = "" ] || [ "${NODE_VOLUME_IOPS}" = "null" ]; then
    NODE_VOLUME_IOPS="3000"
    echo "No volume iops specified. Setting default value ${NODE_VOLUME_IOPS}"
  fi
  #NODE_VOLUME_TYPE default gp3 if is empty or null
  if [ "${NODE_VOLUME_TYPE}" = "" ] || [ "${NODE_VOLUME_TYPE}" = "null" ]; then
    NODE_VOLUME_TYPE="gp3"
    echo "No volume type specified. Setting default value ${NODE_VOLUME_TYPE}"
  fi
  #NODE_VOLUME_THROUGHPUT default 125 if is empty or null
  if [ "${NODE_VOLUME_THROUGHPUT}" = "" ] || [ "${NODE_VOLUME_THROUGHPUT}" = "null" ]; then
    NODE_VOLUME_THROUGHPUT="125"
    echo "No volume throughput specified. Setting default value ${NODE_VOLUME_THROUGHPUT}"
  fi
}


setCFASG(){
  #Retrieving the desired capacity from autoscaling group
  if  ASG_NAME=$(aws cloudformation describe-stacks --stack-name "${DATAPANEL_CLOUDFORMATION_NAME}" --region="${DEPLOY_AWS_REGION}"  --query "Stacks[0].Outputs[?OutputKey=='NodeGroup'].OutputValue" --output text 2>&1) ;then
    ASG_JSON=$(aws  autoscaling describe-auto-scaling-groups --auto-scaling-group-name "$ASG_NAME")
    NODE_ASG_RETRIEVED_VALUE=$(echo $ASG_JSON | jq -r '.AutoScalingGroups[0].DesiredCapacity')
  else
    echo "The stack ${DATAPANEL_CLOUDFORMATION_NAME} has not been created yet, the desired capacity will be retrieved from the configuration json file"
  fi

  if [[ "${NODE_ASG_RETRIEVED_VALUE}" -gt "${NODE_ASG_DESIRED_CAPACITY}" ]] && [[ "${NODE_ASG_RETRIEVED_VALUE}" -le "${NODE_ASG_MAX_SIZE}" ]]; then
      echo "The number of desired nodes retrieved from the autoscaling group is greater than node_desidered param in automation_conf.json\The desidered capacity will be equal to number of nodes retrieved from the stack"
      NODE_ASG_DESIRED_CAPACITY=${NODE_ASG_RETRIEVED_VALUE}
  fi
  echo "The desidered capacity of this nodegroup is: ${NODE_ASG_DESIRED_CAPACITY}"
}


setCFOnDemandBaseCapacity(){
  if [ "${ONDEMAND_BASE_CAPACITY}" = "" ] || [ "${ONDEMAND_BASE_CAPACITY}" = "null" ]; then
    ONDEMAND_BASE_CAPACITY=0
  fi
}


function generateAwsAuthConfigMap () {
cat <<EOF>> aws-auth.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - groups:
      - system:bootstrappers
      - system:nodes
      rolearn: arn:aws:iam::${DEPLOY_AWS_ACCOUNT_ID}:role/${ROLE_NAME}
      username: system:node:{{EC2PrivateDNSName}}
EOF
sed -i -E 's/[[:space:]]+$//g' aws-auth.yaml
kubectl --kubeconfig="${ACTUAL_KUBECONF}" --context="${DOMAIN}" apply -f aws-auth.yaml
}