. ./log.sh

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

# add tag to frontend network for load balancer
# $1 : ids of the frontend network to tag
# $2 : cluster names
# void
function addTagToFrontendNetwork () {
  local FE_SUBNETS=$(echo ${1} | tr "," " ")
  echo "Tagging frontend ${NET_KUBERNETES_TYPE} subnets..."
  aws ec2 create-tags --resources ${FE_SUBNETS} --tags Key=kubernetes.io/cluster/"${2}",Value=shared
  echo "Subnets tagged successfully"
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

# check if exist OIDC provider
# $1 : cluster id
# $2 : aws account id
# $3 : aws region where deploy the cluster
# return : string ( "true" if cluster exist, "false" otherwise )
function existOIDCProvider () {
  set +e
  local OIDC_PROVIDER
  OIDC_PROVIDER=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::${2}:oidc-provider/oidc.eks.${3}.amazonaws.com/id/${1}" 2>&1)
  RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -eq 0 ]; then
    echo "true"
  else
    echo "false"
  fi
}

# check if exist OIDC provider
# $1 : name of the cluster to check
# $2 : aws account id
# $3 : aws region where deploy the cluster
# void
function checkOIDCProvider() {
  local EKS_DESCRIPTION="$(aws eks describe-cluster --name "${1}" 2>&1)"
  local CLUSTER_ID="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.endpoint' | cut -d "/" -f3 | cut -d "." -f1)"
  echo "Checking oidc provider arn:aws:iam::${2}:oidc-provider/oidc.eks.${3}.amazonaws.com/id/${CLUSTER_ID}"
  if [ "$(existOIDCProvider "${CLUSTER_ID}" "${2}" "${3}")" = "false" ]; then
    echo "Oidc provider doesn't exist: oidc.eks.${3}.amazonaws.com/id/${CLUSTER_ID}\nCreating new one..."
    #local SRV_CERTIFICATE="c7ccdfd44b79de55780690a159cce8f67eea33c2"
    aws iam create-open-id-connect-provider --url "https://oidc.eks.${3}.amazonaws.com/id/${CLUSTER_ID}" --client-id-list "sts.amazonaws.com" --region "${3}"
    echo "Oidc provider created successfully."
  else
    echo "Oidc provider already exists: oidc.eks.${3}.amazonaws.com/id/${CLUSTER_ID}"
  fi
}

# check if network endpoint is public
# $1 : name of the cluster
# void
function checkEndpoint() {
    echo "Checking if eks cluster is private..."
    local EKS_DESCRIPTION="$(aws eks describe-cluster --name "${1}" 2>&1)"
    if [ "$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.resourcesVpcConfig.endpointPrivateAccess' )" = "true" ] && [ "$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.resourcesVpcConfig.endpointPublicAccess' )" = "false" ] ; then
      echo "Cluster with name ${1} is private."
    elif [ "$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.resourcesVpcConfig.endpointPrivateAccess' )" = "false" ] && [ "$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.resourcesVpcConfig.endpointPublicAccess' )" = "true" ]; then
      echo "Cluster with name ${1} is public. Passing from public endpoint to private ..."
      aws eks update-cluster-config --name "${1}" --resources-vpc-config endpointPrivateAccess=true,endpointPublicAccess=false && sleep 60 && aws eks wait cluster-active --name "${1}"
    else
      >&2 colorEcho "error" "Cannot retrieve Cluster ${1} information"
      exit 1
    fi
}

# create new kubeconfig file for the cluster passed as second parameter in position passed as first parameter
# $1 : path of the new kubeconfig
# $2 : cluster name
# void
function generateKubeconfig () {
  # retrieve variables
  local EKS_DESCRIPTION="$(aws eks describe-cluster --name "${2}" 2>&1)"
  local CLUSTER_API_ENDPOINT="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.endpoint')"
  local CA_DATA_B64="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.certificateAuthority.data')"
  local CA_DATA_DECODED="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.certificateAuthority.data' | base64 -d)"
  local DOMAIN="externalUser"
  # create file
  rm -f ${1}
  cat <<EOF > ${1}
apiVersion: v1
clusters:
- cluster:
    server: ${CLUSTER_API_ENDPOINT}
    certificate-authority-data: ${CA_DATA_B64}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: ${DOMAIN}
current-context: ${DOMAIN}
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws
      args:
        - "eks"
        - "get-token"
        - "--cluster-name"
        - "${2}"
EOF
}

# check if exist secret
# $1 : secret id or name
# return : string ( "true" if cluster exist, "false" otherwise )
function existSecret(){
    set +e
    local SECRET_DESCRIPTION
    SECRET_DESCRIPTION="$(aws secretsmanager describe-secret --secret-id "${1}"  2>&1)"
    local RETURN_CODE=$?
    set -e
    if [ "${RETURN_CODE}" -eq 0 ]; then
      echo "true"
    elif [[ "${SECRET_DESCRIPTION}" == *"ResourceNotFoundException"* ]]; then
      echo "false"
    else
      >&2 colorEcho "error" "exist Secret check error: ${SECRET_DESCRIPTION}"
      exit 1
    fi

}

# create aws secret with and save kubeconfing in
# $1 : cluster name
# $2 : deploy region
function createKubeconfigSecret(){
  echo "Generating Kubeconfig."
  generateKubeconfig ./kubeconf.yaml ${1}
  echo "Kubeconfig generated."
  local SECRET_NAME="cnoe-loki-kubeconfig-${1}"
  if [ "$(existSecret "${SECRET_NAME}")" = "true" ]; then
    echo "Secret updating..."
    aws secretsmanager update-secret --secret-id "${SECRET_NAME}" --secret-string "$(cat ./kubeconf.yaml)" --region "${2}"
    echo "Secret updated"
  else
    echo "Secret creating..."
    aws secretsmanager create-secret --name ${SECRET_NAME} --description "Contains the kubeconfig file necessary for accessing the ${1} cluster." --secret-string "$(cat ./kubeconf.yaml)" --region "${2}"
    echo "Secret created"
  fi
}