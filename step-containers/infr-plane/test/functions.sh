. /log.sh

function checkDeployment () {
  set +e
  local DEPLOY_NAME="$1"
  local NAMESPACE="$2"
  echo "Checking ${DEPLOY_NAME} deployment..."
  kubectl -n "${NAMESPACE}" get deploy "${DEPLOY_NAME}" 2>/dev/null
  local RETURN_CODE=$?

  FLAG=0
  if [ "${RETURN_CODE}" -eq 0 ]; then
    echo "${DEPLOY_NAME} deployment exits"
    kubectl -n "${NAMESPACE}" get deploy "${DEPLOY_NAME}" -o json > "${DEPLOY_NAME}".json
    local REPLICAS_DESIRED="$(jq -r '.spec.replicas' "${DEPLOY_NAME}".json)"
    local REPLICAS_AVAILABLE="$(jq -r '.status.availableReplicas' "${DEPLOY_NAME}".json)"

    if [ "${REPLICAS_DESIRED}" = "null" ] || [ "${REPLICAS_DESIRED}" = "" ]; then
      REPLICAS_DESIRED=0
    fi
    if [ "${REPLICAS_AVAILABLE}" = "null" ] || [ "${REPLICAS_AVAILABLE}" = "" ]; then
      REPLICAS_AVAILABLE=0
    fi
      if [ "${REPLICAS_DESIRED}" != "${REPLICAS_AVAILABLE}" ]; then
        FLAG=1
        echo "The deployment is not healty. Attending few minutes.."
        for LOCAL_RETRIES in {1..10}; do
            echo "Tentative number: ${LOCAL_RETRIES}"
            kubectl --kubeconfig="${KUBECONFIG}" --context="${DOMAIN}" -n "${NAMESPACE}" get deploy "${DEPLOY_NAME}" -o json > "${DEPLOY_NAME}".json
            REPLICAS_DESIRED="$(jq -r '.spec.replicas' "${DEPLOY_NAME}".json)"
            REPLICAS_AVAILABLE="$(jq -r '.status.availableReplicas' "${DEPLOY_NAME}".json)"
            if [ "${REPLICAS_DESIRED}" = "${REPLICAS_AVAILABLE}" ]; then
              echo "The deployment ${DEPLOY_NAME} is healty."
              FLAG=0
              break
            fi
            echo "The deployment ${DEPLOY_NAME} is not healty.\nAttending 60 seconds and checks it again."
            sleep 60
        done
        echo "REPLICAS_DESIRED = ${REPLICAS_DESIRED} - REPLICAS_AVAILABLE = ${REPLICAS_AVAILABLE}"
      else
        echo "The deployment ${DEPLOY_NAME} is healty."
      fi
    else
      colorEcho "warning" "${DEPLOY_NAME} deployment doesn't exist"
    fi

    return ${FLAG}
}