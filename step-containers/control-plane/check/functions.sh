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

function generateKubeconfig () {
  rm -f ${KUBECONF}
  cat <<EOF > ${KUBECONF}
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
        - "${CLUSTER_NAME_EXTENDED}"
EOF
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
    log error "Secret doesn't exists, please check your secretmanager. Are you sure that the secret [${SECRET_ID}] is wrote correctly in the dynmoBD and that the cluster EKS exists? Please check your configuration"
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


function checkSecret () {
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
    log info "Secret doesn't exists! OK"
  elif [[ ${RESPONSE_LAMBDA} = *"The request was invalid due to"* ]]; then
    log info"Lambda requests was invalid, check logs for more details"
  elif [[ ${RESPONSE_LAMBDA} = *"The request had invalid params due to"* ]]; then
    log info "Lambda requests params was invalid, check logs for more details"
  elif [ -z "$(echo "${RESPONSE_LAMBDA}")" ]; then
    log info "Bamboo configuration variables missing or not retrieved"
  else
    >&2 log error "The secret already exists. Please check your plan params!"
    exit 1
  fi

}

function getAutomationConfJson () {
  KIND_PANEL="$1"
  SECRET="$(aws secretsmanager get-secret-value --secret-id "bamboo.${BAMBOOENV}.api.access" --query SecretString --output text --profile "${MASTER_PROFILE}" --region "${MASTER_REGION}")"
  USER_BAMBOO="$(echo "${SECRET}" | jq -jr '. | "\(.username)"')"
  PASS_BAMBOO="$(echo "${SECRET}" | jq -jr '. | "\(.password)"')"

  if [ "${BAMBOOENV}" = "noprod" ]; then
    URL="bitbucketdev.springlab.enel.com"
  else 
    URL="bitbucket.springlab.enel.com"
  fi
  
  PROJECT_KEY="${SC_TAG_PARAMETER}-${GIAS_ID_NOT_DOT_TAG_PARAMETER}-${ENVIRONMENT}-${CLOUD_PROVIDER}-project-mk8s"
  REPOSITORY_KEY="${CLUSTER_NAME}-${NET_KUBERNETES_TYPE}-${CLUSTER_TYPE}-${DEPLOY_AWS_ACCOUNT_ID}-${DEPLOY_AWS_REGION}-repo-${KIND_PANEL}"
  REPOSITORY_KINDPANEL="https://${USER_BAMBOO}:${PASS_BAMBOO}@${URL}/scm/${PROJECT_KEY}/${REPOSITORY_KEY}.git" 
  log info "Retrieving repository: ${REPOSITORY_KEY}"

  set +e
  CHECK_REPO="$(git ls-remote ${REPOSITORY_KINDPANEL})"
  set -e

  if [ $? = 0 ]; then 
    log info "Repository ${REPOSITORY_KEY}. Cloning it..."
    rm -rf "${REPOSITORY_KEY}"
    set +e
    CLONED=$(git clone "${REPOSITORY_KINDPANEL}")
    RETURN_CODE=$?
    set -e

    if [ "${RETURN_CODE}" -ne 0 ]; then
      >&2 log error "Error during cloning '${REPOSITORY_KEY}'..\nRepository not exists.."
      PANEL_INFORMATION=""
    else 
      log info "Repository ${REPOSITORY_KEY} cloned correctly."
      chown -R "${USERID}":"${GROUPID}" "${REPOSITORY_KEY}"
      PANEL_INFORMATION="${REPOSITORY_KEY}/automation_conf.json"
    fi

  else 
    PANEL_INFORMATION=""
  fi
}

function getLastTagRepository () {
  KIND_PANEL="$1"
  SECRET="$(aws secretsmanager get-secret-value --secret-id "bamboo.${BAMBOOENV}.api.access" --query SecretString --output text --profile "${MASTER_PROFILE}" --region "${MASTER_REGION}")"
  USER_BAMBOO="$(echo "${SECRET}" | jq -jr '. | "\(.username)"')"
  PASS_BAMBOO="$(echo "${SECRET}" | jq -jr '. | "\(.password)"')"

  if [ "${BAMBOOENV}" = "noprod" ]; then
    URL="bitbucketdev.springlab.enel.com"
  else 
    URL="bitbucket.springlab.enel.com"
  fi
  REPOSITORY_KINDPANEL="https://${USER_BAMBOO}:${PASS_BAMBOO}@${URL}/scm/itsessie/cicd-mk8s-cluster-${KIND_PANEL}.git" 
  TAG="$(git ls-remote --tags ${REPOSITORY_KINDPANEL} -l 1.* | sort -n | awk 'END{print}' | awk '{ print $2; }' | cut -d "/" -f 3)"
}