#!/bin/bash -e

. /log.sh
. /functions.sh

set -e

cd /shared

# variables.json variables
CLUSTER_NAME="$(jq -r '.clusterName' ./variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.env' ./variables.json)"
KEY_NAME="$(jq -r '.keyName' ./variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIds' ./variables.json | sed 's/ //g')"
BE_SUBNET_IDS_PARAMETER="$(jq -r '.beSubnetIds' ./variables.json | sed 's/ //g')"
VPC_ID_PARAMETER="$(jq -r '.vpcId' ./variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' ./variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' ./variables.json)"
ENVIRONMENT="$(jq -r '.env' ./variables.json)"
#automation_conf.json
DATAPANEL_VERSION="$(jq -r '.datapanel_version' ./automation_conf.json)"
NODEGROUPS_NUMBER="$(jq '.nodegroups | length' ./automation_conf.json)"
# variables derivated
CONTROLPANEL_CLOUDFORMATION_NAME="cnoe-${CLUSTER_NAME}-controlpanel"
ROLE_NAME="cnoe-role-${CLUSTER_NAME}-dp"
ROLE_ARN="arn:aws:iam::${DEPLOY_AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

cd /

assignRoleToServiceAccount "${ROLE_ARN}" "${DEPLOY_AWS_REGION}"

# configure access to cluster
configureClusterAccess "${CLUSTER_NAME}" "${DEPLOY_AWS_REGION}"

ReadyNodesTest "${CLUSTER_NAME}"

if [ "$(getNumberOfReadyNodes)" -gt 0 ]; then
  connetivityTest
  kubesystemDeploymentsTest
  podReadyPercentageTest
fi