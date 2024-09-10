# download automation_conf.json from repo passed as parameter
# $1 : GitHub repository where download automation_conf.json
# $2 : GitHub token
# void
function downloadAutomationConfJson(){
  curl -H "Authorization: Bearer ${2}" -L "https://raw.githubusercontent.com/${1}/main/automation_conf.json" > automation_conf.json
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