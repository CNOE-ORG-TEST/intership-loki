#!/bin/bash -e

# def utility functions
#. /log.sh
. /functions.sh

# if some script return error the script will kill
set -e

# clone variables config repo
cd /shared
downloadVariablesFiles

# setup deploy_and_release_variables.json
#TIMESTAMP_BUILD="{\"timestamp_build\": \"$(echo $(date +%Y-%m-%dT%H-%M-%S_%s))\"}"
#echo "${TIMESTAMP_BUILD} $(cat working_path/automation_conf.json)" | jq -s add > deploy_and_release_variables.json

# assign values to env variables
CLUSTER_NAME="$(jq -r '.clusterName' variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.env' variables.json)"
BE_SUBNET_IDS_PARAMETER="$(jq -r '.beSubnetIds' ./variables.json)"
VPC_ID_PARAMETER="$(jq -r '.vpcId' ./variables.json)"
EKS_VERSION="$(jq -r '.controlpanel_version' automation_conf.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIds' ./variables.json)"
# derivated or fixed
VERSION="$(jq -r '.eksVersion' variables.json)"
ROLE_TAG_PARAMETER="application"
DATE=$(date +"%d-%m-%Y %H:%M:%S")
COMMIT="test"
CLOUD_FORMATION_NAME="cnoe-${CLUSTER_NAME}-nodegroup"
ROLE_NAME="cnoe-role-${CLUSTER_NAME}-cp"
STACK_NAME="StackPullControlplane-${CLUSTER_NAME}"


#DEBUG=1
#echo "DEBUG_ACTIVE=${DEBUG_ACTIVE}"

if [ "$(existRoleCF "${STACK_NAME}" "${DEPLOY_AWS_REGION}")" = "false" ]; then
    echo "CONTAINER VERSION: $(cat /automation_conf.json | jq -r '.release_version')"

    echo "sed on cloudformation_for_role.yaml"
    sed -i -e 's/__ROLE_NAME__/'"$ROLE_NAME"'/g' /cloudformation_for_role.yaml
    sed -i -e 's/__DEPLOY_AWS_ACCOUNT_ID__/'"$DEPLOY_AWS_ACCOUNT_ID"'/g' /cloudformation_for_role.yaml
    sed -i -e 's/__DEPLOY_AWS_REGION__/'"$DEPLOY_AWS_REGION"'/g' /cloudformation_for_role.yaml
    sed -i -e 's/__CLOUDFORMATION_NAME__/'"$CLOUDFORMATION_NAME"'/g' /cloudformation_for_role.yaml
    sed -i -e 's/__CLUSTER_NAME__/'"$CLUSTER_NAME"'/g' /cloudformation_for_role.yaml

    cat /cloudformation_for_role.yaml

    echo "\nStarting role: $(aws sts get-caller-identity )"

    aws cloudformation deploy --no-fail-on-empty-changeset --template-file /cloudformation_for_role.yaml --stack-name "${STACK_NAME}" --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND"
else
    echo "Role ${ROLE_NAME} already exist"
fi

echo "Start compiling cloudformation_cluster.yaml with DATA = ${DATA}, VERSION = ${VERSION}, COMMIT = ${COMMIT}"
cd /shared
aws s3 cp s3://cnoe-loki-manifest-templates/cloudformation_cluster.yaml /shared/cloudformation_cluster.yaml
aws s3 cp s3://cnoe-loki-manifest-templates/cluster_parameters.json /shared/cluster_parameters.json

#sed -i -e 's/__ROLE_NAME__/'"$ROLE_NAME"'/g' ./cloudformation_cluster.yaml
#sed -i -e 's/__DEPLOY_AWS_ACCOUNT_ID__/'"$DEPLOY_AWS_ACCOUNT_ID"'/g' ./cloudformation_cluster.yaml
#sed -i -e 's/__DEPLOY_AWS_REGION__/'"$DEPLOY_AWS_REGION"'/g' ./cloudformation_cluster.yaml
#sed -i -e 's/__CLOUDFORMATION_NAME__/'"$CLOUDFORMATION_NAME"'/g' ./cloudformation_cluster.yaml
#sed -i -e 's/__CLUSTER_NAME__/'"$CLUSTER_NAME"'/g' ./cloudformation_cluster.yaml
#sed -i -e 's/__EKS_VERSION__/'"$EKS_VERSION"'/g' ./cloudformation_cluster.yaml
sed -i -e 's/__VERSION__/'"$VERSION"'/g' ./cloudformation_cluster.yaml
sed -i -e 's/__DATE__/'"$DATE"'/g' ./cloudformation_cluster.yaml
sed -i -e 's/__COMMIT__/'"$COMMIT"'/g' ./cloudformation_cluster.yaml


sed -i -e "s?__ENVIRONMENT_TAG_PARAMETER__?${ENVIRONMENT_TAG_PARAMETER}?g" /shared/cluster_parameters.json
sed -i -e "s?__ROLE_TAG_PARAMETER__?${ROLE_TAG_PARAMETER}?g" /shared/cluster_parameters.json
sed -i -e "s?__CLUSTERNAME_PARAMETER__?${CLUSTER_NAME}?g" /shared/cluster_parameters.json
sed -i -e "s?__CLUSTERVERSION_PARAMETER__?${EKS_VERSION}?g" /shared/cluster_parameters.json
sed -i -e "s?__SUBNETIDS_PARAMETER__?${BE_SUBNET_IDS_PARAMETER}?g" /shared/cluster_parameters.json
sed -i -e "s?__VPCID_PARAMETER__?${VPC_ID_PARAMETER}?g" /shared/cluster_parameters.json
sed -i -e "s?__SECURITYGROUPIDS_PARAMETER__?${SECURITY_GROUP_IDS_PARAMETER}?g" /shared/cluster_parameters.json

cd /shared

echo "Show Compiled cloudformation_cluster.yaml file: \n"
cat ./cloudformation_cluster.yaml

echo "\n\n\n"
echo "Show Compiled cluster_parameters.json file"
cat /shared/cluster_parameters.json


#aws_infrastructure_configuration.json
