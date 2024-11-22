. /log.sh
. /functions.sh
. /setHelmVariables.sh

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

# download helm files
# $1 : infrplane version
# void
function downloadHelmFiles() {
  echo "Dowloading templates from s3 bucket"

  aws s3 cp s3://cnoe-loki-manifest-templates/infrplane-manifest/kubernetes/version${1}/helm/ /helm --recursive
  ls -la /helm/
}

# set helm variables
# $1 : Cluster name
# $2 : SECURITY_GROUP_IDS_PARAMETER
# $3 : ENI_SUBNETS
# $4 : DEPLOY_AWS_REGION
# void
function setHelmVariables() {
  setAwsCniVariables
  setAutoscalerVariables "${1}" "/helm/templates/eks-cluster-autoscaler.yaml"
  setCoreDNS
  setMetricServer
  setBaseVariables "${2}" "${3}" "${4}"
}

# check if exist path to helm values file
# $1 : HELM_VALUE_PATH
# void
function helmValuesFileValidation () {
  if [ ! -f ${1} ]; then
    >&2 colorEcho "error" "helm values file doesn't exist environment can be only:"
    for file in /helm/values/*; do
      >&2 colorEcho "red" "${file%.*};"
    done
    exit 1
  fi
}

# compile helm values file
# $1 : path to helm file
# void
function compileHelmValuesFile () {
  echo "Sed on helm values file ${1}"

  #sed -i -e 's/__AWS_ACCOUNT__/'"${DEPLOY_AWS_ACCOUNT_ID}"'/g' "${1}"
  sed -i -e 's/__AWS_REGION__/'"${DEPLOY_AWS_REGION}"'/g' "${1}"
  sed -i -e 's/__CLUSTER_NAME__/'"${CLUSTER_NAME}"'/g' "${1}"

  sed -i -e 's/__EXPANDER__/'"${EXPANDER}"'/g' "${1}"
  sed -i -e 's/__CLUSTER_AUTOSCALER_SCALE_DOWN_TIME__/'"${SCALE_DOWN_TIME}"'/g' "${1}"
  sed -i -e 's/__CLUSTER_AUTOSCALER_LIMITS_CPU__/'"${AUTOSCALER_LIM_CPU}"'/g' "${1}"
  sed -i -e 's/__CLUSTER_AUTOSCALER_LIMITS_MEM__/'"${AUTOSCALER_LIM_MEM}"'/g' "${1}"
  sed -i -e 's/__CLUSTER_AUTOSCALER_REQUESTS_CPU__/'"${AUTOSCALER_REQ_CPU}"'/g' "${1}"
  sed -i -e 's/__CLUSTER_AUTOSCALER_REQUESTS_MEM__/'"${AUTOSCALER_REQ_MEM}"'/g' "${1}"

  sed -i -e 's/__SECURITY_GROUPS__/'"${SECURITY_GROUPS}"'/g' "${1}"
  sed -i -e 's/__SUBNET_1a__/'"${SUBNET_1a}"'/g' "${1}"
  sed -i -e 's/__SUBNET_1b__/'"${SUBNET_1b}"'/g' "${1}"
  sed -i -e 's/__SUBNET_1c__/'"${SUBNET_1c}"'/g' "${1}"

  sed -i -e 's/__COREDNS_LIMITS_CPU__/'"${COREDNS_LIM_CPU}"'/g' "${1}"
  sed -i -e 's/__COREDNS_LIMITS_MEM__/'"${COREDNS_LIM_MEM}"'/g' "${1}"
  sed -i -e 's/__COREDNS_REQUESTS_CPU__/'"${COREDNS_REQ_CPU}"'/g' "${1}"
  sed -i -e 's/__COREDNS_REQUESTS_MEM__/'"${COREDNS_REQ_MEM}"'/g' "${1}"

  sed -i -e 's/__METRIC_SERVER_LIMITS_CPU__/'"${METRIC_SERVER_LIM_CPU}"'/g' "${1}"
  sed -i -e 's/__METRIC_SERVER_LIMITS_MEM__/'"${METRIC_SERVER_LIM_MEM}"'/g' "${1}"
  sed -i -e 's/__METRIC_SERVER_REQUESTS_CPU__/'"${METRIC_SERVER_REQ_CPU}"'/g' "${1}"
  sed -i -e 's/__METRIC_SERVER_REQUESTS_MEM__/'"${METRIC_SERVER_REQ_MEM}"'/g' "${1}"

  sed -i -e 's/__ENABLE_NET_POL_CONTROLLER__/'"${AWS_CNI_NETPOL_ENABLED}"'/g' "${1}"

  sed -i -e 's/__VERSION__/'"${INFRPANEL_VERSION}"'/g' "${1}"
  sed -i -e 's/__ENABLE_COREDNS__/'"${COREDNS_ENABLED}"'/g' "${1}"
  sed -i -e 's/__ENABLE_CLUSTERAUTOSCALER__/'"${AUTOSCALER_ENABLED}"'/g' "${1}"
  sed -i -e 's/__ENABLE_METRIC__/'"${METRIC_SERVER_ENABLED}"'/g' "${1}"
}

# deploy artifact in helm chart
# $1 : cluster name
# $2 : path to helm variables file
# $3 : label
function deployHelm () {
  echo "Generating helm template"
  helm template -f ${2} ./helm > tmp_template.yaml
  echo "Add label to resources in helm template"
  kubectl label -f tmp_template.yaml --local ${3} -o json --overwrite > template.yaml
  echo "Apply generated helm template with prune (${3})"
  kubectl get po -A -l "${3}"
  kubectl apply -f template.yaml --prune -l ${3} \
    --prune-whitelist=core/v1/Pod \
    --prune-whitelist=core/v1/Service \
    --prune-whitelist=core/v1/ServiceAccount \
    --prune-whitelist=core/v1/Secret \
    --prune-whitelist=core/v1/ConfigMap \
    --prune-whitelist=core/v1/Namespace \
    --prune-whitelist=apps/v1/Deployment \
    --prune-whitelist=apps/v1/DaemonSet \
    --prune-whitelist=apps/v1/ReplicaSet \
    --prune-whitelist=storage.k8s.io/v1/StorageClass \
    --prune-whitelist=rbac.authorization.k8s.io/v1/ClusterRole \
    --prune-whitelist=rbac.authorization.k8s.io/v1/ClusterRoleBinding \
    --prune-whitelist=rbac.authorization.k8s.io/v1/Role \
    --prune-whitelist=rbac.authorization.k8s.io/v1/RoleBinding \
    --prune-whitelist=apiregistration.k8s.io/v1/APIService \
    --prune-whitelist=crd.k8s.amazonaws.com/v1alpha1/ENIConfig \
    --prune-whitelist=autoscaling/v1/HorizontalPodAutoscaler \
    --prune-whitelist=admissionregistration.k8s.io/v1/ValidatingWebhookConfiguration

  mapfile -t DEPLOYMENTS < <(yq eval '. | (select(.kind == "Deployment")).metadata.name, (select(.kind == "Deployment")).metadata.namespace' tmp_template.yaml | sed 's/---//g;/^$/d' | awk 'NR%2{printf "%s ",$0;next;}1')
  local NUM_DEPLOYMENT="${#DEPLOYMENTS[@]}"
  echo "${NUM_DEPLOYMENT} deployments are just created on the cluster ${1}."

}