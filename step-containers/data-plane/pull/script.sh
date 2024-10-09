#!/bin/bash -e

. /subSteps.sh

set -e

downloadVariablesFiles

# assign values to env variables
CLUSTER_NAME="$(jq -r '.clusterName' /shared/variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' /shared/variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' /shared/variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.env' /shared/variables.json)"
BE_SUBNET_IDS_PARAMETER="$(jq -r '.beSubnetIds' /shared/variables.json)"
VPC_ID_PARAMETER="$(jq -r '.vpcId' /shared/variables.json)"
EKS_VERSION="$(jq -r '.eksVersion' /shared/variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIds' /shared/variables.json)"
# derivated or fixed
VERSION="$(jq -r '.eksVersion' /shared/variables.json)"
#ROLE_TAG_PARAMETER="application"
DATE=$(date +"%d-%m-%Y %H:%M:%S")
COMMIT="test"
CLOUD_FORMATION_NAME="cnoe-${CLUSTER_NAME}-nodegroup"
ROLE_NAME="cnoe-role-${CLUSTER_NAME}-dp"
STACK_NAME="StackPullDataplane-${CLUSTER_NAME}"
DATAPANEL_VERSION="$(jq -r '.datapanel_version' /shared/automation_conf.json)"
NODEGROUPS_NUMBER="$(jq '.nodegroups | length' /shared/automation_conf.json)"

echo "There are ${NODEGROUPS_NUMBER} of NodeGroups in this datapanel."
echo "Datapanel version: ${DATAPANEL_VERSION}"

#STARTING UPDATE PLAN
#echo "CONTAINER VERSION: $(cat /shared/automation_conf.json | jq -r '.release_version')"

if [ "$(existRoleCF "${STACK_NAME}" "${DEPLOY_AWS_REGION}")" = "false" ]; then
  # compute ALL_CLOUDFORMATION_NODEGROUPS and ALL_CLOUDFORMATION_NODEINSTANCEROLES variables
  computeNodesRolesNames
  echo ${ALL_CLOUDFORMATION_NODEGROUPS}
  echo "ALL_CLOUDFORMATION_NODEINSTANCEROLES=${ALL_CLOUDFORMATION_NODEINSTANCEROLES}"

  echo "sed on cloudformation_for_role.yaml"

  sed -i -e 's|__ALL_CLOUDFORMATION_NODEGROUPS__|'"$ALL_CLOUDFORMATION_NODEGROUPS"'|g' /cloudformation_for_role.yaml
  sed -i -e 's|__ALL_CLOUDFORMATION_NODEINSTANCEROLES__|'"$ALL_CLOUDFORMATION_NODEINSTANCEROLES"'|g' /cloudformation_for_role.yaml
  sed -i -e 's/__ROLE_NAME__/'"$ROLE_NAME"'/g' /cloudformation_for_role.yaml
  sed -i -e 's/__DEPLOY_AWS_ACCOUNT_ID__/'"$DEPLOY_AWS_ACCOUNT_ID"'/g' /cloudformation_for_role.yaml
  sed -i -e 's/__DEPLOY_AWS_REGION__/'"$DEPLOY_AWS_REGION"'/g' /cloudformation_for_role.yaml
  sed -i -e 's/__ENVIRONMENT_TAG_PARAMETER__/'"$ENVIRONMENT_TAG_PARAMETER"'/g' /cloudformation_for_role.yaml
  sed -i -e 's/__CLUSTER_NAME__/'"$CLUSTER_NAME"'/g' /cloudformation_for_role.yaml

  echo "Deploying role cloudformation..."
  deployRoleCF "${STACK_NAME}"
  echo "Deployed role cloudformation"
else
  echo "Role ${ROLE_NAME} already exist"
fi

downloadCFFiles

# set variables
VERSION="$(jq -r '.eksVersion' /shared/variables.json)"
DATE=$(date +"%d-%m-%Y %H:%M:%S")
COMMIT="test"

cd /shared
sed -i -e 's/__VERSION__/'"$VERSION"'/g' ./cloudformation_nodegroups.yaml
sed -i -e 's/__DATE__/'"$DATE"'/g' ./cloudformation_nodegroups.yaml
sed -i -e 's/__COMMIT__/'"$COMMIT"'/g' ./cloudformation_nodegroups.yaml
cd /

showCompiledCFFiles