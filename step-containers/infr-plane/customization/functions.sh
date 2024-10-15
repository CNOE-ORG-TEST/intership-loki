# download automation_conf.json from repo passed as parameter
# $1 : GitHub repository where download automation_conf.json
# $2 : GitHub token
# void
function downloadAutomationConfJson(){
  curl -H "Authorization: Bearer ${2}" -L "https://raw.githubusercontent.com/${1}/main/automation_conf.json" > automation_conf_dp.json
}

# check if repo exist
# $1 : GitHub repository to check
# $2 : GitHub token
# return : string ( "true" if cluster exist, "false" otherwise )
function repoExist () {
  set +e
  git ls-remote "https://${1}:x-oauth-basic@${2}" &> /dev/null
  local RETURN_CODE=$?
  set -e
  if [ "${RETURN_CODE}" -eq 0 ]; then
    echo "true"
  else
    echo "false"
  fi
}

#parse cpu value to get it's value
# $1 : CPU value
function get_absolute_cpu_value() {
    #Parse '250m'
    k8s_cpu=$1
    if [[ ${k8s_cpu} =~ ^[0-9]*m$ ]]; then
        val_cpu=${k8s_cpu//m/}
    elif [[ ${k8s_cpu} =~ ^[0-9]*$ ]] || [[ ${k8s_cpu} =~ ^[0-9]*\.[0-9]*$ ]]; then
        val_cpu="$( (echo "${k8s_cpu} * 1000") | bc )"
    else
        val_cpu="-1"
    fi
    echo ${val_cpu}
}

#parse MEM value to get it's value
# $2 : MEM value
function get_absolute_mem_value() {
    #Parse '1G'
    k8s_mem=$1
    val_mem=0
    base_mem=$(echo "${k8s_mem}" | sed -E "s/[^0-9]//g")
    if [[ ${k8s_mem} =~ ^[0-9]*[EPTGMK]$ ]]; then
        unit_measure=$(echo "${k8s_mem//[[:blank:]]/}" | echo "${k8s_mem: -1}")
        if [[ "${unit_measure}" == "K" ]]; then
            val_mem=$(( base_mem * 1000))
        elif [[ "${unit_measure}" == "M" ]]; then
            val_mem=$(( base_mem * 1000 * 1000))
        elif [[ "${unit_measure}" == "G" ]]; then
            val_mem=$(( base_mem * 1000 * 1000 * 1000 ))
        elif [[ "${unit_measure}" == "T" ]]; then
            val_mem=$(( base_mem * 1000 * 1000 * 1000 * 1000))
        elif [[ "${unit_measure}" == "P" ]]; then
            val_mem=$(( base_mem * 1000 * 1000 * 1000 * 1000 * 1000))
        elif [[ "${unit_measure}" == "E" ]]; then
            val_mem=$(( base_mem * 1000 * 1000 * 1000 * 1000 * 1000 * 1000))
        else
            val_mem=${base_mem}
        val_mem=${base_mem//m/}
        fi
    elif [[ ${k8s_mem} =~ ^[0-9]*[EPTGMK]i$ ]]; then
        unit_measure=$(echo "${k8s_mem//[[:blank:]]/}" | echo "${k8s_mem: -2}")
        if [[ "${unit_measure}" == "Ki" ]]; then
            val_mem=$(( base_mem * 1024))
        elif [[ "${unit_measure}" == "Mi" ]]; then
            val_mem=$(( base_mem * 1024 * 1024))
        elif [[ "${unit_measure}" == "Gi" ]]; then
            val_mem=$(( base_mem * 1024 * 1024 * 1024))
        elif [[ "${unit_measure}" == "Ti" ]]; then
            val_mem=$(( base_mem * 1024 * 1024 * 1024 * 1024))
        elif [[ "${unit_measure}" == "Pi" ]]; then
            val_mem=$(( base_mem * 1024 * 1024 * 1024 * 1024 * 1024))
        elif [[ "${unit_measure}" == "Ei" ]]; then
            val_mem=$(( base_mem * 1024 * 1024 * 1024 * 1024 * 1024 * 1024))
        else
            val_mem=$(( base_mem ))
        fi
    #Parse '11092830123'
    elif [[ ${k8s_mem} =~ ^[0-9]*$ ]]; then
        val_mem=${k8s_mem}
    #Parse '1910230923m' (incorrect)
    elif [[ ${k8s_mem} =~ ^[0-9]*m$ ]]; then
        val_mem=${base_mem//m/}
    #Parse '0.2'
    elif [[ ${k8s_mem} =~ ^[0-9]*\.[0-9]*[EPTGMK]*i?$ ]]; then
       val_mem=$(( base_mem * 1000 ))
    else
        #Unexpected measurement
        val_mem=-1
    fi
    echo ${val_mem}
}