#!/bin/bash

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_YELLOW='\033[1;33m'

validateEnvVariables() {
  println "executing from ${DIR} with the following"
  println "- BTP_CLUSTER_MANAGER_URL: ${C_GREEN}${BTP_CLUSTER_MANAGER_URL}${C_RESET}"
  println "- BTP_SERVICE_TOKEN: ${C_GREEN}${BTP_SERVICE_TOKEN}${C_RESET}"
  println "- BTP_SCS_ID: ${C_GREEN}${BTP_SCS_ID}${C_RESET}"
  println "- CC_RUNTIME_LANGUAGE: ${C_GREEN}${CC_RUNTIME_LANGUAGE}${C_RESET}"
  println "- CC_SRC_PATH: ${C_GREEN}${CC_SRC_PATH}${C_RESET}"
  println "- CC_NAME: ${C_GREEN}${CC_NAME}${C_RESET}"
  println "- CC_VERSION: ${C_GREEN}${CC_VERSION}${C_RESET}"
  println "- CC_SEQUENCE: ${C_GREEN}${CC_SEQUENCE}${C_RESET}"
  println "- CC_INIT_FCN: ${C_GREEN}${CC_INIT_FCN}${C_RESET}"
  println ""

  if [ -z "$BTP_CLUSTER_MANAGER_URL" ]; then
    fatalln "No cluster manager url was provided. Please provide it in the environment variable BTP_CLUSTER_MANAGER_URL."
  fi

  if [ -z "$BTP_SERVICE_TOKEN" ]; then
    fatalln "No cluster manager service token was provided. Please provide it in the environment variable BTP_SERVICE_TOKEN."
  fi

  if [ -z "$BTP_SCS_ID" ]; then
    fatalln "No smart contract set id was provided. Please provide it in the environment variable BTP_SCS_ID."
  fi

  # User has not provided a name
  if [ -z "$CC_NAME" ] || [ "$CC_NAME" = "NA" ]; then
    fatalln "No chaincode name was provided. Please provide it in the environment variable CC_NAME"

  # User has not provided a path
  elif [ -z "$CC_SRC_PATH" ] || [ "$CC_SRC_PATH" = "NA" ]; then
    fatalln "No chaincode path was provided. Please provide it in the environment variable CC_SRC_PATH"
  fi

  if [ "$CC_RUNTIME_LANGUAGE" != "golang" ] && [ "$CC_RUNTIME_LANGUAGE" != "node" ]; then
    fatalln "The chaincode language ${CC_RUNTIME_LANGUAGE} is not supported by this script. Supported chaincode language is go or node"
  fi
}

get() {
  curl -A "Chaincode lifecycle" -H "x-auth-token: ${BTP_SERVICE_TOKEN}" -s ${BTP_CLUSTER_MANAGER_URL}/ide/chaincode/${BTP_SCS_ID}$1
}

post() {
  curl -A "Chaincode lifecycle" -H "x-auth-token: ${BTP_SERVICE_TOKEN}" -H "Content-Type: application/json" -s -X POST -d "$2" ${BTP_CLUSTER_MANAGER_URL}/ide/chaincode/${BTP_SCS_ID}$1
}

findAndSourceEnv() {
  dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.env" ]; then
      echo "Sourcing .env file: $dir/.env"
      source "$dir/.env"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  echo "No .env file found in parent directories."
  return 1
}

# println echos string
function println() {
  echo -e "$1"
}

# errorln echos in red color
function errorln() {
  println "${C_RED}${1}${C_RESET}"
}

# successln echos in green color
function successln() {
  println "${C_GREEN}${1}${C_RESET}"
}

# infoln echos in blue color
function infoln() {
  println "${C_BLUE}${1}${C_RESET}"
}

# warnln echos in yellow color
function warnln() {
  println "${C_YELLOW}${1}${C_RESET}"
}

# fatalln echos in red color and exits with fail status
function fatalln() {
  errorln "$1"
  exit 1
}

verifyResult() {
  if [ $1 -ne 0 ]; then
    fatalln "$2"
  fi
}
