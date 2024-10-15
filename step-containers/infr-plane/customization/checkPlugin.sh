. ./functions.sh

# check core DNS
# $1 : cluster name
function checkCoreDNS () {
  echo "##### coredns check #####"

  cd shared

  local COREDNS_ENABLED="$(jq -r '.infr_components.coredns.enabled' ./automation_conf.json)"


  if [ "${COREDNS_ENABLED}" != "" ] && [ "${COREDNS_ENABLED}" != "null" ]; then
      local COREDNS_LIM_CPU="$(jq -r '.infr_components.coredns.resources.limit_cpu' ./automation_conf.json)"
      local COREDNS_LIM_MEM="$(jq -r '.infr_components.coredns.resources.limit_ram' ./automation_conf.json)"
      local COREDNS_REQ_CPU="$(jq -r '.infr_components.coredns.resources.request_cpu' ./automation_conf.json)"
      local COREDNS_REQ_MEM="$(jq -r '.infr_components.coredns.resources.request_ram' ./automation_conf.json)"

      # SET DEFAULT VALUES
      if [ "${COREDNS_LIM_CPU}" = "" ] || [ "${COREDNS_LIM_CPU}" = "null" ]; then
        COREDNS_LIM_CPU="300m"
        echo "Setting default COREDNS_LIM_CPU"
      fi
      if [ "${COREDNS_LIM_MEM}" = "" ] || [ "${COREDNS_LIM_MEM}" = "null" ]; then
        COREDNS_LIM_MEM="170Mi"
        echo "Setting default COREDNS_LIM_MEM"
      fi
      if [ "${COREDNS_REQ_CPU}" = "" ] || [ "${COREDNS_REQ_CPU}" = "null" ]; then
        COREDNS_REQ_CPU="100m"
        echo "Setting default COREDNS_REQ_CPU"
      fi
      if [ "${COREDNS_REQ_MEM}" = "" ] || [ "${COREDNS_REQ_MEM}" = "null" ]; then
        COREDNS_REQ_MEM="70Mi"
        echo "Setting default COREDNS_REQ_MEM"
      fi

      # CHECK MEM AND CPU
      if [[ "$(get_absolute_cpu_value "${COREDNS_REQ_CPU}")" -gt "$(get_absolute_cpu_value "${COREDNS_LIM_CPU}")" ]]; then
        >&2 colorEcho "error" "coredns: request_cpu cannot be greater then limit_cpu. Please check you resources parameters"
        exit 1
      fi
      if [[ "$(get_absolute_mem_value "${COREDNS_REQ_MEM}")" -gt "$(get_absolute_mem_value "${COREDNS_LIM_MEM}")" ]]; then
        >&2 colorEcho "error" "coredns: request_mem cannot be greater then limit_mem. Please check you resources parameters"
        exit 1
      fi

      CHECK_COREDNS="$(kubectl get deployment -n kube-system coredns)"
      if [ "${CHECK_COREDNS}" = "" ] && [ "${COREDNS_ENABLED}" = "true" ]; then
        echo "coredns isn't present on cluster ${1} and will be installed in next step"

      elif [ "${CHECK_COREDNS}" = "" ] && [ "${COREDNS_ENABLED}" = "false" ]; then
        echo "coredns isn't present on cluster ${1} and will not be installed in next step"

      elif [ "${CHECK_COREDNS}" != "" ] && [ "${COREDNS_ENABLED}" = "true" ]; then
        echo "Checking coredns resources"
        CURRENT_COREDNS_REQ_CPU="$(kubectl get deployment -n kube-system coredns -o "jsonpath={.spec.template.spec.containers[].resources.requests.cpu}")"
        CURRENT_COREDNS_LIM_CPU="$(kubectl get deployment -n kube-system coredns -o "jsonpath={.spec.template.spec.containers[].resources.limits.cpu}")"
        CURRENT_COREDNS_REQ_MEM="$(kubectl get deployment -n kube-system coredns -o "jsonpath={.spec.template.spec.containers[].resources.requests.memory}")"
        CURRENT_COREDNS_LIM_MEM="$(kubectl get deployment -n kube-system coredns -o "jsonpath={.spec.template.spec.containers[].resources.limits.memory}")"
        if [[ "${COREDNS_REQ_CPU}" != "" ]] && [[ "${CURRENT_COREDNS_REQ_CPU}" != "" ]] && [[ "$(get_absolute_cpu_value "${COREDNS_REQ_CPU}")" -lt "$(get_absolute_cpu_value "${CURRENT_COREDNS_REQ_CPU}")" ]]; then
          echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_COREDNS_REQ_CPU} - inserted_value ${COREDNS_REQ_CPU}), this can cause problems in next steps."
        fi
        if [[ "${COREDNS_LIM_CPU}" != "" ]] && [[ "${CURRENT_COREDNS_LIM_CPU}" != "" ]] && [[ "$(get_absolute_cpu_value "${COREDNS_LIM_CPU}")" -lt "$(get_absolute_cpu_value "${CURRENT_COREDNS_LIM_CPU}")" ]]; then
          echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_COREDNS_LIM_CPU} - inserted_value ${COREDNS_LIM_CPU}), this can cause problems in next steps."
        fi
        if [[ "${COREDNS_REQ_MEM}" != "" ]] && [[ "${CURRENT_COREDNS_REQ_MEM}" != "" ]] && [[ "$(get_absolute_mem_value "${COREDNS_REQ_MEM}")" -lt "$(get_absolute_mem_value "${CURRENT_COREDNS_REQ_MEM}")" ]]; then
          echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_COREDNS_REQ_MEM} - inserted_value ${COREDNS_REQ_MEM}), this can cause problems in next steps."
        fi
        if [[ "${COREDNS_LIM_MEM}" != "" ]] && [[ "${CURRENT_COREDNS_LIM_MEM}" != "" ]] && [[ "$(get_absolute_mem_value "${COREDNS_LIM_MEM}")" -lt "$(get_absolute_mem_value "${CURRENT_COREDNS_LIM_MEM}")" ]]; then
          echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_COREDNS_LIM_MEM} - inserted_value ${COREDNS_LIM_MEM}), this can cause problems in next steps."
        fi

        echo "coredns is present on cluster ${1} and will be updated in next step"

      elif [ "${CHECK_COREDNS}" != "" ] && [ "${COREDNS_ENABLED}" = "false" ]; then
        echo "coredns is present on cluster ${1}, but the flag enabled is false. Will be ignorated in next step"
      fi
  fi

  cd /
}


# check autoscaler
# $1 : cluster name
function checkAutoscaler() {
  cd /shared

  #cluster_autoscaler
  echo "##### cluster-autoscaler check #####"
  local AUTOSCALER_ENABLED="$(jq -r '.infr_components.cluster_autoscaler.enabled' ./automation_conf.json)"
  if [ "${AUTOSCALER_ENABLED}" != "" ] && [ "${AUTOSCALER_ENABLED}" != "null" ]; then
    local EXPANDER="$(jq -r '.infr_components.cluster_autoscaler.parameters.expander' ./automation_conf.json)"
    local AUTOSCALER_LIM_CPU="$(jq -r '.infr_components.cluster_autoscaler.resources.limit_cpu' ./automation_conf.json)"
    local AUTOSCALER_LIM_MEM="$(jq -r '.infr_components.cluster_autoscaler.resources.limit_ram' ./automation_conf.json)"
    local AUTOSCALER_REQ_CPU="$(jq -r '.infr_components.cluster_autoscaler.resources.request_cpu' ./automation_conf.json)"
    local AUTOSCALER_REQ_MEM="$(jq -r '.infr_components.cluster_autoscaler.resources.request_ram' ./automation_conf.json)"

    if [[ "$(get_absolute_cpu_value "${AUTOSCALER_REQ_CPU}")" -gt "$(get_absolute_cpu_value "${AUTOSCALER_LIM_CPU}")" ]]; then
      >&2 colorEcho "error" "cluster_autoscaler: request_cpu cannot be greater then limit_cpu. Please check you resources parameters"
      exit 1
    fi
    if [[ "$(get_absolute_mem_value "${AUTOSCALER_REQ_MEM}")" -gt "$(get_absolute_mem_value "${AUTOSCALER_LIM_MEM}")" ]]; then
      >&2 colorEcho "error" "cluster_autoscaler: request_mem cannot be greater then limit_mem. Please check you resources parameters"
      exit 1
    fi
    CHECK_AUTOSCALER="$(kubectl get deployment -n kube-system cluster-autoscaler)"
    if [ "${CHECK_AUTOSCALER}" = "" ] && [ "${AUTOSCALER_ENABLED}" = "true" ]; then
      echo "cluster-autoscaler isn't present on cluster ${1} and will be installed in next step"

    elif [ "${CHECK_AUTOSCALER}" = "" ] && [ "${AUTOSCALER_ENABLED}" = "false" ]; then
      echo "cluster-autoscaler isn't present on cluster ${1} and will not be installed in next step"

    elif [ "${CHECK_AUTOSCALER}" != "" ] && [ "${AUTOSCALER_ENABLED}" = "true" ]; then
      mapfile -t VALIDE_EXPANDER < <((echo -e "least-waste\npriority\n"))
      if [[ ! "${VALIDE_EXPANDER[*]}" =~ ${EXPANDER} ]]; then
        >&2 colorEcho "error" "The expander inserted (${EXPANDER}) is not valid. Please check you expander param!\nExiting"
        exit 1
      fi
      if [ "${EXPANDER}" = "priority" ] && [ "${ENVIRONMENT}" = "prod" ]; then
        >&2 colorEcho "error" "The expander priority cannot be choose for prod environment. Please check you expander param!\nExiting"
        exit 1
      fi
      CURRENT_EXPANDER="$(kubectl describe deployment -n kube-system cluster-autoscaler | grep expander | cut -d "=" -f 2)"
      if [ "${CURRENT_EXPANDER}" = "${EXPANDER}" ]; then
        >&2 colorEcho "error" "The expander of the cluster-autoscaler is the same as the one already used (${CURRENT_EXPANDER})"
      else
        >&2 colorEcho "error" "The expander of the cluster-autoscaler isn't the same as the one already used (current:${CURRENT_EXPANDER} - inserted:${EXPANDER}). Will be changed in next step"
      fi
      echo "Checking cluster-autoscaler resources"
      CURRENT_AUTOSCALER_REQ_CPU="$(kubectl get deployment -n kube-system cluster-autoscaler -o "jsonpath={.spec.template.spec.containers[].resources.requests.cpu}")"
      CURRENT_AUTOSCALER_LIM_CPU="$(kubectl get deployment -n kube-system cluster-autoscaler -o "jsonpath={.spec.template.spec.containers[].resources.limits.cpu}")"
      CURRENT_AUTOSCALER_REQ_MEM="$(kubectl get deployment -n kube-system cluster-autoscaler -o "jsonpath={.spec.template.spec.containers[].resources.requests.memory}")"
      CURRENT_AUTOSCALER_LIM_MEM="$(kubectl get deployment -n kube-system cluster-autoscaler -o "jsonpath={.spec.template.spec.containers[].resources.limits.memory}")"
      if [[ "${AUTOSCALER_REQ_CPU}" != "" ]] && [[ "${CURRENT_AUTOSCALER_REQ_CPU}" != "" ]] && [[ "$(get_absolute_cpu_value "${AUTOSCALER_REQ_CPU}")" -lt "$(get_absolute_cpu_value "${CURRENT_AUTOSCALER_REQ_CPU}")" ]]; then
        echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_AUTOSCALER_REQ_CPU} - inserted_value ${AUTOSCALER_REQ_CPU}), this can cause problems in next steps."
      fi
      if [[ "${AUTOSCALER_LIM_CPU}" != "" ]] && [[ "${CURRENT_AUTOSCALER_LIM_CPU}" != "" ]] && [[ "$(get_absolute_cpu_value "${AUTOSCALER_LIM_CPU}")" -lt "$(get_absolute_cpu_value "${CURRENT_AUTOSCALER_LIM_CPU}")" ]]; then
        echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_AUTOSCALER_LIM_CPU} - inserted_value ${AUTOSCALER_LIM_CPU}), this can cause problems in next steps."
      fi
      if [[ "${AUTOSCALER_REQ_MEM}" != "" ]] && [[ "${CURRENT_AUTOSCALER_REQ_MEM}" != "" ]] && [[ "$(get_absolute_mem_value "${AUTOSCALER_REQ_MEM}")" -lt "$(get_absolute_mem_value "${CURRENT_AUTOSCALER_REQ_MEM}")" ]]; then
        echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_AUTOSCALER_REQ_MEM} - inserted_value ${AUTOSCALER_REQ_MEM}), this can cause problems in next steps."
      fi
      if [[ "${AUTOSCALER_LIM_MEM}" != "" ]] && [[ "${CURRENT_AUTOSCALER_LIM_MEM}" != "" ]] && [[ "$(get_absolute_mem_value "${AUTOSCALER_LIM_MEM}")" -lt "$(get_absolute_mem_value "${CURRENT_AUTOSCALER_LIM_MEM}")" ]]; then
        echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_AUTOSCALER_LIM_MEM} - inserted_value ${AUTOSCALER_LIM_MEM}), this can cause problems in next steps."
      fi

      echo "cluster-autoscaler is present on cluster ${1} and will be updated in next step"

    elif [ "${CHECK_AUTOSCALER}" != "" ] && [ "${AUTOSCALER_ENABLED}" = "false" ]; then
      echo "cluster-autoscaler is present on cluster ${1}, but the flag enabled is false. Will be ignorated in next step"
    fi
  fi

  cd /

}


# check metric
# $1 : cluster name
function checkMetric () {
  cd /shared

  #metric_server
  echo "##### metric-server check #####"
  local METRIC_SERVER_ENABLED="$(jq -r '.infr_components."metric-server".enabled' ./automation_conf.json)"
  if [ "${METRIC_SERVER_ENABLED}" != "" ] && [ "${METRIC_SERVER_ENABLED}" != "null" ]; then

    local METRIC_SERVER_LIM_CPU="$(jq -r '.infr_components."metric-server".resources.limit_cpu' ./automation_conf.json)"
    local METRIC_SERVER_LIM_MEM="$(jq -r '.infr_components."metric-server".resources.limit_ram' ./automation_conf.json)"
    local METRIC_SERVER_REQ_CPU="$(jq -r '.infr_components."metric-server".resources.request_cpu' ./automation_conf.json)"
    local METRIC_SERVER_REQ_MEM="$(jq -r '.infr_components."metric-server".resources.request_ram' ./automation_conf.json)"

    if [ "${METRIC_SERVER_LIM_CPU}" = "" ] || [ "${METRIC_SERVER_LIM_CPU}" = "null" ]; then
      METRIC_SERVER_LIM_CPU="300m"
      echo "Setting default METRIC_SERVER_LIM_CPU"
    fi
    if [ "${METRIC_SERVER_LIM_MEM}" = "" ] || [ "${METRIC_SERVER_LIM_MEM}" = "null" ]; then
      METRIC_SERVER_LIM_MEM="500Mi"
      echo "Setting default METRIC_SERVER_LIM_MEM"
    fi
    if [ "${METRIC_SERVER_REQ_CPU}" = "" ] || [ "${METRIC_SERVER_REQ_CPU}" = "null" ]; then
      METRIC_SERVER_REQ_CPU="100m"
      echo "Setting default METRIC_SERVER_REQ_CPU"
    fi
    if [ "${METRIC_SERVER_REQ_MEM}" = "" ] || [ "${METRIC_SERVER_REQ_MEM}" = "null" ]; then
      METRIC_SERVER_REQ_MEM="200Mi"
      echo "Setting default METRIC_SERVER_REQ_MEM"
    fi

    if [[ "$(get_absolute_cpu_value "${METRIC_SERVER_REQ_CPU}")" -gt "$(get_absolute_cpu_value "${METRIC_SERVER_LIM_CPU}")" ]]; then
      >&2 colorEcho "error" "metric-server: request_cpu cannot be greater then limit_cpu. Please check you resources parameters"
      exit 1
    fi
    if [[ "$(get_absolute_mem_value "${METRIC_SERVER_REQ_MEM}")" -gt "$(get_absolute_mem_value "${METRIC_SERVER_LIM_MEM}")" ]]; then
      >&2 colorEcho "error" "metric-server: request_mem cannot be greater then limit_mem. Please check you resources parameters"
      exit 1
    fi

    CHECK_METRIC_SERVER="$(kubectl --kubeconfig="${KUBECONF_SA}" --context="${DOMAIN}" get deployment -n kube-system metrics-server)"
    if [ "${CHECK_METRIC_SERVER}" = "" ] && [ "${METRIC_SERVER_ENABLED}" = "true" ]; then
      echo "metric-server isn't present on cluster ${1} and will be installed in next step"
    elif [ "${CHECK_METRIC_SERVER}" = "" ] && [ "${METRIC_SERVER_ENABLED}" = "false" ]; then
      echo "metric-server isn't present on cluster ${1} and will not be installed in next step"
    elif [ "${CHECK_METRIC_SERVER}" != "" ] && [ "${METRIC_SERVER_ENABLED}" = "true" ]; then

      echo "Checking metric-server resources"
      CURRENT_METRIC_SERVER_REQ_CPU="$(kubectl get deployment -n kube-system metrics-server -o "jsonpath={.spec.template.spec.containers[].resources.requests.cpu}")"
      CURRENT_METRIC_SERVER_LIM_CPU="$(kubectl get deployment -n kube-system metrics-server -o "jsonpath={.spec.template.spec.containers[].resources.limits.cpu}")"
      CURRENT_METRIC_SERVER_REQ_MEM="$(kubectl get deployment -n kube-system metrics-server -o "jsonpath={.spec.template.spec.containers[].resources.requests.memory}")"
      CURRENT_METRIC_SERVER_LIM_MEM="$(kubectl get deployment -n kube-system metrics-server -o "jsonpath={.spec.template.spec.containers[].resources.limits.memory}")"

      if [[ "${METRIC_SERVER_REQ_CPU}" != "" ]] && [[ "${CURRENT_METRIC_SERVER_REQ_CPU}" != "" ]] && [[ "$(get_absolute_cpu_value "${METRIC_SERVER_REQ_CPU}")" -lt "$(get_absolute_cpu_value "${CURRENT_METRIC_SERVER_REQ_CPU}")" ]]; then
        echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_METRIC_SERVER_REQ_CPU} - inserted_value ${METRIC_SERVER_REQ_CPU}), this can cause problems in next steps."
      fi
      if [[ "${METRIC_SERVER_LIM_CPU}" != "" ]] && [[ "${CURRENT_METRIC_SERVER_LIM_CPU}" != "" ]] && [[ "$(get_absolute_cpu_value "${METRIC_SERVER_LIM_CPU}")" -lt "$(get_absolute_cpu_value "${CURRENT_METRIC_SERVER_LIM_CPU}")" ]]; then
        echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_METRIC_SERVER_LIM_CPU} - inserted_value ${METRIC_SERVER_LIM_CPU}), this can cause problems in next steps."
      fi
      if [[ "${METRIC_SERVER_REQ_MEM}" != "" ]] && [[ "${CURRENT_METRIC_SERVER_REQ_MEM}" != "" ]] && [[ "$(get_absolute_mem_value "${METRIC_SERVER_REQ_MEM}")" -lt "$(get_absolute_mem_value "${CURRENT_METRIC_SERVER_REQ_MEM}")" ]]; then
        echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_METRIC_SERVER_REQ_MEM} - inserted_value ${METRIC_SERVER_REQ_MEM}), this can cause problems in next steps."
      fi
      if [[ "${METRIC_SERVER_LIM_MEM}" != "" ]] && [[ "${CURRENT_METRIC_SERVER_LIM_MEM}" != "" ]] && [[ "$(get_absolute_mem_value "${METRIC_SERVER_LIM_MEM}")" -lt "$(get_absolute_mem_value "${CURRENT_METRIC_SERVER_LIM_MEM}")" ]]; then
        echo "ATTENTION: the entered value is smaller than the current value (current_value: ${CURRENT_METRIC_SERVER_LIM_MEM} - inserted_value ${METRIC_SERVER_LIM_MEM}), this can cause problems in next steps."
      fi

      echo "metric-server is present on cluster ${1} and will be updated in next step"

    elif [ "${CHECK_METRIC_SERVER}" != "" ] && [ "${METRIC_SERVER_ENABLED}" = "false" ]; then
      echo "metric-server is present on cluster ${1}, but the flag enabled is false. Will be ignorated in next step"
    fi
  fi
}