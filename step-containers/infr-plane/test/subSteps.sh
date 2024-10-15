. /log.sh
. /functions.sh

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
  local RETRIES=10
  while [ ${RETRIES} -ne 0 ]
  do
      set +e
      local CODE="$(kubectl -n "test-eks" exec "test-client" -- curl -s "nginx-service-to-test.test-eks" -w "%{http_code}\n" -o /dev/null 2>&1)"
      set -e
      if [[ "${CODE}" =~ ^[0-9]+$ ]] && [ "${CODE}" -eq 200 ]; then
          echo "Test connectivity successfully"
          break
      else
          colorEcho "warning" "Test connectivity failed (for error: ${CODE}), let's wait 30 seconds and retry"
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
# $1 : enable cluster autoscaler
# $2 : enable metric server
# void
function kubesystemDeploymentsTest(){
  local RESULT_VALUES=()
  set +e



  checkDeployment "coredns" "kube-system"
  RESULT_VALUES[0]=$?
  local DEPLOYMENT_TO_CHECK="coredns"
  if [ "${1}" = "true" ]; then
    DEPLOYMENT_TO_CHECK+=", cluster-autoscaler"
    checkDeployment "cluster-autoscaler" "kube-system"
    RESULT_VALUES[1]=$?
  fi
  if [ "${2}" = "true" ]; then
    DEPLOYMENT_TO_CHECK+=", metrics-server"
    checkDeployment "metrics-server" "kube-system"
    RESULT_VALUES[2]=$?
  fi

  set -e

  if [[ "${RESULT_VALUES[*]}" =~ 1 ]]; then
      >&2 colorEcho "error" "At least one of these deployments is not healty: ${DEPLOYMENT_TO_CHECK}"
      exit 1
  fi
  echo "Deployments check passed: ${DEPLOYMENT_TO_CHECK}"
}
