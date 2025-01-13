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
  echo "  peers <application_name>           : Query the peers (defaults to the application of this smart contract set)"
  echo "  orderers <application_name>        : Query the orderers (defaults to the application of this smart contract set)"
  echo "  nodes <application_name>           : Query all the nodes (defaults to the application of this smart contract set)"
  echo "  orderer-channels <orderer>         : Query the channels of the orderer"
  echo "  peer-channels <peer>               : Query the channels of the peer"
  echo "  installed <peer>                   : Query installed chaincodes"
  echo "  approved <peer>                    : Query approved definition of chaincode"
  echo "  committed <peer>                   : Query commit definition of chaincode"
  echo "  commit-readiness <peer>            : Checking commit readiness of chaincode"
  echo "  package                            : Package the chaincode"
  echo "  install <peer>                     : Install the chaincode"
  echo "  approve <peer> <orderer>           : Approve the chaincode"
  echo "  commit <peer> <orderer>            : Commit the chaincode"
  echo "  init <peer> <orderer>              : Initialize the chaincode"
  echo "  query <peer> <function_name> [options]                   : Query the chaincode."
  echo "    Options:"
  echo "      --arguments '[\"arg1\", \"arg2\"]'                   : The regular arguments to pass to the function." 
  echo "      --channel <channel_name>                             : Optionally override the channel name."
  echo "  Example: chaincode.sh query functionName --arguments '[\"arg1\", \"arg2\"]'"
  echo "  invoke <peer> <orderer> <function_name> [options]        : Invoke a transaction on the chaincode."
  echo "    Options:"
  echo "      --arguments '[\"arg1\", \"arg2\"]'                   : The regular arguments to pass to the function."
  echo "      --transient '{\"key\": \"value\"}'                   : The transient data to pass the to the function."
  echo "      --channel <channel_name>                             : Optionally override the channel name."
  echo "    Example: chaincode.sh invoke functionName '[\"arg1\", \"arg2\"]'"
  echo "  create-channel <orderer> <channel_name> [options]        : Create a channel with the given name and options"
  echo "    Options:"
  echo "      --endorsementPolicy <MAJORITY|ALL>                   : Endorsement policy for the channel (default: MAJORITY)"
  echo "      --batchTimeoutInSeconds <seconds>                    : Batch timeout in seconds (default: 2)"
  echo "      --maxMessageCount <count>                            : Maximum message count (default: 500)"
  echo "      --absoluteMaxMB <MB>                                 : Absolute maximum bytes (default: 10)"
  echo "      --preferredMaxMB <MB>                                : Preferred maximum bytes (default: 2)"
  echo "  orderer-join-channel <orderer> <channel_name>            : Orderer joins a channel."
  echo "  orderer-leave-channel <orderer> <channel_name>           : Orderer leaves a channel."
  echo "  peer-join-channel <peer> <channel_name>                  : Peer joins a channel."
  echo "  peer-leave-channel <peer> <channel_name>                 : Peer leaves a channel."
  echo "Options:"
  echo "  -h, --help                         : Display this help message"
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
  app_name=${1:-$SETTLEMINT_APPLICATION}
  if [ -z "$app_name" ]; then
    fatalln "Application name not provided and SETTLEMINT_APPLICATION not set"
  fi

  infoln "Querying nodes for application '$app_name'..."
  response=$(getApplicationData "/$app_name/nodes")
  jqFormatOrError "$response" '.[] | "Node ID: \(.id), Name: \(.uniqueName), Type: \(.type), MSP Id: \(.mspId)"'
  successln "Done"
}

queryPeers() {
  app_name=${1:-$SETTLEMINT_APPLICATION}
  if [ -z "$app_name" ]; then
    fatalln "Application name not provided and SETTLEMINT_APPLICATION not set"
  fi

  infoln "Querying peers for application '$app_name'..."
  response=$(getApplicationData "/$app_name/peers")
  jqFormatOrError "$response" '.[] | "Peer ID: \(.id), Name: \(.uniqueName), MSP Id: \(.mspId)"'
  successln "Done"
}

queryOrderers() {
  app_name=${1:-$SETTLEMINT_APPLICATION}
  if [ -z "$app_name" ]; then
    fatalln "Application name not provided and SETTLEMINT_APPLICATION not set"
  fi

  infoln "Querying orderers for application '$app_name'..."
  response=$(getApplicationData "/$app_name/orderers")
  jqFormatOrError "$response" '.[] | "Orderer ID: \(.id), Name: \(.uniqueName), MSP Id: \(.mspId)"'
  successln "Done"
}

queryOrdererChannels() {
  infoln "Querying channels for orderer ${1}..."
  echo "Channel names orderer is a member of:"
  response=$(getChannelData "/nodes/$1")
  echo "$response"
  successln "Done"
}

queryPeerChannels() {
  infoln "Querying channels for ${1}..."
  echo "Channel names peer has joined: (Note: this is not the same as the channels the peer is a member of, since the peer could have left some channels)"
  response=$(getChannelData "/nodes/$1")
  echo "$response"
  successln "Done"
}

queryInstalledChaincode() {
  infoln "Querying installed chaincode of ${1}..."
  response=$(getChaincodeData "/installed/peers/$1")
  jqFormatOrError "$response" '.[] | "Package ID: \(.package_id), Label: \(.label)"'
  successln "Done"
}

queryApprovedChaincode() {
  infoln "Querying approved chaincode definition on ${1-"default peer"} for channel ${CC_CHANNEL-"default channel"}..."
  if [ -n "$CC_CHANNEL" ]; then
    channel_name="&channel=$CC_CHANNEL"
  else
    channel_name=""
  fi
  getChaincodeData "/approved/peers/$1?chaincode=${CC_NAME}${channel_name}"
  successln "Done"
}

queryCommittedChaincode() {
  infoln "Querying committed chaincode definition on ${1-"default peer"} for channel ${CC_CHANNEL-"default channel"}..."
  if [ -n "$CC_CHANNEL" ]; then
    channel_name="&channel=$CC_CHANNEL"
  else
    channel_name=""
  fi
  getChaincodeData "/committed/peers/$1?chaincode=${CC_NAME}${channel_name}"
  successln "Done"
}

checkCommitReadiness() {
  infoln "Checking commit readiness on ${1-"default peer"} for channel ${CC_CHANNEL-"default channel"}..."
  if [ -n "$CC_INIT_FCN" ]; then
    init_required="true"
  else
    init_required="false"
  fi

  if [ -n "$CC_COLLECTIONS_CONFIG_PATH" ] || [ -n "$CC_SIGNATURE_POLICY" ]; then
    if [ -n "$CC_SIGNATURE_POLICY" ]; then
      signature_policy=", \"signaturePolicy\": \"$CC_SIGNATURE_POLICY\""
    else
      signature_policy=""
    fi
    if [ -n "$CC_CHANNEL" ]; then
      channel_name=", \"channelName\": \"$CC_CHANNEL\""
    else
      channel_name=""
    fi

    if [ -n "$CC_COLLECTIONS_CONFIG_PATH" ]; then
      # if i don't do it this way collection config might get evaluated too early and we don't sent valid json
      postChaincodeData "/commit-readiness/peers/$1" "{\"chaincodeName\": \"$CC_NAME\", \"chaincodeVersion\": \"$CC_VERSION\", \"chaincodeSequence\": $CC_SEQUENCE, \"initRequired\": $init_required, \"collectionsConfig\": $(cat ${CC_COLLECTIONS_CONFIG_PATH} | tr -d '\n')${channel_name}${signature_policy}}"
    else
      postChaincodeData "/commit-readiness/peers/$1" "{\"chaincodeName\": \"$CC_NAME\", \"chaincodeVersion\": \"$CC_VERSION\", \"chaincodeSequence\": $CC_SEQUENCE, \"initRequired\": ${init_required}${channel_name}${signature_policy}}"
    fi
  else
    if [ -n "$CC_CHANNEL" ]; then
      channel_name="&channel=$CC_CHANNEL"
    else
      channel_name=""
    fi
    getChaincodeData "/commit-readiness/peers/$1?chaincode=${CC_NAME}&version=${CC_VERSION}&sequence=${CC_SEQUENCE}&init_required=${init_required}${channel_name}"
  fi

  successln "Done"
}

compileSourceCode() {
  if [ "$CC_RUNTIME_LANGUAGE" = "golang" ]; then
    infoln "Vendoring Go dependencies at $CC_SRC_PATH"
    pushd $CC_SRC_PATH
    go mod vendor
    popd
    successln "Finished vendoring Go dependencies"
  elif [ "$CC_RUNTIME_LANGUAGE" = "node" ]; then
    infoln "Compiling TypeScript code into JavaScript..."
    npm run build
    successln "Finished compiling TypeScript code into JavaScript"
  fi
}

packageChaincode() {
  infoln "Packaging chaincode ${CC_VERSION}..."
  if [ -f ./package.json ]; then
    cp ./package.json ${CC_SRC_PATH}/package.json
  fi
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
  if [ -f ${CC_SRC_PATH}/package.json ]; then
    rm ${CC_SRC_PATH}/package.json
  fi
}

compileAndPackageChaincode() {
  compileSourceCode
  packageChaincode
}

isChaincodeInstalled() {
  result=$(getChaincodeData "/installed/peers/$1" | jq -r ".[] | select(.package_id | contains(\"$2\"))")

  # Check if result is empty
  if [ -z "$result" ]; then
    return 1
  else
    return 0
  fi
}

installChaincode() {
  infoln "Installing chaincode on ${1}..."

  if isChaincodeInstalled $1 "${CC_NAME}_${CC_VERSION}"; then
    successln "Chaincode already installed"
    exit 0
  fi

  result=$(curl -A "Chaincode lifecycle" -F "file=@./${CC_NAME}.tar.gz" \
    -H "x-auth-token: ${BTP_SERVICE_TOKEN}" \
    -s -w "%{http_code}" -o /dev/null \
    "${BTP_CLUSTER_MANAGER_URL}/chaincodes/install/peers/$1")

  # 408 and 504 are timeout errors, so we should start polling
  if [ "$result" -ge 400 ] && [ "$result" -ne 408 ] && [ "$result" -ne 504 ]; then
    fatalln "Request failed with HTTP status code $result"
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
    if isChaincodeInstalled $1 "${CC_NAME}_${CC_VERSION}"; then
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
  infoln "Approving chaincode on peer ${1} to be committed on orderer ${2} for channel ${CC_CHANNEL-"default channel"}..."
  peer_unique_name=$1
  orderer_unique_name=$2

  if [ -n "$CC_INIT_FCN" ]; then
    init_required="true"
  else
    init_required="false"
  fi

  if [ -n "$CC_COLLECTIONS_CONFIG_PATH" ]; then
    collections_config=", \"collectionsConfig\": $(cat ${CC_COLLECTIONS_CONFIG_PATH} | tr -d '\n')"
  else
    collections_config=""
  fi

  if [ -n "$CC_SIGNATURE_POLICY" ]; then
    signature_policy=", \"signaturePolicy\": \"$CC_SIGNATURE_POLICY\""
  else
    signature_policy=""
  fi

  if [ -n "$CC_CHANNEL" ]; then
    channel_name=", \"channelName\": \"$CC_CHANNEL\""
  else
    channel_name=""
  fi

  postChaincodeData "/approve" "{\"ordererUniqueName\": \"$orderer_unique_name\", \"peerUniqueName\": \"$peer_unique_name\", \"chaincodeName\": \"$CC_NAME\", \"chaincodeVersion\": \"$CC_VERSION\", \"chaincodeSequence\": $CC_SEQUENCE, \"initRequired\": ${init_required}${collections_config}${signature_policy}${channel_name}}"
  successln "Done"
}

isChaincodeCommitted() {
  if [ -n "$CC_CHANNEL" ]; then
    channel_name="&channel=$CC_CHANNEL"
  else
    channel_name=""
  fi

  response=$(getChaincodeData "/committed/peers/$1?chaincode=${CC_NAME}${channel_name}")

  result=$(echo "$response" | jq ".sequence == $CC_SEQUENCE and .version == \"$CC_VERSION\"")

  if [ "$result" == "true" ]; then
    return 0
  else
    return 1
  fi
}

commitChaincode() {
  infoln "Committing chaincode on peer ${1} to orderer ${2} for channel ${CC_CHANNEL-"default channel"}..."
  peer_unique_name=$1
  orderer_unique_name=$2

  if isChaincodeCommitted $peer_unique_name; then
    successln "Chaincode already committed"
    exit 0
  fi

  if [ -n "$CC_INIT_FCN" ]; then
    init_required="true"
  else
    init_required="false"
  fi

  if [ -n "$CC_COLLECTIONS_CONFIG_PATH" ]; then
    collections_config=", \"collectionsConfig\": $(cat ${CC_COLLECTIONS_CONFIG_PATH} | tr -d '\n')"
  else
    collections_config=""
  fi

  if [ -n "$CC_SIGNATURE_POLICY" ]; then
    signature_policy=", \"signaturePolicy\": \"$CC_SIGNATURE_POLICY\""
  else
    signature_policy=""
  fi

  if [ -n "$CC_CHANNEL" ]; then
    channel_name=", \"channelName\": \"$CC_CHANNEL\""
  else
    channel_name=""
  fi

  postChaincodeData "/commit" "{\"ordererUniqueName\": \"$orderer_unique_name\", \"peerUniqueName\": \"$peer_unique_name\", \"chaincodeName\": \"$CC_NAME\", \"chaincodeVersion\": \"$CC_VERSION\", \"chaincodeSequence\": $CC_SEQUENCE, \"initRequired\": ${init_required}${collections_config}${signature_policy}${channel_name}}"

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
    if isChaincodeCommitted $peer_unique_name; then
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
  infoln "Initializing chaincode on peer ${1} to orderer ${2} on channel ${CC_CHANNEL-"default channel"}..."

  if [ -z "$CC_INIT_FCN" ]; then
    warnln "No CC_INIT_FCN function specified, skipping chaincode initialization."
    exit 0
  fi

  peer_unique_name=$1
  orderer_unique_name=$2

  if [ -n "$CC_CHANNEL" ]; then
    postChaincodeData "/init" "{\"ordererUniqueName\": \"$orderer_unique_name\", \"peerUniqueName\": \"$peer_unique_name\", \"chaincodeName\": \"$CC_NAME\", \"channelName\": \"$CC_CHANNEL\", \"functionName\": \"$CC_INIT_FCN\", \"functionArgs\": ${CC_INIT_ARGS:-[]}${channel_name}}"
  else
    postChaincodeData "/init" "{\"ordererUniqueName\": \"$orderer_unique_name\", \"peerUniqueName\": \"$peer_unique_name\", \"chaincodeName\": \"$CC_NAME\", \"functionName\": \"$CC_INIT_FCN\", \"functionArgs\": ${CC_INIT_ARGS:-[]}}"
  fi

  successln "done"
}

invokeChaincode() {
  channel=$CC_CHANNEL

  peer_unique_name=$1
  orderer_unique_name=$2
  function_name=$3
  shift 3

  while [[ $# -gt 0 ]]; do
    case $1 in
    --arguments)
      arguments="$2"
      shift 2
      ;;
    --transient)
      transient="$2"
      shift 2
      ;;
    --channel)
      channel="$2"
      shift 2
      ;;
    *)
      fatalln "Unknown option: $1"
      ;;
    esac
  done

  infoln "Invoking chaincode on peer $peer_unique_name to orderer $orderer_unique_name for $function_name with ${arguments-"NO ARGUMENTS"} and transient data ${transient-"NONE"} on channel ${channel-"default channel"}..."

  # Construct the JSON payload
  json_payload='{"ordererUniqueName": "'$orderer_unique_name'", "peerUniqueName": "'$peer_unique_name'", "chaincodeName": "'$CC_NAME'", "functionName": "'$function_name'", "functionArgs": '${arguments:-[]}

  # Add channel if it exists
  if [ -n "$channel" ]; then
    json_payload+=', "channelName": "'$channel'"'
  fi

  # Add transient data if it exists
  if [ -n "$transient" ]; then
    json_payload+=', "transientData": '$transient
  fi

  json_payload+='}'

  echo $json_payload

  # Execute request
  postChaincodeData "/invoke" "$json_payload"

  successln "done"
}

queryChaincode() {
  channel=$CC_CHANNEL

  peer_unique_name=$1
  function_name=$2
  shift 2

  while [[ $# -gt 0 ]]; do
    case $1 in
    --arguments)
      arguments="$2"
      shift 2
      ;;
    --channel)
      channel="$2"
      shift 2
      ;;
    *)
      fatalln "Unknown option: $1"
      ;;
    esac
  done

  infoln "Querying chaincode on $peer_unique_name for $function_name with ${arguments-"NO ARGUMENTS"} on channel ${channel-"default channel"}..."

  # Parse and format the arguments to query string
  if [[ -n $arguments && $arguments != \[* && $arguments != *\] ]]; then
    query_arguments="&function_args[]=$arguments"
  elif [[ -n $arguments && $arguments != '[]' ]]; then
    delimiter="|"

    input_arguments="${arguments}"

    # Remove spaces
    input_arguments="${input_arguments// /}"

    # Remove brackets and quotes
    input_arguments="${input_arguments//[\"/}"
    input_arguments="${input_arguments//\"]/}"

    # Replace commas between quotes with a different delimiter
    input_arguments="${input_arguments//\",\"/$delimiter}"

    # Replace delimiter with '&function_args[]='
    input_arguments="${input_arguments//$delimiter/\&function_args[]=}"

    # Add 'function_args[]=' to the beginning
    query_arguments="&function_args[]=$input_arguments"
  else
    query_arguments=""
  fi

  if [ -n "$channel" ]; then
    query_channel="&channel=$channel"
  else
    query_channel=""
  fi

  # Execute request
  getChaincodeData "/query/peers/${peer_unique_name}?chaincode=$CC_NAME&function_name=${function_name}${query_arguments}${query_channel}" 

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
  channel_name="$2"
  orderer_unique_name=$1
  shift 2

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
      fatalln "Unknown option: $1"
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

  infoln "Creating channel ${channel_name} on orderer ${1} with configuration [endorsement_policy=${endorsement_policy}, batch_timeout_seconds=${batch_timeout_seconds}, max_message_count=${max_message_count}, absolute_max_mb=${absolute_max_mb}, preferred_max_mb=${preferred_max_mb}]..."

  postChannelData "" '{"ordererUniqueName": "'$orderer_unique_name'", "name": "'$channel_name'", "endorsementPolicy": "'$endorsement_policy'", "batchTimeoutSeconds": '$batch_timeout_seconds', "maxMessageCount": '$max_message_count', "absoluteMaxMB": '$absolute_max_mb', "preferredMaxMB": '$preferred_max_mb'}'

  successln "done"
}

ordererJoinChannel() {
  infoln "Orderer ${1} joining channel ${2}..."
  postChannelData "/$2/nodes" '{"nodeUniqueName": "'$1'"}'
  successln "done"
}

peerJoinChannel() {
  infoln "Peer ${1} joining channel ${2}..."
  postChannelData "/$2/nodes" '{"nodeUniqueName": "'$1'"}'
  successln "done"
}

ordererLeaveChannel() {
  infoln "Orderer ${1} leaving channel ${2}..."
  deleteChannelData "/$2/nodes/$1"
  successln "done"
}

peerLeaveChannel() {
  infoln "Peer ${1} leaving channel ${2}..."
  deleteChannelData "/$2/nodes/${1}"
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
    queryPeers $2
    ;;
  orderers)
    validateEnvVariables
    queryOrderers $2
    ;;
  nodes)
    validateEnvVariables
    queryNodes $2
    ;;
  orderer-channels)
    validateEnvVariables
    queryOrdererChannels $2
    ;;
  peer-channels)
    validateEnvVariables
    queryPeerChannels $2
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
    approveChaincode ${@:2}
    ;;
  commit)
    validateEnvVariables
    commitChaincode ${@:2}
    ;;
  init)
    validateEnvVariables
    initChaincode ${@:2}
    ;;
  invoke)
    validateEnvVariables
    invokeChaincode "${@:2}"
    ;;
  query)
    validateEnvVariables
    queryChaincode "${@:2}"
    ;;
  create-channel)
    validateEnvVariables
    createChannel "${@:2}"
    ;;
  orderer-join-channel)
    validateEnvVariables
    ordererJoinChannel $2 "$3"
    ;;
  peer-join-channel)
    validateEnvVariables
    peerJoinChannel $2 "$3"
    ;;
  orderer-leave-channel)
    validateEnvVariables
    ordererLeaveChannel $2 "$3"
    ;;
  peer-leave-channel)
    validateEnvVariables
    peerLeaveChannel $2 "$3"
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
