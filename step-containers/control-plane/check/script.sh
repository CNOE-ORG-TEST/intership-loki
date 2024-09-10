#!/bin/bash -e

. /subSteps.sh

set -e

cd /shared
cat ./variables.json

# from ./variables.json
CLUSTER_NAME="$(jq -r '.clusterName' ./variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.environment' ./variables.json)"
ENVIRONMENT="$(jq -r '.environment' ./variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIdsParameter' ./variables.json)"
FE_SUBNET_IDS_PARAMETER="$(jq -r '.feSubnetIdsParameter' ./variables.json)"
BE_SUBNET_IDS_PARAMETER="$(jq -r '.beSubnetIdsParameter' ./variables.json)"
VPC_ID_PARAMETER="$(jq -r '.vpcIdParameter' ./variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' ./variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' ./variables.json)"
# from deploy_and_release_variables.json
CLOUDFORMATION_NAME="cnoe-${CLUSTER_NAME}-controlpanel"
CONTROLPANEL_VERSION="$(jq -r '.eksVersion' ./variables.json)"
# derived parameters
ROLE_NAME="cnoe-role-${CLUSTER_NAME}-cp"
ROLE_ARN="arn:aws:iam::${DEPLOY_AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

assignRoleToServiceAccount "${ROLE_ARN}" "${DEPLOY_AWS_REGION}"

checkVPCs "${FE_SUBNET_IDS_PARAMETER}" "${BE_SUBNET_IDS_PARAMETER}"

if [ "$(existClusterCF "${CLOUDFORMATION_NAME}" "${DEPLOY_AWS_REGION}")" = "false"]; then
    # if don't exist cluster CF
    echo "Cloudformation ${CLOUDFORMATION_NAME} doesn't exist. Checking existence of cluster: ${CLUSTER_NAME_EXTENDED}"
    if [ "$(existCluster "${CLUSTER_NAME}")" = "false"]; then
      # if don't exist cluster CF and don't exist cluster
      echo "Cluster with name ${CLUSTER_NAME} doesn't exist"
      echo "OK: Cloudformation ${CLOUDFORMATION_NAME} will be created in next deploy step."
    else
      # if don't exist cluster CF but exist cluster
      >&2 colorEcho "error" "KO: Cloudformation ${CLOUDFORMATION_NAME} doesn't exist but cluster ${CLUSTER_NAME} exists."
      >&2 colorEcho "red" "Please check your params!"
      exit 1
      # ERROR !!!
    fi
else
  if [ "$(existCluster "${CLUSTER_NAME}")" = "true"]; then
    # if exist cluster CF and exist cluster

    # configure access to cluster
    configureClusterAccess "${CLUSTER_NAME}" "${DEPLOY_AWS_REGION}"

    # retrieve variables to check and check
    CF="$(aws cloudformation describe-stacks --stack-name "${CLOUDFORMATION_NAME}" --region="${DEPLOY_AWS_REGION}" 2>&1)"
    VPC_ID_PARAMETER_TO_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="VPCIdParameter") | .ParameterValue')"
    BE_SUBNET_IDS_PARAMETER_TO_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="SubnetIdsParameter") | .ParameterValue')"
    ENVIRONMENT_TAG_PARAMETER_TO_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="EnvironmentTagParameter") | .ParameterValue')"
    CLUSTER_NAME_TO_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="ClusterName") | .ParameterValue')"
    SECURITY_GROUP_IDS_PARAMETER_TO_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="SecurityGroupIdsParameter") | .ParameterValue')"

    echo "Checking before update cloudformation => CLOUDFORMATION_NAME=${CLOUDFORMATION_NAME}"

    checkNewControlpanelVersion "${CLUSTER_NAME}" "${CONTROLPANEL_VERSION}"
    checkControlpanelVsDatapanel "${CLUSTER_NAME}" "${CONTROLPANEL_VERSION}" "${DEPLOY_AWS_REGION}"
    checkControlpanelVsInfrpanel "${CLUSTER_NAME}" "${CONTROLPANEL_VERSION}"
    checkCFMandatoryParameters
  else
    >&2 colorEcho "error" "Cloudformation ${CLOUDFORMATION_NAME} exist but cluster ${CLUSTER_NAME} don't exists"
    >&2 colorEcho "red" "Please check your params!"
    exit 1
    # ERROR !!!
fi