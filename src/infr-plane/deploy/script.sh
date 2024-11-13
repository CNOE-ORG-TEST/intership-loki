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
ENI_SUBNETS="$(jq -r '.beSubnetIds' ./variables.json)"
# automation_conf variables
INFRPANEL_VERSION="$(jq -r '.infrpanel_version' ./automation_conf.json)"

echo "Infrpanel version: ${INFRPANEL_VERSION_TAG}"

configureClusterAccess "${CLUSTER_NAME}" "${DEPLOY_AWS_REGION}" "${DEPLOY_AWS_ACCOUNT_ID}"
downloadHelmFiles "${INFRPANEL_VERSION}"
setHelmVariables "${CLUSTER_NAME}" "${SECURITY_GROUP_IDS_PARAMETER}" "${ENI_SUBNETS}" "${DEPLOY_AWS_REGION}"
HELM_VALUE_PATH="/helm/values/${ENVIRONMENT}.yaml"
helmValuesFileValidation ${HELM_VALUE_PATH}
LABEL="thor=infrpanel"
compileHelmValuesFile ${HELM_VALUE_PATH}
deployHelm "${CLUSTER_NAME}" "${HELM_VALUE_PATH}" "${LABEL}"