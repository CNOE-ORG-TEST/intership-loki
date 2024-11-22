. /log.sh
. /functions.sh


# assign new role (created in pull step) to service account
# $1 : arn of the role to assign
# $2 : region where deploy the cluster
# void
function assignRoleToServiceAccount () {
  echo "Assuming role: ${1}"
  local OLD_ROLE="$(aws sts get-caller-identity)"
  echo "Old role: ${OLD_ROLE}"
  aws sts assume-role --role-arn "${1}" --role-session-name=session-role-infrplane-$$ --region "${2}" --duration-seconds 3600
  local ROLE_ASSUMED="$(aws sts get-caller-identity)"
  echo "Role assumed: ${ROLE_ASSUMED}"
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


# limit permission to the cluster for securety perimeter
# $1: name of the service account (SA_NAME)
# void
function limitClusterPermissions() {
  #GENERATE KUBECONFIG SA
  echo "SA_NAME: ${1}"
  local DOMAIN="${1}"
  local KUBECONF_SA="/${DOMAIN}_kubeconf.yaml"
  local NAMESPACE="kube-system"
  local SERVER="$(kubectl config view | grep server | sed 's/server://g;s/ //g')"
  local TOKEN_NAME="$(kubectl -n "${NAMESPACE}" get secret | grep ${1}-token | tr "\n" " " |cut -d ' ' -f 1 )"

  if [[ "${TOKEN_NAME}" != *"serviceaccounts \"${1}\" not found"* ]]; then
    echo "Creating kubeconfig sa"
    kubectl -n "${NAMESPACE}" get secret "${TOKEN_NAME}" -o "jsonpath={.data.ca\.crt}" | base64 -d > ca.crt
    local TOKEN_VALUE=$(kubectl -n "${NAMESPACE}" get secret "${TOKEN_NAME}" -o "jsonpath={.data.token}" | base64 -d)
    kubectl --kubeconfig="${KUBECONF_SA}" config set-credentials "${SA_NAME}-user" --token="${TOKEN_VALUE}" --client-key=ca.crt --embed-certs=true
    kubectl --kubeconfig="${KUBECONF_SA}" config set-cluster "${DOMAIN}" --server="${SERVER}"
    kubectl --kubeconfig="${KUBECONF_SA}" config set-cluster "${DOMAIN}" --certificate-authority=ca.crt --embed-certs=true
    kubectl --kubeconfig="${KUBECONF_SA}" config set-context "${DOMAIN}" --cluster="${DOMAIN}" --user="${SA_NAME}-user" --namespace="${NAMESPACE}"
    kubectl --kubeconfig="${KUBECONF_SA}" config use-context "${DOMAIN}"
    echo "KUBECONF_SA:"
    cat "${KUBECONF_SA}"
    export KUBECONFIG="${KUBECONF_SA}"
  else
    >&2 colorEcho "error" "Service account with name \"${1}\" not found.\nThere was a problem with creating the serviceaccount.\nExiting "
    exit 1
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


  echo "Test coredns..."
  checkDeployment "coredns" "kube-system"
  NUMBER_CHECKED=0
  RESULT_VALUES[NUMBER_CHECKED]=$?
  NUMBER_CHECKED=$((NUMBER_CHECKED + 1))
  local DEPLOYMENT_TO_CHECK="coredns"
  if [ "${1}" = "true" ]; then
    echo "Test cluster-autoscaler..."
    DEPLOYMENT_TO_CHECK+=", cluster-autoscaler"
    checkDeployment "cluster-autoscaler" "kube-system"
    RESULT_VALUES[NUMBER_CHECKED]=$?
    NUMBER_CHECKED=$((NUMBER_CHECKED + 1))
  fi
  if [ "${2}" = "true" ]; then
    echo "Test metrics-server..."
    DEPLOYMENT_TO_CHECK+=", metrics-server"
    checkDeployment "metrics-server" "kube-system"
    RESULT_VALUES[NUMBER_CHECKED]=$?
    NUMBER_CHECKED=$((NUMBER_CHECKED + 1))
  fi

  set -e

  echo "${ARRAY[@]}"
  if [[ "${RESULT_VALUES[*]}" =~ 1 ]]; then
      >&2 colorEcho "error" "At least one of these deployments is not healty: ${DEPLOYMENT_TO_CHECK}"
      exit 1
  else
      echo "Deployments check passed: ${DEPLOYMENT_TO_CHECK}"
  fi

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
