#!/bin/bash -e

. /log.sh
. /functions.sh

set -e

cd /shared

cat variables.json

# assign values to env variables
CLUSTER_NAME="$(jq -r '.clusterName' variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.awsAccountId' variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.env' variables.json)"
BE_SUBNET_IDS_PARAMETER="$(jq -r '.beSubnetIds' ./variables.json)"
VPC_ID_PARAMETER="$(jq -r '.vpcId' ./variables.json)"
EKS_VERSION="$(jq -r '.eksVersion' variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIds' ./variables.json)"
# derivated or fixed
VERSION="$(jq -r '.eksVersion' variables.json)"
ROLE_TAG_PARAMETER="application"
DATE=$(date +"%d-%m-%Y %H:%M:%S")
COMMIT="test"
CLOUD_FORMATION_NAME="cnoe-${CLUSTER_NAME}-nodegroup"
ROLE_NAME="cnoe-role-${CLUSTER_NAME}-dp"
STACK_NAME="StackPullDataplane-${CLUSTER_NAME}"