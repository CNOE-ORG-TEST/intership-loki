. /log.sh
. /functions.sh

# check if infrplane version is compatible with controlplane version
# $1 : name of the cluster to check
# $2 : infrplane version to deploy
# void
function checkInfrpanelVsControlpanel () {
  echo "Checking infrpanel version accross controlpanel version."
  local CONTROLPANEL_VERSION="$(aws eks describe-cluster --name "${1}" | jq -r '.cluster.version')"
  echo "infrpanel version = ${2}"
  echo "controlpanel version = ${CONTROLPANEL_VERSION}"
  local INFRPANEL_NEXT_VERSION=$( (echo "$CONTROLPANEL_VERSION + 0.01") | bc )
  local INFRPANEL_PERMITTED_VERSIONS=( "${CONTROLPANEL_VERSION}" "${INFRPANEL_NEXT_VERSION}" )
  if [[ ! " ${INFRPANEL_PERMITTED_VERSIONS[*]} " =~ ${2} ]]; then
    >&2 colorEcho "error" "${2} infrpanel version NOT permitted! Please check your controlpanel version.\nExiting..."
    exit 1
  else
    echo "controlpanel version and infrpanel version are compatible"
  fi
}


# check if infrplane version is compatible with dataplane version
# $1 : name of the cluster to check
# $2 : infrplane version to deploy
# $3 : region where deploy
# void
function checkInfrpanelVsDatapanel () {
    #CHECK CONTROL PANEL VERSION WITH CURRENT DATA PANEL VERSIONS
    echo "Checking infrpanel version accross datapanel versions"
    if [ "$(repoExist "${GITHUB_ORG}/${1}Dataplane" "${GITHUB_TOKEN}")" = "true" ]; then
        downloadAutomationConfJson "${GITHUB_ORG}/${1}Dataplane" "${GITHUB_TOKEN}"
        echo "The datapanel exits, checking the versions"
        mapfile -t ALL_NODEGROUPS_NAMES_CF< <(jq -r '.nodegroups[].datapanel_cloudformation_name' "automation_conf_dp.json")
        for NODEGROUP_NAME_CF in "${ALL_NODEGROUPS_NAMES_CF[@]}"; do
          set +e
          local INFO_NODEGROUP_NAME_CF="$(aws cloudformation describe-stacks --stack-name "${NODEGROUP_NAME_CF}" --region="${3}" 2>&1)"
          local RETURN_CODE=$?
          set -e

          if [ "${RETURN_CODE}" -eq 0 ] && [[ "${INFO_NODEGROUP_NAME_CF}" != *"Stack with id ${INFO_NODEGROUP_NAME_CF} does not exist"* ]]; then
            local NODEGROUP_VERSION="$(echo "${INFO_NODEGROUP_NAME_CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeImageIdSSMParam") | .ParameterValue' | cut -d "/" -f6 )"
            echo "Name stack datapanel ${NODEGROUP_NAME_CF} has the version: ${NODEGROUP_VERSION}"
            local INFRPANEL_NEXT_VERSION=$( (echo "$NODEGROUP_VERSION + 0.01") | bc )
            local INFRPANEL_PERMITTED_VERSIONS=("${NODEGROUP_VERSION}" "${INFRPANEL_NEXT_VERSION}")
            if [[ ! " ${INFRPANEL_PERMITTED_VERSIONS[*]} " =~ ${2} ]]; then
              >&2 colorEcho "error" "${2} infrpanel version NOT permitted! Please check your datapanel version.\nExiting..."
              exit 1
            fi
          else
            echo "Stack of datapanel with name ${NODEGROUP_NAME_CF} doesn't exist"
          fi
        done
    else
      >&2 colorEcho "error" "dataplane repository doesn't exist.\nExiting..."
      exit 1
    fi
}


# configure access to cluster
# $1 : name of the cluster
# $2 : region where cluster is deployed
# $3 : AWS account ID
# void
function configureClusterAccess() {
    echo "Configuring access to cluster ${1}..."
    aws eks update-kubeconfig --region "${2}" --name "${1}"
    echo "Configured access to cluster ${1}"
    echo "Setting current context to arn:aws:eks:${2}:${3}:cluster/${1}..."
    kubectl config use-context "arn:aws:eks:${2}:${3}:cluster/${1}"
    if [ "$(kubectl config current-context)" != "arn:aws:eks:${2}:${3}:cluster/${1}" ]; then
      >&2 colorEcho "error" "Context not set correctly"
      exit 1
    else
      echo "Context set correctly"
    fi
}

# check all plugins parameters (if you have to add some plugin add here and in checkPlugin.sh file the code)
# $1 : cluster name
# void
function checkPlugins () {
  checkCoreDNS "${CLUSTER_NAME}"
  checkAutoscaler "${CLUSTER_NAME}"

}

# TODO function genereteKubeconfigSA ()