#!/bin/bash -e

. /subSteps.sh

set -e

cd /shared

# variables.json variables
CLUSTER_NAME="$(jq -r '.clusterName' ./variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' ./variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' ./variables.json)"
ENVIRONMENT="$(jq -r '.env' ./variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.env' ./variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIds' ./variables.json | sed 's/ //g')"
VPC_ID_PARAMETER="$(jq -r '.vpcId' ./variables.json)"
#automation_conf.json
INFRPANEL_VERSION="$(jq -r '.infrpanel_version' ./automation_conf.json)"
ENABLE_CLUSTER_AUTOSCALER="$(jq -r '.infr_components.cluster_autoscaler.enabled' ./automation_conf.json)"
ENABLE_METRIC_SERVER="$(jq -r '.infr_components.metric-server.enabled' ./automation_conf.json)"
echo "Infrpanel version: ${INFRPANEL_VERSION}"

cd /

# configure access to cluster
configureClusterAccess "${CLUSTER_NAME}" "${DEPLOY_AWS_REGION}" "${DEPLOY_AWS_ACCOUNT_ID}"

#compute number of ready nodes
ACTUAL_NUMBER_NODE=$(getNumberOfReadyNodes)
echo "There are ${ACTUAL_NUMBER_NODE} nodes in the target cluster with secret."

if [ "${ACTUAL_NUMBER_NODE}" -gt 0 ]; then
  connetivityTest
  kubesystemDeploymentsTest "${ENABLE_CLUSTER_AUTOSCALER}" "${ENABLE_METRIC_SERVER}"
  podReadyPercentageTest
fi