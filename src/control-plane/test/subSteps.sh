. /functions.sh


# assign new role (created in pull step) to service account
# $1 : arn of the role to assign
# $2 : region where deploy the cluster
# void
function assignRoleToServiceAccount() {
  echo "Assuming role: ${1}"
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


#create simple service and one pod to test it
#void
function connetivityTest(){
  cd /
  kubectl apply -f ./test-connectivity-pod.yaml 2>&1
  RETRIES=10
  while [ ${RETRIES} -ne 0 ]
  do
      set +e
      CODE="$(kubectl -n "test-eks" exec "test-client" -- curl -s "nginx-service-to-test.test-eks" -w "%{http_code}\n" -o /dev/null)"
      set -e
      if [[ "${CODE}" == *"200"* ]]; then
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
  RESULT_VALUES=()
  set +e

  NUMBER_CHECKED=0
  DEPLOYMENT_TO_CHECK="coredns"
  checkDeployment "coredns" "kube-system"
  RESULT_VALUES[0]=$?

  # check autoscaler
  if [ "$(checkEnablePlugin "autoscaler")" = "true" ]; then
    DEPLOYMENT_TO_CHECK+=", cluster-autoscaler"
    NUMBER_CHECKED=$((NUMBER_CHECKED + 1))
    checkDeployment "cluster-autoscaler" "kube-system"
    RESULT_VALUES[NUMBER_CHECKED]=$?
  fi
  # check metrics-server
  if [ "$(checkEnablePlugin "metrics")" = "true" ]; then
    DEPLOYMENT_TO_CHECK+=", metrics-server"
    NUMBER_CHECKED=$((NUMBER_CHECKED + 1))
    checkDeployment "metrics-server" "kube-system"
    RESULT_VALUES[NUMBER_CHECKED]=$?
  fi

  set -e

  if [[ "${RESULT_VALUES[*]}" =~ 1 ]]; then
      >&2 colorEcho "error" "At least one of these deployments is not healty: ${DEPLOYMENT_TO_CHECK}"
      exit 1
  fi
  echo "Deployments check passed: ${DEPLOYMENT_TO_CHECK}"
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
