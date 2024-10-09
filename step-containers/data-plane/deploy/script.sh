#!/bin/bash -e

set -e

. /subSteps.sh

showVariables

cd /shared
ls -la

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

if [ "$(existCF "${CONTROLPANEL_CLOUDFORMATION_NAME}" "${DEPLOY_AWS_REGION}")" = "false" ]; then
  >&2 colorEcho "error" "KO: Cloudformation ${CONTROLPANEL_CLOUDFORMATION_NAME} doesn't exist."
  >&2 colorEcho "red" "Please check your params!"
  exit 1
elif [ "$(existCluster "${CLUSTER_NAME}")" = "false" ]; then
  >&2 colorEcho "error" "Cloudformation ${CONTROLPANEL_CLOUDFORMATION_NAME} exist but cluster ${CLUSTER_NAME} don't exists"
  >&2 colorEcho "red" "Please check your parameters! if all parameters it's ok delete ${CONTROLPANEL_CLOUDFORMATION_NAME} cloudformation end recreate all (in this way you will lose all in the cluster)"
  exit 1
else
  configureClusterAccess "${CLUSTER_NAME}" "${DEPLOY_AWS_REGION}" "${DEPLOY_AWS_ACCOUNT_ID}"
  retrieveEksParameters "${CLUSTER_NAME}"
  for i in $(seq 0 $((NODEGROUPS_NUMBER-1)));
  do
    DATAPANEL_CLOUDFORMATION_NAME="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].datapanel_cloudformation_name' /shared/automation_conf.json)"
    if [ "$(needToUpdateGroupNode ${i})" = "true" ]; then
        createOrUpdateGroupNode ${DATAPANEL_CLOUDFORMATION_NAME} ${i}
    else
      echo "The cloudformation \"${DATAPANEL_CLOUDFORMATION_NAME}\" won't be updated. Update flag is false.\nSkip to the next cloudformation."
    fi
  done
fi