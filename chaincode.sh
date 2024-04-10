#!/bin/bash

# imports
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/utils.sh"

findAndSourceEnv $DIR

# Function to display usage instructions
usage() {
  echo "Usage: $0 <command> [options]"
  echo "Commands:"
  echo "  peers                   : Query the peers on which we can install the chaincode"
  echo "  installed <peer>        : Query installed chaincodes"
  echo "  approved <peer>         : Query approved definition of chaincode"
  echo "  committed <peer>        : Query commit definition of chaincode"
  echo "  commit-readiness <peer> : Checking commit readiness of chaincode"
  echo "  package                 : Package the chaincode"
  echo "  install <peer>          : Install the chaincode"
  echo "  approve <peer>          : Approve the chaincode"
  echo "  commit <peer>           : Commit the chaincode"
  echo "  init <peer>             : Initialize the chaincode"
  echo "  query <peer> <function_name> [args...]  : Query the chaincode example: chaincode.sh query functionName '[\"arg1\", \"arg2\"]'"
  echo "  invoke <peer> <function_name> [args...] : Invoke a transaction on the chaincode example: chaincode.sh invoke functionName '[\"arg1\", \"arg2\"]'"
  echo "Options:"
  echo "  -h, --help              : Display this help message"
  # Add more options if needed
}

getPeerId() {
  peers=$(get /peers)

  if [ -n "$1" ] && [ "$1" != "default" ]; then
    echo "$peers" | jq -r ".[] | select(.uniqueName == \"$1\") | .id"
  else
    echo "$peers" | jq -r ".[] | select(.default == true) | .id"
  fi
}

queryPeers() {
  infoln "Querying peers..."
  get "/peers" | jq -r '.[] | "Peer ID: \(.id), Name: \(.uniqueName)"'
  successln "Done"
}

queryInstalledChaincode() {
  infoln "Querying installed chaincode of ${1-default peer}..."
  peer_id=$(getPeerId $1)
  get "/installed/$peer_id" | jq -r '.[] | "Package ID: \(.package_id), Label: \(.label)"'
  successln "Done"
}

queryApprovedChaincode() {
  infoln "Querying approved chaincode definition on ${1-"default peer"}..."
  peer_id=$(getPeerId $1)
  get "/approved/$peer_id?chaincode=$CC_NAME"
  successln "Done"
}

queryCommittedChaincode() {
  infoln "Querying committed chaincode definition on ${1-"default peer"}..."
  peer_id=$(getPeerId $1)
  get "/committed/$peer_id?chaincode=$CC_NAME"
  successln "Done"
}

checkCommitReadiness() {
  infoln "Checking commit readiness on ${1-"default peer"}..."
  peer_id=$(getPeerId $1)

  if [ -n "$CC_INIT_FCN" ]; then
    init_required="true"
  else
    init_required="false"
  fi

  get "/commit-readiness/${peer_id}?chaincode=${CC_NAME}&version=${CC_VERSION}&sequence=${CC_SEQUENCE}&init_required=${init_required}"

  successln "Done"
}

compileSourceCode() {
  infoln "Compiling TypeScript code into JavaScript..."
  npm run build
  successln "Finished compiling TypeScript code into JavaScript"
}

packageChaincode() {
  infoln "Packaging chaincode ${CC_VERSION}..."
  cp ./package.json ${CC_SRC_PATH}/package.json
  set -x
  peer lifecycle chaincode package ./${CC_NAME}.tar.gz \
    --path ${CC_SRC_PATH} \
    --lang ${CC_RUNTIME_LANGUAGE} \
    --label ${CC_NAME}_${CC_VERSION} >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Chaincode packaging has failed"
  successln "Chaincode is packaged"
  rm ${CC_SRC_PATH}/package.json
}

compileAndPackageChaincode() {
  compileSourceCode
  packageChaincode
}

isChaincodeInstalled() {
  result=$(get /installed/$1 | jq -r ".[] | select(.package_id | contains(\"$2\"))")

  # Check if result is empty
  if [ -z "$result" ]; then
    return 1
  else
    return 0
  fi
}

installChaincode() {
  infoln "Installing chaincode on ${1-"default peer"}..."
  peer_id=$(getPeerId $1)

  if isChaincodeInstalled $peer_id "${CC_NAME}_${CC_VERSION}"; then
    successln "Chaincode already installed"
    exit 0
  fi

  result=$(curl -A "Chaincode lifecycle" -F "file=@./${CC_NAME}.tar.gz" -H "x-auth-token: ${BTP_SERVICE_TOKEN}" -s -w "%{http_code}" -o /dev/null ${BTP_CLUSTER_MANAGER_URL}/ide/chaincode/${BTP_SCS_ID}/install/${peer_id})

  # Check if curl command returned status code 500
  if [ "$result" -eq 500 ]; then
    errorln "Error: HTTP status code 500, exiting..."
    exit 1
  fi

  infoln "Request to install chaincode sent, will start polling to check if chaincode is installed..."

  # Set start time
  start_time=$(date +%s)

  # Define timeout duration (in seconds)
  timeout_duration=$((10 * 60)) # 10 minutes

  # Main loop to execute curl command every second
  while true; do
    # Check if timeout duration has elapsed
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    if [ $elapsed_time -ge $timeout_duration ]; then
      echo "Timeout reached, exiting..."
      exit 1
    fi

    # Call function to check packageId
    if isChaincodeInstalled $peer_id "${CC_NAME}_${CC_VERSION}"; then
      successln "Chaincode installed successfully"
      exit 0
    else
      infoln "Chaincode is not installed yet, will check again in 1 second..."
    fi

    # Sleep for 1 second
    sleep 1
  done
}

approveChaincode() {
  infoln "Approving chaincode on ${1-"default peer"}..."
  peer_id=$(getPeerId $1)

  if [ -n "$CC_INIT_FCN" ]; then
    init_required="true"
  else
    init_required="false"
  fi

  post /approve/$peer_id "{\"chaincodeName\": \"$CC_NAME\", \"chaincodeVersion\": \"$CC_VERSION\", \"chaincodeSequence\": $CC_SEQUENCE, \"initRequired\": $init_required}"
  successln "Done"
}

isChaincodeCommitted() {
  response=$(get /committed/$1?chaincode=$CC_NAME)

  result=$(echo "$response" | jq ".sequence == $CC_SEQUENCE and .version == \"$CC_VERSION\"")

  if [ "$result" == "true" ]; then
    return 0
  else
    return 1
  fi
}

commitChaincode() {
  infoln "Committing chaincode on ${1-"default peer"}..."
  peer_id=$(getPeerId $1)

  if isChaincodeCommitted $peer_id; then
    successln "Chaincode already committed"
    exit 0
  fi

  if [ -n "$CC_INIT_FCN" ]; then
    init_required="true"
  else
    init_required="false"
  fi

  post /commit/$peer_id "{\"chaincodeName\": \"$CC_NAME\", \"chaincodeVersion\": \"$CC_VERSION\", \"chaincodeSequence\": $CC_SEQUENCE, \"initRequired\": $init_required}"

  infoln "Request to commit chaincode sent, will start polling to check if chaincode is committed..."

  # Set start time
  start_time=$(date +%s)

  # Define timeout duration (in seconds)
  timeout_duration=$((10 * 60)) # 10 minutes

  # Main loop to execute curl command every second
  while true; do
    # Check if timeout duration has elapsed
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    if [ $elapsed_time -ge $timeout_duration ]; then
      echo "Timeout reached, exiting..."
      exit 1
    fi

    # Call function to check packageId
    if isChaincodeCommitted $peer_id; then
      successln "Chaincode committed successfully"
      exit 0
    else
      infoln "Chaincode is not committed yet, will check again in 1 second..."
    fi

    # Sleep for 1 second
    sleep 1
  done
}

initChaincode() {
  infoln "Initializing chaincode on ${1-"default peer"}..."

  if [ -z "$CC_INIT_FCN" ]; then
    warnln "No CC_INIT_FCN function specified, skipping chaincode initialization."
  fi

  peer_id=$(getPeerId $1)

  post /init/$peer_id "{\"chaincodeName\": \"$CC_NAME\", \"functionName\": \"$CC_INIT_FCN\", \"functionArgs\": ${CC_INIT_ARGS:-[]}}"

  successln "done"
}

invokeChaincode() {
  infoln "Invoking chaincode on ${1-"default peer"} for $2 with $3..."

  peer_id=$(getPeerId $1)

  post /invoke/$peer_id '{"chaincodeName": "'$CC_NAME'", "functionName": "'$2'", "functionArgs": '${3:-[]}'}'

  successln "done"
}

queryChaincode() {
  infoln "Querying chaincode on ${1-"default peer"} for $2 with $3..."

  input=$3

  if [[ -n $input && $input != \[* && $input != *\] ]]; then
    function_args="&function_args[]=$input"
  elif [[ -n $input && $input != '[]' ]]; then
    delimiter="|"

    # Remove brackets and quotes
    input="${input//[\"/}"
    input="${input//\"]/}"

    # Replace commas between quotes with a different delimiter
    input="${input//\",\"/$delimiter}"

    # Replace delimiter with '&function_args[]='
    input="${input//$delimiter/\&function_args[]=}"

    # Add 'function_args[]=' to the beginning
    function_args="&function_args[]=$input"
  else
    function_args=""
  fi

  peer_id=$(getPeerId $1)

  get "/query/$peer_id?chaincode=$CC_NAME&function_name=${2}${function_args}"

  successln "done"
}

# Main function to parse arguments and execute commands
main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  case $1 in
  peers)
    validateEnvVariables
    queryPeers
    ;;
  installed)
    validateEnvVariables
    queryInstalledChaincode $2
    ;;
  approved)
    validateEnvVariables
    queryApprovedChaincode $2
    ;;
  committed)
    validateEnvVariables
    queryCommittedChaincode $2
    ;;
  commit-readiness)
    validateEnvVariables
    checkCommitReadiness $2
    ;;
  package)
    validateEnvVariables
    compileAndPackageChaincode
    ;;
  install)
    validateEnvVariables
    installChaincode $2
    ;;
  approve)
    validateEnvVariables
    approveChaincode $2
    ;;
  commit)
    validateEnvVariables
    commitChaincode $2
    ;;
  init)
    validateEnvVariables
    initChaincode $2
    ;;
  invoke)
    validateEnvVariables
    if [ $# -eq 3 ]; then
      invokeChaincode "default" $2 $3
    elif [ $# -eq 4 ]; then
      invokeChaincode "default" $2 $3 $4
    else
      echo "Error: Incorrect number of arguments provided, at least function name and arguments must be provided"
      return 1
    fi
    ;;
  query)
    validateEnvVariables
    if [ $# -eq 3 ]; then
      queryChaincode "default" $2 $3
    elif [ $# -eq 4 ]; then
      queryChaincode "default" $2 $3 $4
    else
      echo "Error: Incorrect number of arguments provided, at least function name and arguments must be provided"
      return 1
    fi
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    echo "Error: Invalid command '$1'"
    usage
    exit 1
    ;;
  esac
}

# Call the main function with command line arguments
main "$@"
