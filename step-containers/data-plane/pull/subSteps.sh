. /log.sh
. /functions.sh

# download variables.json and automation_conf.json
# void
function downloadVariablesFiles() {
  cd /shared
  curl -H "Authorization: Bearer ${GITHUB_TOKEN}" -L "https://raw.githubusercontent.com/${GITHUB_REPO}/main/variables.json" > /shared/variables.json
  curl -H "Authorization: Bearer ${GITHUB_TOKEN}" -L "https://raw.githubusercontent.com/${GITHUB_REPO}/main/automation_conf.json" > /shared/automation_conf.json
  echo "variables.json parameters:"
  cat variables.json

  echo "automation_conf.json parameters:"
  cat automation_conf.json
  cd /
}

# compute ALL_CLOUDFORMATION_NODEGROUPS and ALL_CLOUDFORMATION_NODEINSTANCEROLES variables
# $1 : number of nodegroups
# void
function computeNodesRolesNames(){
  cd /shared
  for i in $(seq 0 $((${1}-1)));
  do
    local DATAPANEL_CLOUDFORMATION_NAME="$(jq -r --arg i "${i}" '.nodegroups[$i|tonumber].datapanel_cloudformation_name' ./automation_conf.json)"
    ALL_CLOUDFORMATION_NODEGROUPS+="            - \"arn:aws:cloudformation:__DEPLOY_AWS_REGION__:__DEPLOY_AWS_ACCOUNT_ID__:stack/${DATAPANEL_CLOUDFORMATION_NAME}/*\"\n"
    local RESOURCE_NAME="${DATAPANEL_CLOUDFORMATION_NAME:0:33}" # cat name with max length of 33
    if [ "${RESOURCE_NAME: -1}" = "-" ]; then
      RESOURCE_NAME="${DATAPANEL_CLOUDFORMATION_NAME:0:32}"
    fi
    ALL_CLOUDFORMATION_NODEINSTANCEROLES+="            - \"arn:aws:iam::__DEPLOY_AWS_ACCOUNT_ID__:role/${RESOURCE_NAME}*-NodeInstanceRole-*\"\n"
  done
  cd /
  local CONTROL_CLOUDFORMATION_NAME="cnoe-${CLUSTER_NAME}-controlpanel"
  ALL_CLOUDFORMATION_NODEGROUPS+="            - \"arn:aws:cloudformation:__DEPLOY_AWS_REGION__:__DEPLOY_AWS_ACCOUNT_ID__:stack/${CONTROL_CLOUDFORMATION_NAME}/*\"\n"
}


#deploy CF role
# $1 : Stack name
#void
function deployRoleCF(){
  aws cloudformation deploy --no-fail-on-empty-changeset --template-file /cloudformation_for_role.yaml --stack-name "${1}" --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND"
}

# download cloudformation_nodegroups.yaml file
# void
function downloadCFFiles(){
  aws s3 cp s3://cnoe-loki-manifest-templates/cloudformation_nodegroups.yaml /shared/cloudformation_nodegroups.yaml
  aws s3 cp s3://cnoe-loki-manifest-templates/cloudformation_nodegroups.yaml /shared/nodegroups_parameter.json
}

function showCompiledCFFiles() {
    cd /shared

    echo "Show Compiled cloudformation_cluster.yaml file: \n"
    cat ./cloudformation_nodegroups.yaml

    #echo "\n\n\n"
    #echo "Show Compiled cluster_parameters.json file"
    #cat /shared/nodes_groups_parameters.json
    cd /
}


