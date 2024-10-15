#!/bin/bash -e

. /subSteps.sh

set -e

cd /shared

echo "variables file:"
cat ./variables.json

echo "automation_conf file:"
cat ./automation_conf.json

CLUSTER_NAME="$(jq -r '.clusterName' ./variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' ./variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' ./variables.json)"
ENVIRONMENT="$(jq -r '.env' ./variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.env' ./variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIds' ./variables.json)"
VPC_ID_PARAMETER="$(jq -r '.vpcId' ./variables.json)"
# automation_conf variables
INFRPANEL_VERSION="$(jq -r '.infrpanel_version' ./automation_conf.json)"

echo "Infrpanel version: ${INFRPANEL_VERSION_TAG}"

configureClusterAccess "${CLUSTER_NAME}" "${DEPLOY_AWS_REGION}" "${DEPLOY_AWS_ACCOUNT_ID}"

checkInfrpanelVsControlpanel "${CLUSTER_NAME}" "${INFRPANEL_VERSION}"
checkInfrpanelVsDatapanel "${CLUSTER_NAME}" "${INFRPANEL_VERSION}" "${DEPLOY_AWS_REGION}"

checkPlugins "${CLUSTER_NAME}"



cd /
