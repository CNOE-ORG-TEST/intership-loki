
# setup role and roleBinding to use service account
# $1 : namespace to setup
function setupRoleBindingByNamespace () {
  #NAMESPACE kube-system
  log info "Create Role and Role Binding for ${1} namespace"
  cp /Roles-RoleBindings.yaml /Role-RoleBinding.yaml
  sed -i -e 's/__NAMESPACE__/'"${1}"'/g' /Role-RoleBinding.yaml
  kubectl apply -f /Role-RoleBinding.yaml
}