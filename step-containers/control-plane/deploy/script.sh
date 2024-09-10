#!/bin/bash -e

set -e

cd /shared

CLUSTER_NAME="$(jq -r '.clusterName' ./variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.environment' ./variables.json)"
ENVIRONMENT="$(jq -r '.environment' ./variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIdsParameter' ./variables.json)"
FE_SUBNET_IDS_PARAMETER="$(jq -r '.feSubnetIdsParameter' ./variables.json)"
BE_SUBNET_IDS_PARAMETER="$(jq -r '.beSubnetIdsParameter' ./variables.json)"
VPC_ID_PARAMETER="$(jq -r '.vpcIdParameter' ./variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.account' ./variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' ./variables.json)"
# from deploy_and_release_variables.json
CONTROLPANEL_VERSION="$(jq -r '.eksVersion' ./variables.json)"
# derived parameters
ROLE_NAME="cnoe-role-${CLUSTER_NAME}-cp"
ROLE_ARN="arn:aws:iam::${DEPLOY_AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
CONTROL_CLOUDFORMATION_NAME="cnoe-${CLUSTER_NAME}-controlpanel"

cd /

assignRoleToServiceAccount "${ROLE_ARN}" "${DEPLOY_AWS_REGION}"

if [ "$(existClusterCF "${CLOUDFORMATION_NAME}" "${DEPLOY_AWS_REGION}")" = "false"]; then
      deployCF "${CLOUDFORMATION_NAME}" "${DEPLOY_AWS_REGION}"  "${ENVIRONMENT_TAG_PARAMETER}"
else
      updateCF "${CLOUDFORMATION_NAME}" "${DEPLOY_AWS_REGION}"  "${ENVIRONMENT_TAG_PARAMETER}"
fi