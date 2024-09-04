#!/bin/bash -e

# def utility functions
. /log.sh
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
CLOUD_FORMATION_NAME = "cnoe-${CLUSTER_NAME}-nodegroup"
ROLE_NAME = "cnoe-role-${CLUSTER_NAME}-cp"
STACK_NAME = "StackPullControlplane-${CLUSTER_NAME}"


DEBUG=1
log info "DEBUG_ACTIVE=${DEBUG_ACTIVE}"

#STARTING UPDATE PLAN 
log debug "CONTAINER VERSION: $(cat /automation_conf.json | jq -r '.release_version')"

log info "sed on cloudformation_for_role.yaml"
sed -i -e 's/__ROLE_NAME__/'"$ROLE_NAME"'/g' /cloudformation_for_role.yaml
sed -i -e 's/__DEPLOY_AWS_ACCOUNT_ID__/'"$DEPLOY_AWS_ACCOUNT_ID"'/g' /cloudformation_for_role.yaml
sed -i -e 's/__DEPLOY_AWS_REGION__/'"$DEPLOY_AWS_REGION"'/g' /cloudformation_for_role.yaml
sed -i -e 's/__CLOUDFORMATION_NAME__/'"$CLOUDFORMATION_NAME"'/g' /cloudformation_for_role.yaml
sed -i -e 's/__CLUSTER_NAME__/'"$CLUSTER_NAME"'/g' /cloudformation_for_role.yaml

cat /cloudformation_for_role.yaml

log debug "\nStarting role: $(aws sts get-caller-identity --profile ${MASTER_PROFILE})"

aws cloudformation deploy --no-fail-on-empty-changeset --template-file /cloudformation_for_role.yaml --stack-name "${STACK_NAME}" --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND"

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
#crypt
