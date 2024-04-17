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
  echo "  orderers                : Query the orderers"
  echo "  nodes                   : Query all the nodes"
  echo "  channels                : Query the channels"
  echo "  installed <peer>        : Query installed chaincodes"
  echo "  approved <peer>         : Query approved definition of chaincode"
  echo "  committed <peer>        : Query commit definition of chaincode"
  echo "  commit-readiness <peer> : Checking commit readiness of chaincode"
  echo "  package                 : Package the chaincode"
  echo "  install <peer>          : Install the chaincode"
  echo "  approve <peer>          : Approve the chaincode"
  echo "  commit <peer>           : Commit the chaincode"
  echo "  init <peer>             : Initialize the chaincode"
  echo "  query <peer> <function_name> [args...]         : Query the chaincode."
  echo "    Example: chaincode.sh query functionName '[\"arg1\", \"arg2\"]'"
  echo "  invoke <peer> <function_name> [args...]        : Invoke a transaction on the chaincode."
  echo "    Example: chaincode.sh invoke functionName '[\"arg1\", \"arg2\"]'"
  echo "  create-channel <channel_name> [options]        : Create a channel with the given name and options"
  echo "    Options:"
  echo "      --endorsementPolicy <MAJORITY|ALL>         : Endorsement policy for the channel (default: MAJORITY)"
  echo "      --batchTimeoutInSeconds <seconds>          : Batch timeout in seconds (default: 2)"
  echo "      --maxMessageCount <count>                  : Maximum message count (default: 500)"
  echo "      --absoluteMaxMB <MB>                       : Absolute maximum bytes (default: 10)"
  echo "      --preferredMaxMB <MB>                      : Preferred maximum bytes (default: 2)"
  echo "  orderer-join-channel <orderer> <channel_name>  : Orderer joins a channel."
  echo "  orderer-leave-channel <orderer> <channel_name> : Orderer leaves a channel."
  echo "  peer-join-channel <peer> <channel_name>        : Peer joins a channel."
  echo "  peer-leave-channel <peer> <channel_name>       : Peer leaves a channel."
  echo "Options:"
  echo "  -h, --help              : Display this help message"
  # Add more options if needed
}

getNodeId() {
  nodes=$(get /nodes)

  if [ -n "$1" ] && [ "$1" != "default" ]; then
    echo "$nodes" | jq -r ".[] | select(.uniqueName == \"$1\") | .id"
  else
    echo "$nodes" | jq -r ".[] | select(.default == true and .type == \"${2-"orderer"}\") | .id"
  fi
}

getPeerId() {
  peers=$(get /peers)

  if [ -n "$1" ] && [ "$1" != "default" ]; then
    echo "$peers" | jq -r ".[] | select(.uniqueName == \"$1\") | .id"
  else
    echo "$peers" | jq -r ".[] | select(.default == true) | .id"
  fi
}

getOrdererId() {
  orderers=$(get /orderers)

  if [ -n "$1" ] && [ "$1" != "default" ]; then
    echo "$orderers" | jq -r ".[] | select(.uniqueName == \"$1\") | .id"
  else
    echo "$orderers" | jq -r ".[] | select(.default == true) | .id"
  fi
}

queryNodes() {
  infoln "Querying nodes..."
  get "/nodes" | jq -r '.[] | "Node ID: \(.id), Name: \(.uniqueName), Type: \(.type), Default: \(.default)"'
  successln "Done"
}

queryPeers() {
  infoln "Querying peers..."
  get "/peers" | jq -r '.[] | "Peer ID: \(.id), Name: \(.uniqueName), Default: \(.default)"'
  successln "Done"
}

queryOrderers() {
  infoln "Querying orderers..."
  get "/orderers" | jq -r '.[] | "Orderer ID: \(.id), Name: \(.uniqueName), Default: \(.default)"'
  successln "Done"
}

queryChannels() {
  infoln "Querying channels for ${1-"default orderer"}..."
  node_id=$(getNodeId $1 "orderer")
  get "/channels?node=$node_id" | jq -r '.[] | "Channel Name: \(.)"'
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

  if [ -n "$CC_COLLECTIONS_CONFIG_PATH" ]; then
    post /commit-readiness/$peer_id "{\"chaincodeName\": \"$CC_NAME\", \"chaincodeVersion\": \"$CC_VERSION\", \"chaincodeSequence\": $CC_SEQUENCE, \"initRequired\": $init_required, \"collectionsConfig\": $(cat ${CC_COLLECTIONS_CONFIG_PATH})}"
  else
    get "/commit-readiness/${peer_id}?chaincode=${CC_NAME}&version=${CC_VERSION}&sequence=${CC_SEQUENCE}&init_required=${init_required}"
  fi

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

  if [ -n "$CC_COLLECTIONS_CONFIG_PATH" ]; then
    collections_config=", \"collectionsConfig\": $(cat ${CC_COLLECTIONS_CONFIG_PATH})"
  else
    collections_config=""
  fi

  post /approve/$peer_id "{\"chaincodeName\": \"$CC_NAME\", \"chaincodeVersion\": \"$CC_VERSION\", \"chaincodeSequence\": $CC_SEQUENCE, \"initRequired\": ${init_required}${collections_config}}"
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

  if [ -n "$CC_COLLECTIONS_CONFIG_PATH" ]; then
    collections_config=", \"collectionsConfig\": $(cat ${CC_COLLECTIONS_CONFIG_PATH})"
  else
    collections_config=""
  fi

  post /commit/$peer_id "{\"chaincodeName\": \"$CC_NAME\", \"chaincodeVersion\": \"$CC_VERSION\", \"chaincodeSequence\": $CC_SEQUENCE, \"initRequired\": ${init_required}${collections_config}}"

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

createChannel() {
  # Default values
  endorsement_policy=MAJORITY
  batch_timeout_seconds=2 # seconds
  max_message_count=500
  absolute_max_mb=10 # MB
  preferred_max_mb=2 # MB

  # Parse command line arguments
  channel_name="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case $1 in
    --endorsementPolicy)
      endorsement_policy="$2"
      shift 2
      ;;
    --batchTimeoutInSeconds)
      batch_timeout_seconds="$2"
      shift 2
      ;;
    --maxMessageCount)
      max_message_count="$2"
      shift 2
      ;;
    --absoluteMaxMB)
      absolute_max_mb="$2"
      shift 2
      ;;
    --preferredMaxMB)
      preferred_max_mb="$2"
      shift 2
      ;;
    *)
      errorln "Unknown option: $1"
      return 1
      ;;
    esac
  done

  # Validation
  if [ -z "$channel_name" ]; then
    fatalln "Channel name is required."
  fi

  if [ "$endorsement_policy" != "MAJORITY" ] && [ "$endorsement_policy" != "ALL" ]; then
    fatalln "Endorsement policy must be either 'MAJORITY' or 'ALL', found '${endorsement_policy}'."
  fi

  if ! [[ "$batch_timeout_seconds" =~ ^[0-9]+$ ]]; then
    fatalln "Batch timeout must be a number, found '${batch_timeout_seconds}'."
  fi

  if ! [[ "$max_message_count" =~ ^[0-9]+$ ]]; then
    fatalln "Max message count must be a number, found '${max_message_count}'."
  fi

  if ! [[ "$absolute_max_mb" =~ ^[0-9]+$ ]]; then
    fatalln "Absolute max bytes must be a number, found '${absolute_max_mb}'."
  fi

  if ! [[ "$preferred_max_mb" =~ ^[0-9]+$ ]]; then
    fatalln "Preferred max bytes must be a number, found '${preferred_max_mb}'."
  fi

  infoln "Creating channel ${channel_name} with configuration [endorsement_policy=${endorsement_policy}, batch_timeout_seconds=${batch_timeout_seconds}, max_message_count=${max_message_count}, absolute_max_mb=${absolute_max_mb}, preferred_max_mb=${preferred_max_mb}]..."

  post /channels '{"name": "'$channel_name'", "endorsementPolicy": "'$endorsement_policy'", "batchTimeoutSeconds": '$batch_timeout_seconds', "maxMessageCount": '$max_message_count', "absoluteMaxMB": '$absolute_max_mb', "preferredMaxMB": '$preferred_max_mb'}'

  successln "done"
}

ordererJoinChannel() {
  infoln "Orderer ${1} joining channel ${2}..."
  orderer_id=$(getOrdererId $1)
  post /channels/${2}/nodes '{"nodeId": "'$orderer_id'"}'
  successln "done"
}

peerJoinChannel() {
  infoln "Peer ${1} joining channel ${2}..."
  peer_id=$(getPeerId $1)
  post /channels/${2}/nodes '{"nodeId": "'$peer_id'"}'
  successln "done"
}

ordererLeaveChannel() {
  infoln "Orderer ${1} leaving channel ${2}..."
  orderer_id=$(getOrdererId $1)
  delete /channels/${2}/nodes/${orderer_id}
  successln "done"
}

peerLeaveChannel() {
  infoln "Peer ${1} leaving channel ${2}..."
  peer_id=$(getPeerId $1)
  delete /channels/${2}/nodes/${peer_id}
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
  orderers)
    validateEnvVariables
    queryOrderers
    ;;
  channels)
    validateEnvVariables
    queryChannels
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
  create-channel)
    validateEnvVariables
    createChannel "${@:2}"
    ;;
  orderer-join-channel)
    validateEnvVariables
    ordererJoinChannel $2 $3
    ;;
  peer-join-channel)
    validateEnvVariables
    peerJoinChannel $2 $3
    ;;
  orderer-leave-channel)
    validateEnvVariables
    ordererLeaveChannel $2 $3
    ;;
  peer-leave-channel)
    validateEnvVariables
    peerLeaveChannel $2 $3
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
