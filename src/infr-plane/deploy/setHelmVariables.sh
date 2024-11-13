# format variables in variables.json
# $1 : SECURITY_GROUP_IDS_PARAMETER
# $2 : ENI_SUBNETS
# $3 : DEPLOY_AWS_REGION
# void
function setBaseVariables() {
  #SECURITY GROUP VARIABLE
  echo "Configuring security groups variable"
  mapfile -t ARR_SECURITY_GROUPS < <(echo "${1}" | tr "," "\n")
  for SECURITY_GROUP in "${ARR_SECURITY_GROUPS[@]}"; do
    SECURITY_GROUPS+="    - ${SECURITY_GROUP} \n"
  done
  echo "SECURITY_GROUPS:\n${SECURITY_GROUPS}"

  #SUBNET VARIABLE
  echo "Configuring subnets for EniConfig"
  mapfile -t ENICONFIG_SUBNETS < <(echo "${2}" | tr "," "\n")
  for SUBNET in "${ENICONFIG_SUBNETS[@]}"; do
    INFO_SUBNET="$(aws ec2 describe-subnets --subnet-ids "${SUBNET}")"
    AZ="$(echo "${INFO_SUBNET}" | jq -r '.Subnets[].AvailabilityZone')"
    if [[ "${AZ}" = *"1a"* ]]; then
      echo "Subnet ${SUBNET} is ${3}a"
      SUBNET_1a="${SUBNET}"
    elif [[ "${AZ}" = *"1b"* ]]; then
      echo "Subnet ${SUBNET} is ${3}b"
      SUBNET_1b="${SUBNET}"
    elif [[ "${AZ}" = *"1c"* ]]; then
      echo "Subnet ${SUBNET} is ${3}c"
      SUBNET_1c="${SUBNET}"
    else
      >&2 colorEcho "error" "The subnet ${SUBNET} isn't nor ${3}a nor ${3}b nor ${3}c. It isn't not permitted! \nExiting"
      exit 1
    fi
  done
}



function setAwsCniVariables () {
  echo "setup aws cni variables"
  cd /shared

  AWS_CNI_NETPOL_ENABLED="$(jq -r '.infr_components."aws-cni".enableNetworkPolicy' ./automation_conf.json)"
  if [ "${AWS_CNI_NETPOL_ENABLED,,}" = "false" ] || [ "${AWS_CNI_NETPOL_ENABLED}" = "" ] || [ "${AWS_CNI_NETPOL_ENABLED}" = "null" ]; then
    AWS_CNI_NETPOL_ENABLED="false"
    echo "The Network Policy Controller is \"${AWS_CNI_NETPOL_ENABLED}\" will not be enabled!"
  else
    echo "The Network Policy controller is \"${AWS_CNI_NETPOL_ENABLED}\" and will be enabled!"
  fi

  cd /
}

# set autoscaler variables
# $1 : cluster name
# $2 : autoscaler helm file
# void
function setAutoscalerVariables () {
  echo "setup autoscaler helm variables"
  cd /shared

  AUTOSCALER_ENABLED="$(jq -r '.infr_components.cluster_autoscaler.enabled' ./automation_conf.json)"
  if [ "${AUTOSCALER_ENABLED,,}" = "false" ] || [ "${AUTOSCALER_ENABLED}" = "" ] || [ "${AUTOSCALER_ENABLED}" = "null" ]; then
    echo "cluster_autoscaler flag is false: will be elimitated from helm/templates directory"
    rm -f /helm/templates/eks-cluster-autoscaler.yaml
  fi

  AUTOSCALER_LIM_CPU="$(jq -r '.infr_components.cluster_autoscaler.resources.limit_cpu' ./automation_conf.json)"
  AUTOSCALER_LIM_MEM="$(jq -r '.infr_components.cluster_autoscaler.resources.limit_ram' ./automation_conf.json)"
  AUTOSCALER_REQ_CPU="$(jq -r '.infr_components.cluster_autoscaler.resources.request_cpu' ./automation_conf.json)"
  AUTOSCALER_REQ_MEM="$(jq -r '.infr_components.cluster_autoscaler.resources.request_ram' ./automation_conf.json)"
  EXPANDER="$(jq -r '.infr_components.cluster_autoscaler.parameters.expander' ./automation_conf.json)"
  SCALE_DOWN_TIME="$(jq -r '.infr_components.cluster_autoscaler.parameters.scale_down_time' ./automation_conf.json)"

  #SCALE_DOWN_TIME default 10 if is empty or null
  if [ "${SCALE_DOWN_TIME}" = "" ] || [ "${SCALE_DOWN_TIME}" = "null" ]; then
   SCALE_DOWN_TIME="10"
  fi

  if [ "${EXPANDER}" = "priority" ] && [ "${AUTOSCALER_ENABLED}" = "true" ]; then
    local AUTOMATION_CONF_DP="automation_conf_dp.json"
    downloadAutomationConfJson "${GITHUB_ORG}/${1}Dataplane" "${GITHUB_TOKEN}" "${AUTOMATION_CONF_DP}"
    mapfile -t ALL_NODEGROUPS_NAMES_CF< <(jq -r '.nodegroups[] | select(.cloudformation_options.is_spot=="true") | .datapanel_cloudformation_name' "${AUTOMATION_CONF_DP}")
    if [ "${#ALL_NODEGROUPS_NAMES_CF[@]}" -ne 0 ]; then
      echo "There are spot nodegroups. The configmap can be created"
      for NODEGROUP_NAME_CF in "${ALL_NODEGROUPS_NAMES_CF[@]}"; do
        NODEGROUPS_NAMES_CF+="      - ${NODEGROUP_NAME_CF} \n"
      done
      echo "NODEGROUPS_NAMES_CF: ${NODEGROUPS_NAMES_CF}"
      echo "ConfigMap expander priority"
      sed -i -e 's|__NODEGROUPS_NAMES_CF__|'"${NODEGROUPS_NAMES_CF}"'|g' /cluster-autoscaler-priority-expander.yaml
      cat /cluster-autoscaler-priority-expander.yaml
      echo "---" >> ${2}
      cat /cluster-autoscaler-priority-expander.yaml >> ${2}
    else
      echo "There aren't spot nodegroups. The configmap cannot be created. The expander will be least-waste"
      EXPANDER="least-waste"
    fi
  fi

  cd /
}


function setCoreDNS () {
  echo "setup core DNS"
  cd /shared

  COREDNS_ENABLED="$(jq -r '.infr_components.coredns.enabled' ./automation_conf.json)"
  COREDNS_LIM_CPU="$(jq -r '.infr_components.coredns.resources.limit_cpu' ./automation_conf.json)"
  COREDNS_LIM_MEM="$(jq -r '.infr_components.coredns.resources.limit_ram' ./automation_conf.json)"
  COREDNS_REQ_CPU="$(jq -r '.infr_components.coredns.resources.request_cpu' ./automation_conf.json)"
  COREDNS_REQ_MEM="$(jq -r '.infr_components.coredns.resources.request_ram' ./automation_conf.json)"

  if [ "${COREDNS_ENABLED}" = "" ] || [ "${COREDNS_ENABLED}" = "null" ]; then
    COREDNS_ENABLED="true"
    echo "COREDNS_ENABLED value empty, setting default COREDNS_ENABLED to true value"
  fi

  if [ "${COREDNS_ENABLED}" = "true" ]; then
    if [ "${COREDNS_LIM_CPU}" = "" ] || [ "${COREDNS_LIM_CPU}" = "null" ]; then
      COREDNS_LIM_CPU="500m"
      echo "Setting default COREDNS_LIM_CPU"
    fi
    if [ "${COREDNS_LIM_MEM}" = "" ] || [ "${COREDNS_LIM_MEM}" = "null" ]; then
      COREDNS_LIM_MEM="500Mi"
      echo "Setting default COREDNS_LIM_MEM"
    fi
    if [ "${COREDNS_REQ_CPU}" = "" ] || [ "${COREDNS_REQ_CPU}" = "null" ]; then
      COREDNS_REQ_CPU="300m"
      echo "Setting default COREDNS_REQ_CPU"
    fi
    if [ "${COREDNS_REQ_MEM}" = "" ] || [ "${COREDNS_REQ_MEM}" = "null" ]; then
      COREDNS_REQ_MEM="300Mi"
      echo "Setting default COREDNS_REQ_MEM"
    fi
  fi

  cd /

  #Generaing VPA configuration for CoreDNS
  echo "Checking if the VPA is available in the chosen cluster (${DEPLOY_AWS_ACCOUNT_ID} - ${CLUSTER_NAME_EXTENDED})"
  set +e
  VPA_RESPONSE_CMD=$(kubectl get vpa 2>&1)
  set -e

  warning_msg="Warning: Use tokens from the TokenRequest API or manually created secret-based tokens instead of auto-generated secret-based tokens."
  VPA_RESPONSE=${VPA_RESPONSE_CMD//$warning_msg/}

  if [[ "${VPA_RESPONSE}" != *"the server doesn't have a resource type"* ]]; then
    VPA_ISPRESENT="true"
    echo "Applying vpa for coredns and waiting five minute"
    kubectl apply -f /vpa-coredns.yaml
    #sleep 5m
    TARGET_MEM="$(kubectl -n kube-system get vpa coredns-vpa -o jsonpath='{.status.recommendation.containerRecommendations[].target.memory}')"
    UPPER_MEM="$(kubectl -n kube-system get vpa coredns-vpa -o jsonpath='{.status.recommendation.containerRecommendations[].upperBound.memory}')"

    TARGET_CPU="$(kubectl -n kube-system get vpa coredns-vpa -o jsonpath='{.status.recommendation.containerRecommendations[].target.cpu}')"
    UPPER_CPU="$(kubectl -n kube-system get vpa coredns-vpa -o jsonpath='{.status.recommendation.containerRecommendations[].upperBound.cpu}')"

    echo "TARGET_MEM=${TARGET_MEM}"
    unit="${TARGET_MEM: -1}"
    if [ "$unit" == "k" ]; then
      TARGET_MEM_MI=$(( ${TARGET_MEM%k} / 1024 ))
    else
      TARGET_MEM_MI=${TARGET_MEM}
    fi

    echo "UPPER_MEM=${UPPER_MEM}"
    unit="${UPPER_MEM: -1}"
    if [ "$unit" == "k" ]; then
      UPPER_MEM_MI=$(( ${UPPER_MEM%k} / 1024 ))
    else
      UPPER_MEM_MI=${UPPER_MEM}
    fi

    echo "TARGET_MEM_MI=${TARGET_MEM_MI} - "$(get_absolute_mem_value "${TARGET_MEM_MI}Mi")""
    echo "COREDNS_REQ_MEM=${COREDNS_REQ_MEM} - "$(get_absolute_mem_value "${COREDNS_REQ_MEM}")""
    if [[ "$(get_absolute_mem_value "${TARGET_MEM_MI}Mi")" -gt "$(get_absolute_mem_value "${COREDNS_REQ_MEM}")" ]]; then
      COREDNS_REQ_MEM="${TARGET_MEM_MI}Mi"
      echo "VPA value for target MEMORY usage is greater than inserted value, using it: ${TARGET_MEM_MI}Mi"
    else
      echo "Using inserted MEMORY value for request for: ${COREDNS_REQ_MEM}"
    fi

    echo "UPPER_MEM_MI=${UPPER_MEM_MI} - "$(get_absolute_mem_value "${UPPER_MEM_MI}Mi")""
    echo "COREDNS_LIM_MEM=${COREDNS_LIM_MEM} -  "$(get_absolute_mem_value "${COREDNS_LIM_MEM}")""
    if [[ "$(get_absolute_mem_value "${UPPER_MEM_MI}Mi")" -gt "$(get_absolute_mem_value "${COREDNS_LIM_MEM}")" ]]; then
      COREDNS_LIM_MEM="${UPPER_MEM_MI}Mi"
      echo "VPA value for upper MEMORY usage is greater than inserted value, using it: ${UPPER_MEM_MI}Mi"
    else
      echo "Using inserted MEMORY value for limit: ${COREDNS_LIM_MEM}"
    fi

    if [[ "$(get_absolute_cpu_value "${TARGET_CPU}")" -gt "$(get_absolute_cpu_value "${COREDNS_REQ_CPU}")" ]]; then
      COREDNS_REQ_CPU="${TARGET_CPU}"
      echo "VPA value for target CPU usage is greater than inserted value, using it: ${COREDNS_REQ_CPU}"
    else
      echo "Using inserted CPU value for request for: ${COREDNS_REQ_CPU}"
    fi

    if [[ "$(get_absolute_cpu_value "${UPPER_CPU}")" -gt "$(get_absolute_cpu_value "${COREDNS_LIM_CPU}")" ]]; then
      COREDNS_LIM_CPU="${UPPER_CPU}"
      echo "VPA value for upper CPU usage is greater than inserted value, using it: ${COREDNS_LIM_CPU}"
    else
      echo "Using inserted CPU value for limit: ${COREDNS_LIM_CPU}"
    fi

  else
    colorEcho "warning" "The VPA is not installed in the cluster"
    VPA_ISPRESENT="false"
  fi
}

function setMetricServer () {
  echo "setup metric server"
  cd /shared

  METRIC_SERVER_ENABLED="$(jq -r '.infr_components."metric-server".enabled' ./automation_conf.json)"
  METRIC_SERVER_LIM_CPU="$(jq -r '.infr_components."metric-server".resources.limit_cpu' ./automation_conf.json)"
  METRIC_SERVER_LIM_MEM="$(jq -r '.infr_components."metric-server".resources.limit_ram' ./automation_conf.json)"
  METRIC_SERVER_REQ_CPU="$(jq -r '.infr_components."metric-server".resources.request_cpu' ./automation_conf.json)"
  METRIC_SERVER_REQ_MEM="$(jq -r '.infr_components."metric-server".resources.request_ram' ./automation_conf.json)"


  if [ "${METRIC_SERVER_ENABLED}" = "true" ]; then
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

  else
    echo "Metric server flag is false: will be elimitated from helm/templates directory"
    rm -f /helm/templates/metric-server.yaml
  fi

  cd /
}


