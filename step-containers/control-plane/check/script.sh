#!/bin/bash -e

set -e

cd /shared
cat ./variables.json

CLUSTER_NAME="$(jq -r '.clusterName' ./variables.json)"
CUSTOMER_TAG_PARAMETER="$(jq -r '.customerTagParameter' ./variables.json)"
ENVIRONMENT_TAG_PARAMETER="$(jq -r '.environmentTagParameter' ./variables.json)"
GIAS_ID_TAG_PARAMETER="$(jq -r '.giasIDTagParameter' ./variables.json)"
GIAS_ID_NOT_DOT_TAG_PARAMETER="${GIAS_ID_TAG_PARAMETER//./}"
GIAS_NAME_TAG_PARAMETER="$(jq -r '.giasNameTagParameter' ./variables.json)"
PROJECT_TAG_PARAMETER="$(jq -r '.projectTagParameter' ./variables.json)"
ROLE_TAG_PARAMETER="$(jq -r '.roleTagParameter' ./variables.json)"
RUNNING_TAG_PARAMETER="$(jq -r '.runningTagParameter' ./variables.json)"
SC_TAG_PARAMETER="$(jq -r '.scTagParameter' ./variables.json)"
SECURITY_GROUP_IDS_PARAMETER="$(jq -r '.securityGroupIdsParameter' ./variables.json)"
FE_SUBNET_IDS_PARAMETER="$(jq -r '.feSubnetIdsParameter' ./variables.json)"
BE_SUBNET_IDS_PARAMETER="$(jq -r '.beSubnetIdsParameter' ./variables.json)"
VPC_ID_PARAMETER="$(jq -r '.vpcIdParameter' ./variables.json)"
CLOUD_PROVIDER="$(jq -r '.cloudProvider' ./variables.json)"
CUSTOM_KUBERNETES="$(jq -r '.customKubernetes' ./variables.json)"
IS_FEDERATED_CLUSTER="$(jq -r '.isFederatedCluster' ./variables.json)"
DEPLOY_AWS_ACCOUNT_ID="$(jq -r '.account' ./variables.json)"
DEPLOY_AWS_REGION="$(jq -r '.region' ./variables.json)"
BAMBOOENV="$(jq -r '.bamboo_env' ./variables.json)"
ENVIRONMENT="$(jq -r '.environment' ./variables.json)"
MASTER_ACCOUNT="$(jq -r '.master_account' ./variables.json)"
MASTER_REGION="$(jq -r '.master_region' ./variables.json)"
NET_KUBERNETES_TYPE="$(jq -r '.netKubernetesType' ./variables.json)"
PLANSPEC_ACTUAL_MAJOR_VERSION="$(jq -r '.planspec_actual_major_version' ./variables.json)"
PLANSPEC_ACTUAL_MINOR_VERSION="$(jq -r '.planspec_actual_minor_version' ./variables.json)"

CLOUDFORMATION_NAME="$(jq -r '.controlpanel_cloudformation_name' deploy_and_release_variables.json)"
BACKUP_PARAMETER="$(jq -r '.cloudformation_parameters.BackupParameter' deploy_and_release_variables.json)"
CONTROLPANEL_VERSION="$(jq -r '.controlpanel_version' deploy_and_release_variables.json)"
TIMESTAMP_BUILD="$(jq -r '.timestamp_build' deploy_and_release_variables.json)"

GENERATE_KUBECONFIG="$(jq -r '.generate_kubeconfig_admin' deploy_and_release_variables.json)"

DEBUG=1
echo "DEBUG_ACTIVE=${DEBUG_ACTIVE}"
echo "Cloudformation name: ${CLOUDFORMATION_NAME}"

if [ "${CUSTOM_KUBERNETES}" = "true" ]; then
  CLUSTER_TYPE="custom"
else
  if [ "${IS_FEDERATED_CLUSTER}" = "true" ]; then
    >&2 echo "You are trying to deploy FEDERATED cluster with parameter CLUSTER_TYPE != custom. Federated clusters supports only CLUSTER_TYPE=custom. Please check your parameters then try again."
    exit 1
  fi
  CLUSTER_TYPE="default"
fi

SECRET_BAMBOO_ACCESS_NAME="bamboo.prod.thor.access"
SECRET_BAMBOO_ACCESS="$(aws secretsmanager get-secret-value --secret-id "${SECRET_BAMBOO_ACCESS_NAME}" --query SecretString --output text" --region "${MASTER_REGION}")"
AWS_ACCESS_KEY_ID="$(echo ${SECRET_BAMBOO_ACCESS} | jq -jr '. | "\(.AWS_ACCESS_KEY_ID)"')"
AWS_SECRET_ACCESS_KEY="$(echo ${SECRET_BAMBOO_ACCESS} | jq -jr '. | "\(.AWS_SECRET_ACCESS_KEY)"')"

ROLE_NAME="${SC_TAG_PARAMETER,,}-${GIAS_ID_NOT_DOT_TAG_PARAMETER,,}-${CLUSTER_NAME,,}-${ENVIRONMENT,,}-role-mk8s-cp"
ROLE_ARN="arn:aws:iam::${DEPLOY_AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo "Assuming role: ${ROLE_ARN}"
ASSUME_ROLE_RES="$(AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" aws sts assume-role --role-arn "${ROLE_ARN}" --role-session-name=session-role-controlpanel-$$ --region "${DEPLOY_AWS_REGION}" --duration-seconds 43200)"
export AWS_ACCESS_KEY_ID=$(echo "${ASSUME_ROLE_RES}" | jq -r ".Credentials.AccessKeyId")
export AWS_SECRET_ACCESS_KEY=$(echo "${ASSUME_ROLE_RES}" | jq -r ".Credentials.SecretAccessKey")
export AWS_SESSION_TOKEN=$(echo "${ASSUME_ROLE_RES}" | jq -r ".Credentials.SessionToken")
export AWS_DEFAULT_REGION=${DEPLOY_AWS_REGION}
ROLE_ASSUMED="$(aws sts get-caller-identity)"
echo "Role assumed: ${ROLE_ASSUMED}"

S3_URL="s3://enel-prod-infr-automation-releases-${DEPLOY_AWS_REGION}/mk8s/controlpanel/release-${BAMBOOENV}/${CONTROLPANEL_VERSION}/aws_infrastructure_packaged.yaml"
echo "Dowloading ${S3_URL}"
aws s3 cp "${S3_URL}" aws_infrastructure_packaged.yaml --profile "${PROJECT_PROFILE}" --region "${DEPLOY_AWS_REGION}"
S3_URL="s3://enel-prod-infr-automation-releases-${DEPLOY_AWS_REGION}/mk8s/controlpanel/release-${BAMBOOENV}/${CONTROLPANEL_VERSION}/aws_infrastructure_configuration.json"
echo "Dowloading ${S3_URL}"
aws s3 cp "${S3_URL}" aws_infrastructure_configuration.json --profile "${PROJECT_PROFILE}" --region "${DEPLOY_AWS_REGION}"
DEPLOY_CONTROLPANEL_VERSION="$(jq -r '.[] | select(.ParameterKey=="ClusterVersion") | .ParameterValue' aws_infrastructure_configuration.json)"

if [ "${IS_FEDERATED_CLUSTER}" = "true" ] && [ "${CUSTOM_KUBERNETES}" = "true" ]; then
  echo "Check of subnets on platform is not necessary"
elif [ "${NET_KUBERNETES_TYPE}" = "lan" ]; then
  echo "Check of subnets in lan net is not necessary, subnets backend and subnets frontend are the same"
else 
  echo "Checking subnets frontend/backend"
  # take names of frontend network
  FE_SUBNETS=$(echo "${FE_SUBNET_IDS_PARAMETER}" | tr "," " ")
  mapfile -t ARR_SUBNETS_FE < <(aws ec2 describe-subnets --subnet-ids ${FE_SUBNETS} | jq -cr '.Subnets[].Tags[] | select(.Key=="Name") | .Value | @sh')
  # take names of backend network
  BE_SUBNETS=$(echo "${BE_SUBNET_IDS_PARAMETER}" | tr "," " ")
  mapfile -t ARR_SUBNETS_BE < <(aws ec2 describe-subnets --subnet-ids ${BE_SUBNETS} | jq -cr '.Subnets[].Tags[] | select(.Key=="Name") | .Value | @sh')

  # regular expression that network name must match
  SUBNET_REGEX_BE=".*[bB][eE](-|[0-9]).*"
  SUBNET_REGEX_FE=".*[fF][eE](-|[0-9]).*"

  echo "Checking backend subnets ${ARR_SUBNETS_BE[*]}"
  # check match between network names and regular expression
  for BE_SUBNET in "${ARR_SUBNETS_BE[@]}"; do
    if [[ "${BE_SUBNET}" =~ ${SUBNET_REGEX_BE} ]]; then
      echo "Subnet ${BE_SUBNET} is backend"
    else
      # if don't match => error
      >&2 echo "Subnet ${BE_SUBNET} is NOT backend. Exiting..."
      exit 1
    fi
  done
  # same thing of above
  echo "Checking frontend subnets ${ARR_SUBNETS_FE[*]}"
  for FE_SUBNET in "${ARR_SUBNETS_FE[@]}"; do
    if [[ "${FE_SUBNET}" =~ ${SUBNET_REGEX_FE} ]]; then
      echo "Subnet ${FE_SUBNET} is frontend"
    else
      >&2 echo "Subnet ${FE_SUBNET} is NOT frontend. Exiting..."
      exit 1
    fi
  done
fi


echo "Checking match net_type <-> security_group"
# get security groups names (simil firewall for networks)
SECURITY_GROUP_NAME="$(aws ec2 describe-security-groups --group-ids "${SECURITY_GROUP_IDS_PARAMETER}" --query "SecurityGroups[*].{Name:GroupName,ID:GroupId}" | jq -r '.[0].Name')"

echo "Security group ${SECURITY_GROUP_IDS_PARAMETER}: ${SECURITY_GROUP_NAME}"
echo "Net Type: ${NET_KUBERNETES_TYPE}"

# compare if network type match securityGroup name
if [[ "${SECURITY_GROUP_NAME}" == *"${NET_KUBERNETES_TYPE}"* ]]; then
  echo "Security group ${SECURITY_GROUP_NAME} is compatible with net type ${NET_KUBERNETES_TYPE}"
else
  >&2 echo "Security group ${SECURITY_GROUP_NAME} is NOT compatible with net type ${NET_KUBERNETES_TYPE}. Exiting..."
  exit 1
fi

KUBECONF="kubeconfig.yaml"
ACTUAL_KUBECONF="actual-kubeconfig.yaml"
DOMAIN="enelint"
if [ "${IS_FEDERATED_CLUSTER}" = "true" ]; then

  # incoke a lambda function to retrive kubernates clusters
  LAMBDA_NAME="enel_${BAMBOOENV}_lambda_read_ddb_platform_default_values"
  echo "Invoking Lambda: ${LAMBDA_NAME}"
  LAMBDA_PAYLOAD="$(echo "{\"sc\":\"all\", \"gias_id_dot\":\"all\", \"env\":\"all\", \"type\":\"all\"}" | jq -c)"
  echo "LAMBDA_PAYLOAD=${LAMBDA_PAYLOAD}"
  checkLambda "$(aws lambda invoke --function-name "${LAMBDA_NAME}" --payload "${LAMBDA_PAYLOAD}" --profile "${MASTER_PROFILE}" --region "${MASTER_REGION}" response_lambda.json)"
  
  K8S_CLUSTERS=$(cat response_lambda.json)
  #echo "K8S_CLUSTERS=${K8S_CLUSTERS}"

  set +e
  mapfile -t N_SECRETS < <(echo "${K8S_CLUSTERS}" | jq --arg DEPLOY_AWS_ACCOUNT_ID "${DEPLOY_AWS_ACCOUNT_ID}" -r '.[] | select(.eks_clusters[] | contains($DEPLOY_AWS_ACCOUNT_ID)) | .eks_clusters[]' | sort -u -t. -k3,3)
  mapfile -t SECRETS < <(echo "${K8S_CLUSTERS}" | jq --arg DEPLOY_AWS_ACCOUNT_ID "${DEPLOY_AWS_ACCOUNT_ID}" -r '.[] | select(.eks_clusters[] | contains($DEPLOY_AWS_ACCOUNT_ID)) | .eks_clusters[]' | grep -v "${DEPLOY_AWS_ACCOUNT_ID}" | sort -u -t. -k3,3)
  set -e
  if [ "${#N_SECRETS[*]}" -eq 0 ]; then
    >&2 echo "This account is not configured in DynamoDB enel_${BAMBOOENV}_ddb_platform_default_values. Please configure it before proceed to launch this plan"
    exit 1
  else
    if [ "${#SECRETS[*]}" -gt 0 ]; then
      for SECRET_ID in "${SECRETS[@]}"; do
        echo "Creating Kubeconfig from secret ${SECRET_ID}"
        generateKubeconfigAdmin "${KUBECONF}" "${DOMAIN}"
        echo "Checking controlpanel/datapanel/infrpanel version of clusters"
        #CONTROL PANEL VERSION
        set +e
        CONTROLPANEL_K8S_VERSION="$(kubectl --kubeconfig="${KUBECONF}" --context="${DOMAIN}" version -o json | jq -r '(.serverVersion.major +"."+.serverVersion.minor)' | sed "s/+//g")"
        set -e
        CONTROLPANEL_NEXT_VERSION=$( (echo "$CONTROLPANEL_K8S_VERSION + 0.01") | bc )
        CONTROLPANEL_PERMITTED_VERSIONS=("${CONTROLPANEL_K8S_VERSION}" "${CONTROLPANEL_NEXT_VERSION}")
        if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ " ${DEPLOY_CONTROLPANEL_VERSION} " ]]; then
          >&2 echo "${DEPLOY_CONTROLPANEL_VERSION} NOT permitted! Please check your controlpanel version.\nExiting..."
          exit 1
        else
          echo "Controlpanel checks: OK"
        fi
        #DATA PANEL VERSIONS

        ##### FARGATE NODES CHECKS #####
        #DEPLOY_CONTROLPANEL_VERSION="1.26" # FOR TEST
        echo "Control plane EKS VERSION ${DEPLOY_CONTROLPANEL_VERSION}. Checking fargate nodes"
        OLD_K8S_FARGATE_NODES="false"
        set +e
        mapfile -t DATAPANEL_FARGATE_K8S_VERSIONS< <(kubectl --kubeconfig="${KUBECONF}" --context="${DOMAIN}" get nodes --no-headers | grep fargate | awk '{print $5}' | cut -d "-" -f1 | cut -d "." -f1,2 | sed "s/^v//g" | sort -u)
        set -e
        for DATAPANEL_FARGATE_K8S_VERSION in "${DATAPANEL_FARGATE_K8S_VERSIONS[@]}"; do
          CONTROLPANEL_NEXT_VERSION=$( (echo "$DATAPANEL_FARGATE_K8S_VERSION + 0.01") | bc )
          CONTROLPANEL_PERMITTED_VERSIONS=( "${DATAPANEL_FARGATE_K8S_VERSION}" "${CONTROLPANEL_NEXT_VERSION}" )
          if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ " ${DEPLOY_CONTROLPANEL_VERSION} " ]]; then
            OLD_K8S_FARGATE_NODES="true"
          fi
        done

        if [ "${OLD_K8S_FARGATE_NODES}" = "true" ]; then
          echo "There are some fargate nodes with old EKS version on this cluster $(echo ${SECRET_ID} | cut -d "." -f3)"
          CONTROLPANEL_PREVIOUS_VERSION=$( (echo "$DEPLOY_CONTROLPANEL_VERSION - 0.01") | bc )
          echo "kubectl --kubeconfig="${KUBECONF}" --context="${DOMAIN}" get nodes --no-headers | grep fargate | grep -v "${DEPLOY_CONTROLPANEL_VERSION}" | grep -v "${CONTROLPANEL_PREVIOUS_VERSION}""
          echo "################################"
          kubectl --kubeconfig="${KUBECONF}" --context="${DOMAIN}" get nodes --no-headers | grep fargate | grep -v "${DEPLOY_CONTROLPANEL_VERSION}" | grep -v "${CONTROLPANEL_PREVIOUS_VERSION}"
          exit 1
        else
          echo "All fargate nodes are with correct EKS version"
        fi
        ################################

        set +e
        mapfile -t DATAPANEL_K8S_VERSIONS< <(kubectl --kubeconfig="${KUBECONF}" --context="${DOMAIN}" get nodes --no-headers | awk '{print $5}' | cut -d "-" -f1 | cut -d "." -f1,2 | sed "s/^v//g" | sort -u)
        set -e
        for DATAPANEL_K8S_VERSION in "${DATAPANEL_K8S_VERSIONS[@]}"; do
          CONTROLPANEL_NEXT_VERSION=$( (echo "$DATAPANEL_K8S_VERSION + 0.01") | bc )
          CONTROLPANEL_PERMITTED_VERSIONS=( "${DATAPANEL_K8S_VERSION}" "${CONTROLPANEL_NEXT_VERSION}" )
          if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ " ${DEPLOY_CONTROLPANEL_VERSION} " ]]; then
            echo "${DEPLOY_CONTROLPANEL_VERSION} NOT permitted! Permitted version of controlpanel are ${CONTROLPANEL_PERMITTED_VERSIONS[@]}. Please check your controlpanel version!"
            echo "!!!! There are nodes that differ by more than one version backward, please check the status of the cluster nodes. !!!!!"
            exit 1
          else
            echo "Datapanel checks: OK"
          fi
        done
        #INFR PANEL VERSION
        set +e
        INFRPANEL_K8S_VERSION="$(kubectl --kubeconfig="${KUBECONF}" --context="${DOMAIN}" get cm cm-version -n kube-system -o "jsonpath={.data.version}")"
        set -e
        if [ "${INFRPANEL_K8S_VERSION}" != "" ]; then
          CONTROLPANEL_NEXT_VERSION=$( (echo "$INFRPANEL_K8S_VERSION + 0.01") | bc )
          CONTROLPANEL_PERMITTED_VERSIONS=( "${INFRPANEL_K8S_VERSION}" "${CONTROLPANEL_NEXT_VERSION}" )
          if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ " ${DEPLOY_CONTROLPANEL_VERSION} " ]]; then
            >&2 echo "${DEPLOY_CONTROLPANEL_VERSION} NOT permitted! Permitted version of controlpanel are ${CONTROLPANEL_PERMITTED_VERSIONS[@]}. Please check your controlpanel version.\nExiting..."
            exit 1
          else
            echo "Infrpanel checks: OK"
          fi
        fi

      done
    else
      echo "Your cluster is configured as a single node in a Federation. Are you sure to have configured correctly DynamoDB table enel_${BAMBOOENV}_ddb_platform_default_values?"
    fi
  fi
fi

CLUSTER_NAME_EXTENDED="${CUSTOMER_TAG_PARAMETER}-${GIAS_ID_NOT_DOT_TAG_PARAMETER}-${ENVIRONMENT_TAG_PARAMETER}-${CLUSTER_NAME}-Cluster"
if [ "${BAMBOOENV}" = "noprod" ]; then
  SECRET_PREFIX="noprod."
else
  SECRET_PREFIX=""
fi

if [ "${CUSTOM_KUBERNETES}" = "true" ]; then
  CLUSTER_TYPE="custom"
  if [ "${IS_FEDERATED_CLUSTER}" = "true" ]; then
    mapfile -t SECRETS_ID < <(echo "${K8S_CLUSTERS}" | jq --arg DEPLOY_AWS_ACCOUNT_ID "${DEPLOY_AWS_ACCOUNT_ID}" -r '.[] | select(.eks_clusters[] | contains($DEPLOY_AWS_ACCOUNT_ID)) | .eks_clusters[]' | sort -u -t. -k3,3)
  else
    SECRETS_ID=( "${SECRET_PREFIX}microservice.${CLOUD_PROVIDER}.${DEPLOY_AWS_ACCOUNT_ID}.${DEPLOY_AWS_REGION}.${GIAS_ID_NOT_DOT_TAG_PARAMETER,,}.${ENVIRONMENT}.${NET_KUBERNETES_TYPE}" )
  fi
else
  CLUSTER_TYPE="default"
  SECRETS_ID=( "${SECRET_PREFIX}microservice.${CLOUD_PROVIDER}.${DEPLOY_AWS_ACCOUNT_ID}.${DEPLOY_AWS_REGION}.${CLUSTER_TYPE}.${NET_KUBERNETES_TYPE}" )
fi

#TODO FIXARE IL PRIMA POSSIBILE: errore perchè l'unico cluster che condivide l'account con un altro cluster
if [ "${CLUSTER_NAME_EXTENDED}" = "Enel-AP0781106-development-core-shr-Platform-Cluster" ]; then
    SECRETS_ID=( "microservice.eks.404723859299.eu-central-1.dl00002.dev.lan" )
elif [ "${CLUSTER_NAME_EXTENDED}" = "Enel-AP31312-development-core-in-Platform-Cluster" ]; then
    SECRETS_ID=( "microservice.eks.404723859299.eu-central-1.dl00001.dev.lan" )
fi 

echo "Retrieving SECRET_ID value"
if [ "${#SECRETS_ID[@]}" -eq 1 ]; then
  SECRET_ID=${SECRETS_ID[0]}
else
  for i in $( seq 0 $((${#SECRETS_ID[@]} - 1)) ); do
    SECRET_ID=${SECRETS_ID[$i]}
    if [[ "${SECRET_ID}" == *".${DEPLOY_AWS_ACCOUNT_ID}."* ]]; then
      echo "Breaking loop"
      break
    fi
  done
fi

echo "Actual SECRET_ID: ${SECRET_ID}"

set +e
CF="$(aws cloudformation describe-stacks --stack-name "${CLOUDFORMATION_NAME}" --region="${DEPLOY_AWS_REGION}" 2>&1)"
RETURN_CODE=$?
set -e

if [ "${RETURN_CODE}" -ne 0 ] && [[ "${CF}" == *"Stack with id ${CLOUDFORMATION_NAME} does not exist"* ]]; then
  echo "Cloudformation ${CLOUDFORMATION_NAME} doesn't exist. Checking existence of cluster: ${CLUSTER_NAME_EXTENDED}"
  #GET CLUSTER INFORMATIONS
  set +e
  EKS_DESCRIPTION="$(aws eks describe-cluster --name "${CLUSTER_NAME_EXTENDED}" 2>&1)"
  RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -ne 0 ]; then 
    echo "Cluster with name ${CLUSTER_NAME_EXTENDED} doesn't exist"
    echo "OK: Cloudformation ${CLOUDFORMATION_NAME} will be created in next deploy step."
  else
    >&2 echo "KO: Cloudformation ${CLOUDFORMATION_NAME} doesn't exist but cluster ${CLUSTER_NAME_EXTENDED} exists."
    >&2 echo "Please check your params!"
    exit 1
  fi
  #CHECK IF ALREADY EXIST THE SECRET -> IF EXIST THERE IS SOME ERROR IN PLAN CONFIGURATION

  echo "Checking if secret already exists..."
  checkSecret

else 

  set +e
  EKS_DESCRIPTION="$(aws eks describe-cluster --name "${CLUSTER_NAME_EXTENDED}" 2>&1)"
  RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -eq 0 ]; then 
    set +e
    CHECK_SECRET="$(aws secretsmanager describe-secret --secret-id "${SECRET_ID,,}" --profile "${MASTER_PROFILE}" --region "${MASTER_REGION}" 2>&1)"
    RETURN_CODE=$?
    set -e

    KUBECONF="kubeconfig_token.yaml"
    DOMAIN="enelint"

    echo "Checking secret: ${SECRET_ID}"
    if [ "${RETURN_CODE}" -ne 0 ]; then
      echo "Secret doesn't exists"
      echo "Generating Kubeconfig with aws get-token command..."
      EKS_DESCRIPTION="$(aws eks describe-cluster --name "${CLUSTER_NAME_EXTENDED}" 2>&1)"
      CLUSTER_API_ENDPOINT="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.endpoint')"
      CA_DATA_B64="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.certificateAuthority.data')"
      CA_DATA_DECODED="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.certificateAuthority.data' | base64 -d)"
      
      echo "Generating Kubeconfig."
      generateKubeconfig
      echo "Kubeconfig generated."

    else
      echo "Secret already exists"
      echo "Generating actual kubeconfig"
      generateKubeconfigAdmin "${ACTUAL_KUBECONF}" "${DOMAIN}"
    fi
  fi


  if [ ${GENERATE_KUBECONFIG} = "true" ]; then

    EKS_DESCRIPTION="$(aws eks describe-cluster --name "${CLUSTER_NAME_EXTENDED}" 2>&1)"
    CLUSTER_API_ENDPOINT="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.endpoint')"
    CA_DATA_B64="$(echo "${EKS_DESCRIPTION}" | jq -r '.cluster.certificateAuthority.data')"

    echo "Generating Kubeconfig administrator for secret ${SECRET_ID}"
    cp /empty_kubeconfig.yaml kubeconfig_${CLUSTER_NAME_EXTENDED}.yaml
    sed -i -e 's/__CERTIFICATE_AUTHORITY_DATA__/'"$CA_DATA_B64"'/g' kubeconfig_${CLUSTER_NAME_EXTENDED}.yaml
    sed -i -e 's|__CLUSTER_API_ENDPOINT__|'"$CLUSTER_API_ENDPOINT"'|g' kubeconfig_${CLUSTER_NAME_EXTENDED}.yaml 
    sed -i -e 's/__TOKEN__/'"$PASS"'/g' kubeconfig_${CLUSTER_NAME_EXTENDED}.yaml
    aws secretsmanager get-secret-value --secret-id "${SECRET_ID}" --query 'SecretString' --output text --profile "${MASTER_PROFILE}" --region "${MASTER_REGION}" > secret.json

    if [[ -n $(jq -r '.kubeconfig // empty' secret.json) ]]; then
      echo "Kubeconfig already exists on secret ${SECRET_ID}"
    else 
      echo "Saving kubeconfig on secret ${SECRET_ID}"
      echo "$(cat secret.json | jq --arg field "kubeconfig" --arg value "$(cat kubeconfig_${CLUSTER_NAME_EXTENDED}.yaml)" '. + {($field): $value}')" > secret_updated.json
      #echo "UPDATE SECRET: aws secretsmanager update-secret --secret-id "${SECRET_ID}" --secret-string "$(cat secret_updated.json)"  --profile "${MASTER_PROFILE}" --region "${MASTER_REGION}""
      aws secretsmanager update-secret --secret-id "${SECRET_ID}" --secret-string "$(cat secret_updated.json)" --region "${MASTER_REGION}"
    fi

    rm -f secret*.json
    rm -f kubeconfig_${CLUSTER_NAME_EXTENDED}.yaml
  fi

  CUSTOMER_TAG_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="CustomerTagParameter") | .ParameterValue')"
  ROLE_TAG_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="RoleTagParameter") | .ParameterValue')"
  GIAS_ID_TAG_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="GiasIDTagParameter") | .ParameterValue')"
  PROJECT_TAG_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="ProjectTagParameter") | .ParameterValue')"
  VPC_ID_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="VPCIdParameter") | .ParameterValue')"
  GIAS_NAME_TAG_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="GiasNameTagParameter") | .ParameterValue')"
  RUNNING_TAG_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="RunningTagParameter") | .ParameterValue')"
  GIAS_ID_NOT_DOT_TAG_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="GiasIDNoDotTagParameter") | .ParameterValue')"
  BE_SUBNET_IDS_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="SubnetIdsParameter") | .ParameterValue')"
  ENVIRONMENT_TAG_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="EnvironmentTagParameter") | .ParameterValue')"
  BACKUP_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="BackupParameter") | .ParameterValue')"
  CLUSTER_NAME_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="ClusterName") | .ParameterValue')"
  SECURITY_GROUP_IDS_PARAMETER_CHECK="$(echo "${CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="SecurityGroupIdsParameter") | .ParameterValue')"
  
  echo "Checking before update cloudformation => CLOUDFORMATION_NAME=${CLOUDFORMATION_NAME}"

  #CHECK CONTROL PANEL VERSION WITH CURRENT CONTROL PANEL VERSION
  echo "Checking controlpanel version"
  CURRENT_CONTROLPANEL_VERSION="$(aws eks describe-cluster --name "${CUSTOMER_TAG_PARAMETER}-${GIAS_ID_NOT_DOT_TAG_PARAMETER}-${ENVIRONMENT_TAG_PARAMETER}-${CLUSTER_NAME}-Cluster" --profile "${PROJECT_PROFILE}" | jq -r '.cluster.version')"
  CONTROLPANEL_NEXT_VERSION=$( (echo "$CURRENT_CONTROLPANEL_VERSION + 0.01") | bc )
  CONTROLPANEL_PERMITTED_VERSIONS=("${CURRENT_CONTROLPANEL_VERSION}" "${CONTROLPANEL_NEXT_VERSION}")

  echo "Permitted version controlpanel: ${CONTROLPANEL_PERMITTED_VERSIONS[*]}"
  if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ ${DEPLOY_CONTROLPANEL_VERSION} ]]; then
    >&2 echo "${DEPLOY_CONTROLPANEL_VERSION} NOT permitted! Please check your controlpanel version.\nExiting..."
    exit 1
  fi

    #CHECK CONTROL PANEL VERSION WITH CURRENT DATA PANEL VERSIONS
    echo "Checking controlpanel version accross datapanel versions"
    getAutomationConfJson "datapanel"
     if [ "${PANEL_INFORMATION}" != "" ]; then
      echo "The datapanel exits, checking the versions"
      mapfile -t ALL_NODEGROUPS_NAMES_CF< <(jq -r '.nodegroups[].datapanel_cloudformation_name' "${PANEL_INFORMATION}")
      for NODEGROUP_NAME_CF in "${ALL_NODEGROUPS_NAMES_CF[@]}"; do
        set +e
        INFO_NODEGROUP_NAME_CF="$(aws cloudformation describe-stacks --stack-name "${NODEGROUP_NAME_CF}" --region="${DEPLOY_AWS_REGION}" 2>&1)"
        RETURN_CODE=$?
        set -e
        
        if [ "${RETURN_CODE}" -eq 0 ] && [[ "${INFO_NODEGROUP_NAME_CF}" != *"Stack with id ${INFO_NODEGROUP_NAME_CF} does not exist"* ]]; then
          NODEGROUP_VERSION="$(echo "${INFO_NODEGROUP_NAME_CF}" | jq -r '.Stacks[].Parameters[] | select(.ParameterKey=="NodeImageIdSSMParam") | .ParameterValue' | cut -d "/" -f6 )"
          echo "Name stack datapanel ${NODEGROUP_NAME_CF} has the version: ${NODEGROUP_VERSION}"
          CONTROLPANEL_NEXT_VERSION=$( (echo "$NODEGROUP_VERSION + 0.01") | bc )
          CONTROLPANEL_PERMITTED_VERSIONS=("${NODEGROUP_VERSION}" "${CONTROLPANEL_NEXT_VERSION}")
          if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ ${DEPLOY_CONTROLPANEL_VERSION} ]]; then
            >&2 echo "${DEPLOY_CONTROLPANEL_VERSION} NOT permitted! Please check your datapanel version.\nExiting..."
            exit 1
          fi
        else 
          echo "Stack of datapanel with name ${NODEGROUP_NAME_CF} doesn't exist"
        fi

      done
    else
      echo "The datapanel doesn't exist! No check with version necessary."
  fi

  #CHECK CONTROL PANEL VERSION WITH CURRENT INFR PANEL VERSION
  set +e
  INFRPANEL_K8S_VERSION="$(kubectl --kubeconfig="${ACTUAL_KUBECONF}" --context="${DOMAIN}" get cm cm-version -n kube-system -o "jsonpath={.data.version}")"
  RETURN_CODE=$?
  set -e
   if [ "${RETURN_CODE}" -eq 0 ]; then
    echo "Checking controlpanel version accross infrpanel version.\nInfrpanel version ${INFRPANEL_K8S_VERSION}"
    CONTROLPANEL_NEXT_VERSION=$( (echo "$INFRPANEL_K8S_VERSION + 0.01") | bc )
    CONTROLPANEL_PERMITTED_VERSIONS=( "${INFRPANEL_K8S_VERSION}" "${CONTROLPANEL_NEXT_VERSION}" )
    if [[ ! " ${CONTROLPANEL_PERMITTED_VERSIONS[*]} " =~ ${DEPLOY_CONTROLPANEL_VERSION} ]]; then
      >&2 echo "${DEPLOY_CONTROLPANEL_VERSION} NOT permitted! Please check your datapanel version.\nExiting..."
      exit 1
    fi
  else 
    echo "Control of infrpanel version not possible, the config map cm-version isn't present on cluster ${CLUSTER_NAME_EXTENDED}."
  fi


  echo "Checking Cloudformation mandatory parameters:"
  # 12 MANDATORY 
  # - CUSTOMER_TAG_PARAMETER
  # - VPC_ID_PARAMETER
  # - GIAS_ID_TAG_PARAMETER
  # - GIAS_ID_NOT_DOT_TAG_PARAMETER
  # - BE_SUBNET_IDS_PARAMETER
  # - ENVIRONMENT_TAG_PARAMETER
  # - CLUSTER_NAME
  # - SECURITY_GROUP_IDS_PARAMETER
  # - ROLE_TAG_PARAMETER
  # - PROJECT_TAG_PARAMETER
  # - GIAS_NAME_TAG_PARAMETER
  # - RUNNING_TAG_PARAMETER

  if [ "${CUSTOMER_TAG_PARAMETER}" = "${CUSTOMER_TAG_PARAMETER_CHECK}" ]; then
    echo "CUSTOMER_TAG_PARAMETER check OK: ${CUSTOMER_TAG_PARAMETER}"
  else 
    >&2 echo "CUSTOMER_TAG_PARAMETER check KO (plan_param - cf_param): ${CUSTOMER_TAG_PARAMETER} - ${CUSTOMER_TAG_PARAMETER_CHECK}"
    exit 1
  fi
  
  if [ "${VPC_ID_PARAMETER}" = "${VPC_ID_PARAMETER_CHECK}" ]; then
    echo "VPC_ID_PARAMETER check OK: ${VPC_ID_PARAMETER}"
  else 
    >&2 echo "VPC_ID_PARAMETER check KO (plan_param - cf_param): ${VPC_ID_PARAMETER} - ${VPC_ID_PARAMETER_CHECK}"
    exit 1
  fi

  if [ "${GIAS_ID_TAG_PARAMETER}" = "${GIAS_ID_TAG_PARAMETER_CHECK}" ]; then
    echo "GIAS_ID_TAG_PARAMETER check OK: ${GIAS_ID_TAG_PARAMETER}"
  else 
    >&2 echo "GIAS_ID_TAG_PARAMETER check KO (plan_param - cf_param): ${GIAS_ID_TAG_PARAMETER} - ${GIAS_ID_TAG_PARAMETER_CHECK}"
    exit 1
  fi

  if [ "${GIAS_ID_NOT_DOT_TAG_PARAMETER}" = "${GIAS_ID_NOT_DOT_TAG_PARAMETER_CHECK}" ]; then
    echo "GIAS_ID_NOT_DOT_TAG_PARAMETER check OK: ${GIAS_ID_NOT_DOT_TAG_PARAMETER}"
  else 
    >&2 echo "GIAS_ID_NOT_DOT_TAG_PARAMETER check KO (plan_param - cf_param): ${GIAS_ID_NOT_DOT_TAG_PARAMETER} -${GIAS_ID_NOT_DOT_TAG_PARAMETER_CHECK}"
    exit 1
  fi
  
  BE_SUBNET_IDS_PARAMETER_SORTED="$(echo ${BE_SUBNET_IDS_PARAMETER} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  BE_SUBNET_IDS_PARAMETER_CHECK_SORTED="$(echo ${BE_SUBNET_IDS_PARAMETER_CHECK} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  if [ "${BE_SUBNET_IDS_PARAMETER_SORTED}" =  "${BE_SUBNET_IDS_PARAMETER_CHECK_SORTED}" ]; then
    echo "BE_SUBNET_IDS_PARAMETER check OK: ${BE_SUBNET_IDS_PARAMETER}"
  else 
    >&2 echo "BE_SUBNET_IDS_PARAMETER check KO (plan_param - cf_param): ${BE_SUBNET_IDS_PARAMETER} - ${BE_SUBNET_IDS_PARAMETER_CHECK}"
    exit 1
  fi

  if [ "${ENVIRONMENT_TAG_PARAMETER}" = "${ENVIRONMENT_TAG_PARAMETER_CHECK}" ]; then
    echo "ENVIRONMENT_TAG_PARAMETER check OK: ${ENVIRONMENT_TAG_PARAMETER}"
  else 
    >&2 echo "ENVIRONMENT_TAG_PARAMETER check KO (plan_param - cf_param): ${ENVIRONMENT_TAG_PARAMETER} - ${ENVIRONMENT_TAG_PARAMETER_CHECK}"
    exit 1
  fi

  if [ "${CLUSTER_NAME}" = "${CLUSTER_NAME_CHECK}" ]; then
    echo "CLUSTER_NAME check OK: ${CLUSTER_NAME}"
  else 
    >&2 echo "CLUSTER_NAME check KO (plan_param - cf_param): ${CLUSTER_NAME} - ${CLUSTER_NAME_CHECK}"
    exit 1
  fi

  SECURITY_GROUP_IDS_PARAMETER_SORTED="$(echo ${SECURITY_GROUP_IDS_PARAMETER} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  SECURITY_GROUP_IDS_PARAMETER_CHECK_SORTED="$(echo ${SECURITY_GROUP_IDS_PARAMETER_CHECK} | tr "," "\n" | sort | tr "\n" "," | sed 's/.$//')"
  if [ "${SECURITY_GROUP_IDS_PARAMETER_SORTED}" = "${SECURITY_GROUP_IDS_PARAMETER_CHECK_SORTED}" ]; then
    echo "SECURITY_GROUP_IDS_PARAMETER check OK: ${SECURITY_GROUP_IDS_PARAMETER}"
  else 
    >&2 echo "SECURITY_GROUP_IDS_PARAMETER check KO (plan_param - cf_param): ${SECURITY_GROUP_IDS_PARAMETER} - ${SECURITY_GROUP_IDS_PARAMETER_CHECK}"
    exit 1
  fi

  if [ "${ROLE_TAG_PARAMETER}" = "${ROLE_TAG_PARAMETER_CHECK}" ]; then
    echo "ROLE_TAG_PARAMETER check OK: ${ROLE_TAG_PARAMETER}"
  else 
    >&2 echo "ROLE_TAG_PARAMETER check KO (plan_param - cf_param):  ${ROLE_TAG_PARAMETER} -  ${ROLE_TAG_PARAMETER_CHECK}"
    exit 1
  fi

  if [ "${PROJECT_TAG_PARAMETER}" = "${PROJECT_TAG_PARAMETER_CHECK}" ]; then
    echo "PROJECT_TAG_PARAMETER check OK: ${PROJECT_TAG_PARAMETER}"
  else 
    >&2 echo "PROJECT_TAG_PARAMETER check KO (plan_param - cf_param): ${PROJECT_TAG_PARAMETER} - ${PROJECT_TAG_PARAMETER_CHECK}"
    exit 1
  fi

  if [ "${GIAS_NAME_TAG_PARAMETER}" = "${GIAS_NAME_TAG_PARAMETER_CHECK}" ]; then
    echo "GIAS_NAME_TAG_PARAMETER check OK: ${GIAS_NAME_TAG_PARAMETER}"
  else 
    >&2 echo "GIAS_NAME_TAG_PARAMETER check KO (plan_param - cf_param): ${GIAS_NAME_TAG_PARAMETER} - ${GIAS_NAME_TAG_PARAMETER_CHECK}"
    exit 1
  fi

  if [ "${RUNNING_TAG_PARAMETER}" = "${RUNNING_TAG_PARAMETER_CHECK}" ]; then
    echo "RUNNING_TAG_PARAMETER check OK: ${RUNNING_TAG_PARAMETER}"
  else 
    >&2 echo "RUNNING_TAG_PARAMETER check KO (plan_param - cf_param): ${RUNNING_TAG_PARAMETER} - ${RUNNING_TAG_PARAMETER_CHECK}"
    exit 1
  fi

  echo "Checking Cloudformation not mandatory parameters:"
  #1 NOT MANDATORY
  # - BACKUP_PARAMETER

  if [ "${BACKUP_PARAMETER}" = "${BACKUP_PARAMETER_CHECK}" ]; then
    echo "BACKUP_PARAMETER check OK: ${BACKUP_PARAMETER}"
  else 
    echo "BACKUP_PARAMETER check KO (plan_param - cf_param): ${BACKUP_PARAMETER} - ${BACKUP_PARAMETER_CHECK}"
  fi

fi
