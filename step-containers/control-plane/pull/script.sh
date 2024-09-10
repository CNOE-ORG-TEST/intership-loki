#!/bin/bash -e

# def utility functions
#. /log.sh
. /functions.sh

# if some script return error the script will kill
set -e

# clone variables config repo
cd /shared
curl -H "Authorization: Bearer ${GITHUB_TOKEN}" -L "https://raw.githubusercontent.com/${GITHUB_REPO}/main/variables.json" > variables.json
cat variables.json

# setup deploy_and_release_variables.json
#TIMESTAMP_BUILD="{\"timestamp_build\": \"$(echo $(date +%Y-%m-%dT%H-%M-%S_%s))\"}"
#echo "${TIMESTAMP_BUILD} $(cat working_path/automation_conf.json)" | jq -s add > deploy_and_release_variables.json

# assign values to env variables
CLUSTER_NAME="$(jq -r '.clusterName' variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' variables.json)"
EKS_VERSION="$(jq -r '.eksVersion' variables.json)"
VERSION="$(jq -r '.eksVersion' variables.json)"
DATE="{\"timestamp_build\": \"$(echo $(date +%Y-%m-%dT%H-%M-%S_%s))\"}"
COMMIT="test"
CLOUD_FORMATION_NAME="cnoe-${CLUSTER_NAME}-nodegroup"
ROLE_NAME="cnoe-role-${CLUSTER_NAME}-cp"
STACK_NAME="StackPullControlplane-${CLUSTER_NAME}"


#DEBUG=1
#echo "DEBUG_ACTIVE=${DEBUG_ACTIVE}"

if [  "$(existRoleCF "${ROLE_NAME}"  "${DEPLOY_AWS_REGION}")" = "false"]; then
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
aws s3 cp s3://cnoe-loki-manifest-templates/cloudformation_cluster.yaml ./cloudformation_cluster.yaml

#sed -i -e 's/__ROLE_NAME__/'"$ROLE_NAME"'/g' ./cloudformation_cluster.yaml
#sed -i -e 's/__DEPLOY_AWS_ACCOUNT_ID__/'"$DEPLOY_AWS_ACCOUNT_ID"'/g' ./cloudformation_cluster.yaml
#sed -i -e 's/__DEPLOY_AWS_REGION__/'"$DEPLOY_AWS_REGION"'/g' ./cloudformation_cluster.yaml
#sed -i -e 's/__CLOUDFORMATION_NAME__/'"$CLOUDFORMATION_NAME"'/g' ./cloudformation_cluster.yaml
#sed -i -e 's/__CLUSTER_NAME__/'"$CLUSTER_NAME"'/g' ./cloudformation_cluster.yaml
#sed -i -e 's/__EKS_VERSION__/'"$EKS_VERSION"'/g' ./cloudformation_cluster.yaml
sed -i -e 's/__VERSION__/'"$VERSION"'/g' ./cloudformation_cluster.yaml
sed -i -e 's/__DATE__/'"$DATE"'/g' ./cloudformation_cluster.yaml
sed -i -e 's/__COMMIT__/'"$COMMIT"'/g' ./cloudformation_cluster.yaml

# TODO compile json
# sed -i -e "s?__CUSTOMER_TAG_PARAMETER__?${CUSTOMER_TAG_PARAMETER}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__ENVIRONMENT_TAG_PARAMETER__?${ENVIRONMENT_TAG_PARAMETER}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__GIASID_NAME_TAG_PARAMETER__?${GIAS_NAME_TAG_PARAMETER//&/\\&}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__GIASID_TAG_PARAMETER__?${GIAS_ID_TAG_PARAMETER}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__GIASIDNODOT_TAG_PARAMETER__?${GIAS_ID_NOT_DOT_TAG_PARAMETER}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__PROJECT_TAG_PARAMETER__?${PROJECT_TAG_PARAMETER}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__RUNNING_TAG_PARAMETER__?${RUNNING_TAG_PARAMETER}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__ROLE_TAG_PARAMETER__?${ROLE_TAG_PARAMETER}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__BACKUP_PARAMETER__?${BACKUP_PARAMETER}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__CLUSTERNAME_PARAMETER__?${CLUSTER_NAME}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__SUBNETIDS_PARAMETER__?${BE_SUBNET_IDS_PARAMETER}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__VPCID_PARAMETER__?${VPC_ID_PARAMETER}?g" ./aws_infrastructure_configuration.json
# sed -i -e "s?__SECURITYGROUPIDS_PARAMETER__?${SECURITY_GROUP_IDS_PARAMETER}?g" ./aws_infrastructure_configuration.json


echo "cloudformation_cluster.yaml compiled: \n"
cat ./cloudformation_cluster.yaml
