. /functions.sh


# assign new role (created in pull step) to service account
# $1 : arn of the role to assign
# $2 : region where deploy the cluster
# void
function assignRoleToServiceAccount () {
  echo "Assuming role: ${1}"
  local OLD_ROLE="$(aws sts get-caller-identity)"
  echo "Old role: ${OLD_ROLE}"
  aws sts assume-role --role-arn "${1}" --role-session-name=session-role-controlplane-$$ --region "${2}" --duration-seconds 3600
  local ROLE_ASSUMED="$(aws sts get-caller-identity)"
  echo "Role assumed: ${ROLE_ASSUMED}"
}


# configure access to cluster
# $1 : name of the cluster
# $2 : region where cluster is deployed
# void
function configureClusterAccess() {
    aws eks update-kubeconfig --region "${2}" --name "${1}"
}


# compute number of ready nodes
# string ( number of ready nodes )
function getNumberOfReadyNodes(){
  set +e
  local ACTUAL_NUMBER_NODE="$(kubectl get no --no-headers | grep -c Ready)"
  set -e
  echo "${ACTUAL_NUMBER_NODE}"
}


# get number of nodes defined in automation_conf.json file
# string ( number of desired nodes )
function getNumberOfDesiredNodes(){
  cd /shared

  mapfile -t ALL_NODE_DESIDERED < <(jq -r '.nodegroups[].cloudformation_parameters.node_desidered' ./automation_conf.json)
  local NUMBER_NODE_DESIRED=0
  for i in "${ALL_NODE_DESIDERED[@]}"; do
      (( NUMBER_NODE_DESIRED+=i ))
  done

  cd /

  echo "${NUMBER_NODE_DESIRED}"
}

# check if number of ready nodes= number of desired nodes
# $1 : cluster name
# void
function ReadyNodesTest(){
  local NUMBER_NODE_DESIRED=$(getDesiredNumberOfNodes)
  echo "NUMBER_NODE_DESIRED=${NUMBER_NODE_DESIRED}"
  local RETRIES=10
  while [ ${RETRIES} -ne 0 ]
  do
      local NODES=$(getNumberOfReadyNodes)
      if [ "${NODES}" -gt 0 ]; then
          echo "Cluster ${1} appear healty"
          break
      else
          echo "The nodes are not ready. Let's wait 60 seconds and retry"
          sleep 60
          ((RETRIES--))
      fi
  done
  if ((RETRIES == 0)); then
      >&2 colorEcho "error" "Cluster ${1} isn't healty. There are any nodes READY in this cluster."
      exit 1
  fi
}


#create simple service and one pod to test it
#void
function connetivityTest(){
  cd /
  kubectl apply -f ./test-connectivity-pod.yaml 2>&1
  local RETRIES=10
  while [ ${RETRIES} -ne 0 ]
  do
      set +e
      local CODE="$(kubectl -n "test-eks" exec "test-client" -- curl -s "nginx-service-to-test.test-eks" -w "%{http_code}\n" -o /dev/null)"
      set -e
      if [ "${CODE}" -eq 200 ]; then
          echo "Test connectivity successfully"
          break
      else
          echo "Test connectivity failed, let's wait 30 seconds and retry"
          sleep 30
          ((RETRIES--))
      fi
  done
  if ((RETRIES == 0)); then
      set +e
      kubectl delete -f test-connectivity-pod.yaml 2>&1
      set -e
      >&2 colorEcho "error" "Test connectivity failed to much times"
      exit 1
  fi
  kubectl delete -f ./test-connectivity-pod.yaml 2>&1
}

# check status of deployments in kube-system namespace
# void
function kubesystemDeploymentsTest(){
  local RESULT_VALUES=()
  set +e

  checkDeployment "cluster-autoscaler" "kube-system"
  RESULT_VALUES[0]=$?
  checkDeployment "coredns" "kube-system"
  RESULT_VALUES[1]=$?
  checkDeployment "metrics-server" "kube-system"
  RESULT_VALUES[2]=$?

  set -e

  if [[ "${RESULT_VALUES[*]}" =~ 1 ]]; then
      >&2 colorEcho "error" "At least one of these deployments is not healty: cluster-autoscaler, coredns, metrics-server"
      exit 1
  fi
  echo "Deployments check passed: billing, cluster-autoscaler, coredns, metrics-server"
}

# check percentage of pod in ready status
# void
function podReadyPercentageTest(){
    local PODS="$(kubectl get pod -A --no-headers)"
    local TOT_PODS=$(echo "${PODS}" | grep -v "Terminating\|ErrImagePull\|ImagePullBackOff" | wc -l)
    local RUNNING_PODS=$(echo "${PODS}" | grep "Completed\|Running" | wc -l)
    echo "Tot pods not Terminating not ErrImagePull not ImagePullBackOff: ${TOT_PODS}"
    echo "Ready pods: ${RUNNING_PODS}"
    echo "Percentage of ready pods: $((100*RUNNING_PODS/TOT_PODS))"
    if [ "${TOT_PODS}" -gt 500 ]; then
        PERCENTAGE=85
    elif [ "${TOT_PODS}" -lt 80 ]; then
        PERCENTAGE=60
    else
        PERCENTAGE=80
    fi

    if [ $((100*RUNNING_PODS/TOT_PODS)) -lt ${PERCENTAGE} ]; then
        >&2 colorEcho "error" "Too many pods not running. Exiting.. "
        exit 1
    else
       echo "Check ready pods OK"
    fi
}
