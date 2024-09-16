. /log.sh


# assign new role (created in pull step) to service account
# $1 : arn of the role to assign
# $2 : region where deploy the cluster
# void
function assignRoleToServiceAccount () {
  echo "Assuming role: ${1}"
  aws sts assume-role --role-arn "${1}" --role-session-name=session-role-controlplane-$$ --region "${2}" --duration-seconds 3600
  local ROLE_ASSUMED="$(aws sts get-caller-identity)"
  echo "Role assumed: ${ROLE_ASSUMED}"
}

# check if exist cluster cloud formation
# $1 : name of the cluster cloud formation to check
# $2 : region where deploy the cluster
# return : string ( "true" if CF exist, "false" otherwise )
function existClusterCF () {
  set +e
  local CF
  CF="$(aws cloudformation describe-stacks --stack-name "${1}" --region="${2}" 2>&1)"
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -ne 0 ] && [[ "${CF}" == *"Stack with id ${1} does not exist"* ]]; then
    echo "false"
  elif [ "${RETURN_CODE}" -ne 0 ]; then
    >&2 colorEcho "error" "${CF}"
    exit 1
  else
    echo "true"
  fi
}


# check if exist cluster
# $1 : name of the cluster to check
# return : string ( "true" if cluster exist, "false" otherwise )
function existCluster () {
  set +e
  local EKS_DESCRIPTION
  EKS_DESCRIPTION="$(aws eks describe-cluster --name "${1}" 2>&1)"
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -ne 0 ] && [[ "${EKS_DESCRIPTION}" == *"ResourceNotFoundException"* ]]; then
    echo "false"
  elif [ "${RETURN_CODE}" -ne 0 ]; then
    >&2 colorEcho "error" "${EKS_DESCRIPTION}"
    exit 1
  else
    echo "true"
  fi
}

# check if exist cluster
# $1 : name of the cluster to check
# $2 : region where cluster is deployed
# void
function configureClusterAccess() {
    aws eks update-kubeconfig --region "${2}" --name "${1}"
}

# deploy cloud formation
# $1 : name of the cloud formation to deploy
# $2 : region where deploy
# $3 : value to assign to Env tag
# void
function deployCF(){
    echo "Cloudformation ${1} doesn't exist.\nDeploying cloudformation ${1}"
    cd /shared
    echo "Parameters:"
    cat ./cluster_parameters.json
    aws cloudformation create-stack --stack-name "${1}" --parameters file:///shared/cluster_parameters.json --template-body "file:///shared/cloudformation_cluster.yaml" --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND" --tags "[{\"Key\":\"Env\",\"Value\":\"${3}\"}]" --region "${2}" #--role-arn "${ROLE_ARN}"
    aws cloudformation wait stack-create-complete --stack-name "${1}" --region "${2}"
    cd /
}

# update cloud formation
# $1 : name of the cloud formation to update
# $2 : region where deploy
# $3 : value to assign to Env tag
# void
function updateCF(){
    echo "Cloudformation ${1} exist.\nChecking if change are present before to update the stack ${1}"
    local CHANGE_SETS_NAME="change-set-update-$RANDOM"
    # update
    aws cloudformation create-change-set --stack-name "${1}" --change-set-name ${CHANGE_SETS_NAME} --change-set-type UPDATE --parameters file:///shared/cluster_parameters.json --template-body "file:///shared/cloudformation_cluster.yaml"  --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND" --region "${2}" #--role-arn "${ROLE_ARN}"
    set +e
    aws cloudformation wait change-set-create-complete --change-set-name ${CHANGE_SETS_NAME} --stack-name "${1}" --region "${2}"
    local RETURN_CODE=$?
    set -e
    local CHANGE_SETS="$(aws cloudformation describe-change-set --change-set-name ${CHANGE_SETS_NAME} --stack-name "${1}" --region="${2}" 2>&1)"
    if [ "${RETURN_CODE}" -ne 0 ]; then
      local CHANGE_SETS_STATUS="$(echo "${CHANGE_SETS}" | jq -r '.Status')"
      local CHANGE_SETS_REASON="$(echo "${CHANGE_SETS}" | jq -r '.StatusReason')"
      if [ "${CHANGE_SETS_STATUS}" = "FAILED" ] && [[ "${CHANGE_SETS_REASON}" == *"Submit different information to create a change set"* ]]; then
        echo "The submitted information didn't contain changes. Submit different information to create a change set."
      else
        >&2 colorEcho "error" "Changeset is in ERROR state, please check on AWS Console. Exiting..."
        exit 1
      fi
    fi

    set +e
    mapfile -t ACTIONS < <(echo "${CHANGE_SETS}" | jq -r '.Changes[].ResourceChange.Action')
    #ACTIONS=( $(echo "${CHANGE_SETS}" | jq -r '.Changes[].ResourceChange.Action' | tr "\n" " " ) )
    set -e
    if [ "${ACTIONS[*]}" != "" ] && [ "${ACTIONS[*]}" != "null" ]; then
      log info "Change sets are present, checking if are safe"
      if [[ "${ACTIONS[*]}" == *"Remove"* ]] || [[ "${ACTIONS[*]}" == *"Delete"* ]]; then
        >&2 colorEcho "error" "Attention, a resource could be deleted, the update will be interrupted!\nPlease, check you params!\nExiting ..."
        exit 1
      fi
      echo "All change sets are safe!"
    else
      echo "Change sets are NOT present"
    fi

    echo "Updating cloudformation ${1}..."
    aws cloudformation delete-change-set --change-set-name ${CHANGE_SETS_NAME} --stack-name "${1}" --region "${2}"

    #Print logs continuously to avoid Bamboo hand during large CF deployments
    export cf_deploy_flag_file=$(mktemp)
    export cf_name="${1}"
    python /waiting_logs.py &  #Start waiting logs

    set +e
    update_output=$(aws cloudformation update-stack --stack-name "${1}" --parameters file:///shared/cluster_parameters.json --template-body "file:///shared/cloudformation_cluster.yaml" --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND" --tags "[{\"Key\":\"Env\",\"Value\":\"${3}\"}]" --region "${2}" ) #--role-arn "${ROLE_ARN}" 2>&1)
    status=$?
    echo "${update_output}"
    set -e

      init_timestamp=""
      if [ $status -ne 0 ] ; then
        if [[ $update_output == *"ValidationError"* && $update_output == *"No updates"* ]] ; then
          echo "Finished create/update - no updates to be performed"
        elif [[ $update_output == *"ValidationError"* ]]; then
          >&2 colorEcho "error" "Cloudformation can not be updated due to ValidationError. Exiting..."
          rm -f $cf_deploy_flag_file
          exit 1
        else
          set +e
          wait_response=$(aws cloudformation wait stack-update-complete --stack-name "${1}" --region "${2}" 2>&1)
          >&2 aws cloudformation describe-stack-events --stack "${1}" --query "StackEvents[?Timestamp > \`${init_timestamp}\`] | sort_by(@, &Timestamp)" --max-items 50 --region "${2}" | jq -r '.[] | .Timestamp + " - " + .ResourceType + " - " + .ResourceStatus + " - " + .LogicalResourceId + " - " + .ResourceStatusReason'
          set -e
          rm -f $cf_deploy_flag_file
          exit 1
        fi
      else
        set +e
        wait_response=$(aws cloudformation wait stack-update-complete --stack-name "${1}" --region "${2}" 2>&1)
        aws cloudformation describe-stack-events --stack "${1}" --query "StackEvents[?Timestamp > \`${init_timestamp}\`] | sort_by(@, &Timestamp)" --max-items 50 --region "${2}" | jq -r '.[] | .Timestamp + " - " + .ResourceType + " - " + .ResourceStatus + " - " + .LogicalResourceId + " - " + .ResourceStatusReason'
        set -e
        if [[ "${wait_response}" == *"failed"* ]]; then
          >&2 colorEcho "error" "Cloudformation is in failed state. Please check logs in console."
          exit 1
        fi
        rm -f $cf_deploy_flag_file
      fi
}