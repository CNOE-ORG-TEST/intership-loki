#!/bin/bash -e

. /subSteps.sh

set -e

downloadVariablesFiles

cd /shared
CLUSTER_NAME="$(jq -r '.clusterName' ./variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' ./variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' ./variables.json)"
ENVIRONMENT="$(jq -r '.env' ./variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.env' ./variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIds' ./variables.json)"
VPC_ID_PARAMETER="$(jq -r '.vpcId' ./variables.json)"
# automation_conf variables
INFRPANEL_VERSION="$(jq -r '.infrpanel_version' ./automation_conf.json)"

# manage role
STACK_NAME="StackPullInfrplane-${CLUSTER_NAME}"
ROLE_NAME="cnoe-role-${CLUSTER_NAME}-ip"

echo "Infrpanel version: ${INFRPANEL_VERSION}"

if [ "$(existRoleCF "${STACK_NAME}" "${DEPLOY_AWS_REGION}")" = "false" ]; then
  echo "sed on cloudformation_for_role.yaml"
  sed -i -e 's/__DEPLOY_AWS_ACCOUNT_ID__/'"$DEPLOY_AWS_ACCOUNT_ID"'/g' /cloudformation_for_role.yaml
  sed -i -e 's/__DEPLOY_AWS_REGION__/'"$DEPLOY_AWS_REGION"'/g' /cloudformation_for_role.yaml
  sed -i -e 's/__CLUSTER_NAME__/'"$CLUSTER_NAME"'/g' /cloudformation_for_role.yaml
  sed -i -e 's/__ROLE_NAME__/'"$ROLE_NAME"'/g' /cloudformation_for_role.yaml

  echo "Deploying role cloudformation..."
  deployRoleCF "${STACK_NAME}"
  echo "Deployed role cloudformation"
else
  echo "Role ${ROLE_NAME} already exist"
fi

configureClusterAccess "${CLUSTER_NAME}" "${DEPLOY_AWS_REGION}" "${DEPLOY_AWS_ACCOUNT_ID}"

SA_NAME="${CLUSTER_NAME,,}-${ENVIRONMENT,,}-role-mk8s-infrpanel"

createServiceAccount ${SA_NAME}
createNamespaces ${INFRPANEL_VERSION}
setupRoleBindings ${SA_NAME}