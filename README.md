# btp-chaincode-lifecycle

Scripts to manage the chaincode lifecycle on the BTP platform

```bash
Usage: ./chaincode.sh <command> [options]
Commands:
  peers                   : Query the peers on which we can install the chaincode
  orderers                : Query the orderers
  nodes                   : Query all the nodes
  channels                : Query the channels
  installed <peer>        : Query installed chaincodes
  approved <peer>         : Query approved definition of chaincode
  committed <peer>        : Query commit definition of chaincode
  commit-readiness <peer> : Checking commit readiness of chaincode
  package                 : Package the chaincode
  install <peer>          : Install the chaincode
  approve <peer>          : Approve the chaincode
  commit <peer>           : Commit the chaincode
  init <peer>             : Initialize the chaincode
  query <peer> <function_name> [args...]         : Query the chaincode.
    Example: chaincode.sh query functionName '["arg1", "arg2"]'
  invoke <peer> <function_name> [args...]        : Invoke a transaction on the chaincode.
    Example: chaincode.sh invoke functionName '["arg1", "arg2"]'
  create-channel <channel_name> [options]        : Create a channel with the given name and options
    Options:
      --endorsementPolicy <MAJORITY|ALL>         : Endorsement policy for the channel (default: MAJORITY)
      --batchTimeoutInSeconds <seconds>          : Batch timeout in seconds (default: 2)
      --maxMessageCount <count>                  : Maximum message count (default: 500)
      --absoluteMaxMB <MB>                       : Absolute maximum bytes (default: 10)
      --preferredMaxMB <MB>                      : Preferred maximum bytes (default: 2)
  orderer-join-channel <orderer> <channel_name>  : Orderer joins a channel.
  orderer-leave-channel <orderer> <channel_name> : Orderer leaves a channel.
  peer-join-channel <peer> <channel_name>        : Peer joins a channel.
  peer-leave-channel <peer> <channel_name>       : Peer leaves a channel.
Options:
  -h, --help              : Display this help message
```
## Prerequisites

You will need following environment variables

```bash
export CC_RUNTIME_LANGUAGE=node
export CC_SRC_PATH=./dist
export CC_NAME=chaincodeName
export CC_VERSION=1.0
export CC_SEQUENCE=1
export CC_INIT_FCN=InitLedger
```

Optionally, you can set the following environment variables

```bash
export CC_INIT_ARGS="[]"
export CC_COLLECTIONS_CONFIG_PATH=./collections_config.json
export CC_CHANNEL="mychannel" # Default would be default-channel
```
