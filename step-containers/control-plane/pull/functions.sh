#!/bin/bash -e

function err_report() {
>&2 echo "Error on line $1"
}
trap 'err_report $LINENO' ERR

function crypt () {
  salt=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '')
  echo $salt > salt
  openssl enc -in /data/aws/credentials -out /data/aws/credentials_ -e -aes256 -k "0dnTq%sPtbffOD?Xl0TlJeAxZmCv?clrmw$salt"
  mv /data/aws/credentials_ /data/aws/credentials
}

function decrypt () {
  salt=$(cat salt)
  openssl enc -in /data/aws/credentials -out /root/.aws/credentials -d -aes256 -k "0dnTq%sPtbffOD?Xl0TlJeAxZmCv?clrmw$salt"
}

function del_creds () {
  rm -rf /data/aws/*
}

function checkLambda () {
  response="$*"
  printf "\n$response\n"
  if [[ $response == *"FunctionError"* ]]; then
    printf "LAMBDA FAILED\n"
    return 1
  fi
}

function generateKubeconfigAdmin () {
  KUBECONFIG="$1"
  DOMAIN="$2"
  rm -rf "${KUBECONFIG}"
  SECRET="${SECRET_ID}"
  SECRET_CLUSTER_ID="${CLUSTER_TYPE}"
  SECRET_CLUSTER_TYPE="${CLUSTER_TYPE}"
  if [ "$(echo "${SECRET}" | cut -d "." -f 1)" = "noprod" ]; then
    SECRET_CLUSTER_INSTALLATION_TYPE="$(echo "${SECRET}" | cut -d "." -f 3)"
    SECRET_ACCOUNT="$(echo "${SECRET}" | cut -d "." -f 4)"
    SECRET_REGION="$(echo "${SECRET}" | cut -d "." -f 5)"
    if [ "${CLUSTER_TYPE}" = "default" ]; then
      SECRET_APM=""
      SECRET_ENV=""
      SECRET_NET_TYPE="$(echo "${SECRET}" | cut -d "." -f 7)"
    else
      SECRET_APM="$(echo "${SECRET}" | cut -d "." -f 6)"
      SECRET_ENV="$(echo "${SECRET}" | cut -d "." -f 7)"
      SECRET_NET_TYPE="$(echo "${SECRET}" | cut -d "." -f 8)"
    fi
  else
    SECRET_CLUSTER_INSTALLATION_TYPE="$(echo "${SECRET}" | cut -d "." -f 2)"
    SECRET_ACCOUNT="$(echo "${SECRET}" | cut -d "." -f 3)"
    SECRET_REGION="$(echo "${SECRET}" | cut -d "." -f 4)"
    if [ "${CLUSTER_TYPE}" = "default" ]; then
      SECRET_APM=""
      SECRET_ENV=""
      SECRET_NET_TYPE="$(echo "${SECRET}" | cut -d "." -f 6)"
    else
      SECRET_APM="$(echo "${SECRET}" | cut -d "." -f 5)"
      SECRET_ENV="$(echo "${SECRET}" | cut -d "." -f 6)"
      SECRET_NET_TYPE="$(echo "${SECRET}" | cut -d "." -f 7)"
    fi
  fi
  LAMBDA_PAYLOAD="$(echo "{\"bamboo_env\": \"${BAMBOOENV}\", \"cluster_id\":\"${SECRET_CLUSTER_ID}\", \"cluster_type\":\"${SECRET_CLUSTER_TYPE}\", \"cluster_installation_type\":\"${SECRET_CLUSTER_INSTALLATION_TYPE}\", \"account\": \"${SECRET_ACCOUNT}\", \"region\": \"${SECRET_REGION}\", \"gias_id\":\"${SECRET_APM}\", \"net_type\":\"${SECRET_NET_TYPE}\", \"env\":\"${SECRET_ENV}\"}" | jq -cs add)"
  LAMBDA_NAME="enel_${BAMBOOENV}_microservice_get_cluster_secrets"
  
  log debug "LAMBDA_NAME: ${LAMBDA_NAME}"
  log debug "LAMBDA_PAYLOAD: ${LAMBDA_PAYLOAD}"

  checkLambda "$(aws lambda invoke --function-name "${LAMBDA_NAME}" --payload "${LAMBDA_PAYLOAD}" --profile "${MASTER_PROFILE}" --region "${MASTER_REGION}" response_lambda.json)"
  RESPONSE_LAMBDA=$(cat response_lambda.json | sed -e 's/^"//' -e 's/"$//' | sed "s/\'/\"/g")
  if [[ ${RESPONSE_LAMBDA} = *"The requested secret"* ]]; then
    log error "Secret doesn't exists, please check your secretmanager"
    del_creds
    exit 1
  elif [[ ${RESPONSE_LAMBDA} = *"The request was invalid due to"* ]]; then
    log error "Lambda requests was invalid, check logs for more details"
    del_creds
    exit 1
  elif [[ ${RESPONSE_LAMBDA} = *"The request had invalid params due to"* ]]; then
    log error "Lambda requests params was invalid, check logs for more details"
    del_creds
    exit 1
  elif [ -z "$(echo "${RESPONSE_LAMBDA}")" ]; then
    log error "Bamboo configuration variables missing or not retrieved"
    del_creds
    exit 1
  else
    K8S_ACCOUNT=$(python -c "import json; print(json.loads('$RESPONSE_LAMBDA')['account']);")
    USER=$(python -c "import json; print(json.loads('$RESPONSE_LAMBDA')['user']);")
    PASS=$(python -c "import json; print(json.loads('$RESPONSE_LAMBDA')['password']);")
    CLUSTER=$(python -c "import json; print(json.loads('$RESPONSE_LAMBDA')['cluster']);")
    CERTIFICATE_AUTHORITY=$(python -c "import json; print(json.loads('$RESPONSE_LAMBDA')['certification_authority']);")
    log info "Bamboo configuration variables correctly retrieved"
  fi

  echo "${CERTIFICATE_AUTHORITY}" > ${SECRET_ID}.ca.crt
  sed -i -e 's/-----BEGIN CERTIFICATE-----/'"-----BEGIN CERTIFICATE-----\n"'/g' ./${SECRET_ID}.ca.crt
  sed -i -e 's/-----END CERTIFICATE-----/'"\n-----END CERTIFICATE-----"'/g' ./${SECRET_ID}.ca.crt
  kubectl --kubeconfig="${KUBECONFIG}" config set-credentials "${DOMAIN}" --token="${PASS}"
  kubectl --kubeconfig="${KUBECONFIG}" config set-cluster "${DOMAIN}" --server="${CLUSTER}"
  kubectl --kubeconfig="${KUBECONFIG}" config set-cluster "${DOMAIN}" --certificate-authority=${SECRET_ID}.ca.crt
  kubectl --kubeconfig="${KUBECONFIG}" config set-context "${DOMAIN}" --cluster="${DOMAIN}" --user="${DOMAIN}"
}


function generateAdminServiceaccount () {
  cat <<EOF | kubectl apply --kubeconfig="${KUBECONF}" -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
EOF
}

function generateKubeconfig () {
  rm -f ${KUBECONF}
  cat <<EOF > ${KUBECONF}
apiVersion: v1
clusters:
- cluster:
    server: ${SERVER}
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
        - "${CLUSTER_NAME_EXTENDED}"
EOF
}

function generateTestTemplate () {
  cat /test-connectivity-pod.yaml | \
    sed "s/__NS_NAME_TEST__/${NS_NAME_TEST}-$i/g" | \
    sed "s/__DEPLOYMENT_NAME_TEST__/${DEPLOYMENT_NAME_TEST}-$i/g" | \
    sed "s/__SVC_NAME_TEST__/${SVC_NAME_TEST}-$i/g"
}

function checkDeployment () {
  set +e
  DEPLOY_NAME="$1"
  KUBECONFIG="$2"
  DOMAIN="$3"
  NAMESPACE="$4"
  log info "Checking ${DEPLOY_NAME} deployment..."
  kubectl --kubeconfig="${KUBECONFIG}" --context="${DOMAIN}" -n "${NAMESPACE}" get deploy "${DEPLOY_NAME}"
  RETURN_CODE=$?


  FLAG=0
  if [ "${RETURN_CODE}" -eq 0 ]; then 
    log info "${DEPLOY_NAME} deployment exits"
    kubectl --kubeconfig="${KUBECONFIG}" --context="${DOMAIN}" -n "${NAMESPACE}" get deploy "${DEPLOY_NAME}" -o json > "${DEPLOY_NAME}".json
    REPLICAS_DESIRED="$(jq -r '.spec.replicas' "${DEPLOY_NAME}".json)"
    REPLICAS_AVAILABLE="$(jq -r '.status.availableReplicas' "${DEPLOY_NAME}".json)"
    if [ "${REPLICAS_DESIRED}" != "${REPLICAS_AVAILABLE}" ]; then 
        log error "Error in ${DEPLOY_NAME} deployment"
        log error "REPLICAS_DESIRED = ${REPLICAS_DESIRED} - REPLICAS_AVAILABLE = ${REPLICAS_AVAILABLE}"
        FLAG=1
    fi
  else
      log debug "${DEPLOY_NAME} deployment doesn't exist"
  fi

  return ${FLAG}
}

function getControlPanelCloudformationName () {
  SECRET="$(aws secretsmanager get-secret-value --secret-id "bamboo.${BAMBOOENV}.api.access" --query SecretString --output text --profile "${MASTER_PROFILE}" --region "${MASTER_REGION}")"
  USER_BAMBOO="$(echo "${SECRET}" | jq -jr '. | "\(.username)"')"
  PASS_BAMBOO="$(echo "${SECRET}" | jq -jr '. | "\(.password)"')"

  if [ "${BAMBOOENV}" = "noprod" ]; then
    URL="bitbucketdev.springlab.enel.com"
  else 
    URL="bitbucket.springlab.enel.com"
  fi
  
  PROJECT_KEY="${SC_TAG_PARAMETER}-${GIAS_ID_NOT_DOT_TAG_PARAMETER}-${ENVIRONMENT}-${CLOUD_PROVIDER}-project-mk8s"
  REPOSITORY_KEY="${CLUSTER_NAME}-${NET_KUBERNETES_TYPE}-${CLUSTER_TYPE}-${DEPLOY_AWS_ACCOUNT_ID}-${DEPLOY_AWS_REGION}-repo-controlpanel"
  REPOSITORY_CONTROLPANEL="https://${USER_BAMBOO}:${PASS_BAMBOO}@${URL}/scm/${PROJECT_KEY}/${REPOSITORY_KEY}.git" 
  log info "Retrieving repository: ${REPOSITORY_KEY}"

  rm -rf "${REPOSITORY_KEY}"
  log info "Cloning repository: ${REPOSITORY_KEY}"

  set +e
  CLONED=$(git clone "${REPOSITORY_CONTROLPANEL}")
  RETURN_CODE=$?
  set -e

  if [ "${RETURN_CODE}" -ne 0 ]; then
    >&2 log error "Error during cloning '${REPOSITORY_KEY}'..\nExiting..."
    exit 1
  else 
    log info "Repository ${REPOSITORY_KEY} cloned correctly."
    chown -R "${USERID}":"${GROUPID}" "${REPOSITORY_KEY}"
  fi

  FILE="${REPOSITORY_KEY}/automation_conf.json"
  CONTROLPANEL_CLOUDFORMATION_NAME="$(jq -r '.controlpanel_cloudformation_name' "${FILE}")"
}

function getDataPanelCloudformationName () {
  SECRET="$(aws secretsmanager get-secret-value --secret-id "bamboo.${BAMBOOENV}.api.access" --query SecretString --output text --profile "${MASTER_PROFILE}" --region "${MASTER_REGION}")"
  USER_BAMBOO="$(echo "${SECRET}" | jq -jr '. | "\(.username)"')"
  PASS_BAMBOO="$(echo "${SECRET}" | jq -jr '. | "\(.password)"')"

  if [ "${BAMBOOENV}" = "noprod" ]; then
    URL="bitbucketdev.springlab.enel.com"
  else 
    URL="bitbucket.springlab.enel.com"
  fi
  
  PROJECT_KEY="${SC_TAG_PARAMETER}-${GIAS_ID_NOT_DOT_TAG_PARAMETER}-${ENVIRONMENT}-${CLOUD_PROVIDER}-project-mk8s"
  REPOSITORY_KEY="${CLUSTER_NAME}-${NET_KUBERNETES_TYPE}-${CLUSTER_TYPE}-${DEPLOY_AWS_ACCOUNT_ID}-${DEPLOY_AWS_REGION}-repo-datapanel"
  REPOSITORY_DATAPANEL="https://${USER_BAMBOO}:${PASS_BAMBOO}@${URL}/scm/${PROJECT_KEY}/${REPOSITORY_KEY}.git" 
  log info "Retrieving repository: ${REPOSITORY_KEY}"

  rm -rf "${REPOSITORY_KEY}"
  log info "Cloning repository: ${REPOSITORY_KEY}"

  set +e
  CLONED=$(git clone "${REPOSITORY_DATAPANEL}")
  RETURN_CODE=$?
  set -e

  if [ "${RETURN_CODE}" -ne 0 ]; then
    >&2 log error "Repository '${REPOSITORY_KEY}' not exist...\n"
    DATAPANEL_INFORMATION=""
  else 
    log info "Repository ${REPOSITORY_KEY} exits. Cloned correctly."
    chown -R "${USERID}":"${GROUPID}" "${REPOSITORY_KEY}"
    DATAPANEL_INFORMATION="${REPOSITORY_KEY}/automation_conf.json"
  fi


}
