. /log.sh
. /functions.sh

# download variables.json and automation_conf.json
# void
function downloadVariablesFiles() {
  cd /shared
  cp /etc/config/variables.json /shared/variables.json
  curl -H "Authorization: Bearer ${GITHUB_TOKEN}" -L "https://raw.githubusercontent.com/${GITHUB_REPO}/main/automation_conf.json" > /shared/automation_conf.json
  echo "\nvariables.json parameters:"
  cat variables.json

  echo "\nautomation_conf.json parameters:"
  cat automation_conf.json
  cd /
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


# create service account to access to the cluster
# $1 : service account name
# void
function createServiceAccount() {
  echo "SA_NAME: ${1}"

  echo "apply Service account"
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${1}
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: ${1}-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: ${1}
type: kubernetes.io/service-account-token
EOF

  echo "Checking ${1} ServiceAccount for correctness purposes"
  if  kubectl -n kube-system patch sa ${1} --type=json -p="[{'op': 'remove', 'path': '/secrets'}]" 1>/dev/null 2>/dev/null ;then
      echo "Operation completed successfully, service account ${1}  has been fixed"
    else
      echo "No operation needed to be carried out, the service account is well-formed"
  fi

}


# create namespaces for plugins
# void
function createNamespaces() {
    cd /
    aws s3 cp s3://cnoe-loki-manifest-templates/infrplane-manifest/kubernetes/namespaces.yaml /namespaces.yaml
    kubectl apply -f /namespaces.yaml
}

# setup role and roleBinfing for each namespace of each plugin
# $1 : service account name
function setupRoleBindings() {
  #Role - RoleBinding
  sed -i -e 's/__SA_NAME__/'"${1}"'/g' /Roles-RoleBindings.yaml

  setupRoleBindingByNamespace "kube-system"
  setupRoleBindingByNamespace "metrics"

}