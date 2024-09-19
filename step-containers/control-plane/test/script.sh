#!/bin/bash -e

. ./subSteps.sh

set -e
cd /shared
CLUSTER_NAME="$(jq -r '.clusterName' ./variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.env' ./variables.json)"
#SC_TAG_PARAMETER="$(jq -r '.scTagParameter' initialization_variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIds' ./variables.json)"
FE_SUBNET_IDS_PARAMETER="$(jq -r '.feSubnetIds' ./variables.json)"
BE_SUBNET_IDS_PARAMETER="$(jq -r '.beSubnetIds' ./variables.json)"
VPC_ID_PARAMETER="$(jq -r '.vpcId' ./variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' ./variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' ./variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.env' ./variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' ./variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' ./variables.json)"
CONTROLPANEL_VERSION="$(jq -r '.eksVersion' ./variables.json)"
# derived parameters
CLOUDFORMATION_NAME="cnoe-${CLUSTER_NAME}-controlpanel"
ROLE_NAME="cnoe-role-${CLUSTER_NAME}-cp"
ROLE_ARN="arn:aws:iam::${DEPLOY_AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
cd /

aws sts get-caller-identity
assignRoleToServiceAccount "${ROLE_ARN}" "${DEPLOY_AWS_REGION}"

# configure access to cluster
configureClusterAccess "${CLUSTER_NAME}" "${DEPLOY_AWS_REGION}"

#compute number of ready nodes
ACTUAL_NUMBER_NODE=$(getNumberOfReadyNodes)
echo "There are ${ACTUAL_NUMBER_NODE} nodes in the target cluster with secret."

if [ "${ACTUAL_NUMBER_NODE}" -gt 0 ]; then
  # if we are updating the cluster
  connetivityTest
  kubesystemDeploymentsTest
  podReadyPercentageTest
fi
