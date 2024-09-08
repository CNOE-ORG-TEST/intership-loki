function colorEcho(){
  if [ "${1}" = "error" ]; then
    echo -e "\033[31mError: ${2}\033[0m"
  elif [ "${1}" = "warning" ]; then
    echo -e "\033[33mWarning: ${2}\033[0m"
  elif [ "${1}" = "red" ]; then
    echo -e "\033[31m${2}\033[0m"
  elif [ "${1}" = "yellow" ]; then
    echo -e "\033[33m${2}\033[0m"
  else
    echo "${@}"
  fi
}