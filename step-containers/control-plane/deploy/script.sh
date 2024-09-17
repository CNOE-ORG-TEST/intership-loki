#!/bin/bash -e

. ./subSteps.sh

set -e

cd /shared

CLUSTER_NAME="$(jq -r '.clusterName' ./variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.env' ./variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIds' ./variables.json)"
FE_SUBNET_IDS_PARAMETER="$(jq -r '.feSubnetIds' ./variables.json)"
BE_SUBNET_IDS_PARAMETER="$(jq -r '.beSubnetIds' ./variables.json)"
VPC_ID_PARAMETER="$(jq -r '.vpcId' ./variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' ./variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' ./variables.json)"
# from deploy_and_release_variables.json
CONTROLPANEL_VERSION="$(jq -r '.eksVersion' ./variables.json)"
# derived parameters
ROLE_NAME="cnoe-role-${CLUSTER_NAME}-cp"
ROLE_ARN="arn:aws:iam::${DEPLOY_AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
CONTROL_CLOUDFORMATION_NAME="cnoe-${CLUSTER_NAME}-controlpanel"

cd /

assignRoleToServiceAccount "${ROLE_ARN}" "${DEPLOY_AWS_REGION}"

if [ "$(existClusterCF "${CONTROL_CLOUDFORMATION_NAME}" "${DEPLOY_AWS_REGION}")" = "false" ]; then
      deployCF "${CONTROL_CLOUDFORMATION_NAME}" "${DEPLOY_AWS_REGION}"  "${ENVIRONMENT_TAG_PARAMETER}"
else
      updateCF "${CONTROL_CLOUDFORMATION_NAME}" "${DEPLOY_AWS_REGION}"  "${ENVIRONMENT_TAG_PARAMETER}"
fi