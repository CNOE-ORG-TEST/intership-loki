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
  local CODE=$(curl -H "Authorization: Bearer ${2}" -s -o /dev/null -w "%{http_code}" "https://raw.githubusercontent.com/${1}/main/automation_conf.json")
  if [[ "${CODE}" == *"200"* ]]; then
    echo "true"
  else
    echo "false"
  fi
}