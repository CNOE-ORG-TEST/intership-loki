. ./log.sh

# assign new role (created in pull step) to service account
# $1 : arn of the role to assign
# $2 : region where deploy the cluster
# void
function assignRoleToServiceAccount () {
  echo "Assuming role: ${$1}"
  aws sts assume-role --role-arn "${$1}" --role-session-name=session-role-controlplane-$$ --region "${$2}" --duration-seconds 3600
  local ROLE_ASSUMED="$(aws sts get-caller-identity)"
  echo "Role assumed: ${ROLE_ASSUMED}"
}

# add tag to frontend network
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
  local EKS_DESCRIPTION="$(aws eks describe-cluster --name "${1}" 2>&1)"
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -eq 0 ]; then
    echo "true"
  else
    echo "false"
  fi
}

# check if exist OIDC provider
# $1 : cluster id
# $2 : aws account id
# $3 : aws region where deploy the cluster
# return : string ( "true" if cluster exist, "false" otherwise )
function existOIDCProvider () {
  set +e
  aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::${2}:oidc-provider/oidc.eks.${3}.amazonaws.com/id/${1}"
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
function checkOIDCProvider() {
  local CLUSTER_ID="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.endpoint' | cut -d "/" -f3 | cut -d "." -f1)"
  echo "Checking oidc provider arn:aws:iam::${2}:oidc-provider/oidc.eks.${3}.amazonaws.com/id/${CLUSTER_ID}"
  if [ "$(existOIDCProvider)" "${CLUSTER_ID}" "${2}" "${3}" ]; then
    echo "Oidc provider doesn't exist: oidc.eks.${3}.amazonaws.com/id/${CLUSTER_ID}\nCreating new one..."
    # TODO check SRV_CERTIFICATE
    SRV_CERTIFICATE="9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
    aws iam create-open-id-connect-provider --url https://oidc.eks."${3}".amazonaws.com/id/"${CLUSTER_ID}" --client-id-list "sts.amazonaws.com" --thumbprint-list "${SRV_CERTIFICATE}" --region "${3}"
    log info "Oidc provider created successfully."
  else
    log info "Oidc provider already exists: oidc.eks.${3}.amazonaws.com/id/${CLUSTER_ID}"
  fi
}

# check if network endpoint is public
# $1 : name of the cluster
# void
function checkEndpoint() {
    echo "Checking if eks cluster is private..."
    local EKS_DESCRIPTION="$(aws eks describe-cluster --name "${1}" 2>&1)"
    if [ "$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.resourcesVpcConfig.endpointPrivateAccess' )" = "true" ] && [ "$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.resourcesVpcConfig.endpointPublicAccess' )" = "false" ] ; then
      log debug "Cluster with name ${1} is private."
    elif [ "$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.resourcesVpcConfig.endpointPrivateAccess' )" = "false" ] && [ "$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.resourcesVpcConfig.endpointPublicAccess' )" = "true" ]; then
      echo "Cluster with name ${1} is public. Passing from public endpoint to private ..."
      aws eks update-cluster-config --name "${1}" --resources-vpc-config endpointPrivateAccess=true,endpointPublicAccess=false && sleep 60 && aws eks wait cluster-active --name "${1}"
    else
      >&2 echoColor "error" "Cannot retrieve Cluster ${1} information"
      exit 1
    fi
}

}