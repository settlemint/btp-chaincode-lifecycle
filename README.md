# btp-chaincode-lifecycle

Scripts to manage the chaincode lifecycle on the BTP platform

```bash
Usage: ./chaincode.sh <command> [options]
Commands:
  peers                              : Query the peers on which we can install the chaincode
  orderers                           : Query the orderers
  nodes                              : Query all the nodes
  channels <node>                    : Query the channels
  installed <peer>                   : Query installed chaincodes
  approved <peer>                    : Query approved definition of chaincode
  committed <peer>                   : Query commit definition of chaincode
  commit-readiness <peer>            : Checking commit readiness of chaincode
  package                            : Package the chaincode
  install <peer>                     : Install the chaincode
  approve <peer> <orderer>           : Approve the chaincode
  commit <peer> <orderer>            : Commit the chaincode
  init <peer> <orderer>              : Initialize the chaincode
  query <peer> <function_name> [options]                   : Query the chaincode.
    Options:
      --arguments '["arg1", "arg2"]'                       : The regular arguments to pass to the function.
      --channel <channel_name>                             : Optionally override the channel name.
    Example: chaincode.sh query functionName --arguments '["arg1", "arg2"]'
  invoke <peer> <orderer> <function_name> [options]        : Invoke a transaction on the chaincode.
    Options:
      --arguments '["arg1", "arg2"]'                       : The regular arguments to pass to the function.
      --transient '{"key": "value"}'                       : The transient data to pass the to the function.
      --channel <channel_name>                             : Optionally override the channel name.
    Example: chaincode.sh invoke functionName '["arg1", "arg2"]'
  create-channel <orderer> <channel_name> [options]        : Create a channel with the given name and options
    Options:
      --endorsementPolicy <MAJORITY|ALL>                   : Endorsement policy for the channel (default: MAJORITY)
      --batchTimeoutInSeconds <seconds>                    : Batch timeout in seconds (default: 2)
      --maxMessageCount <count>                            : Maximum message count (default: 500)
      --absoluteMaxMB <MB>                                 : Absolute maximum bytes (default: 10)
      --preferredMaxMB <MB>                                : Preferred maximum bytes (default: 2)
  orderer-join-channel <orderer> <channel_name>            : Orderer joins a channel.
  orderer-leave-channel <orderer> <channel_name>           : Orderer leaves a channel.
  peer-join-channel <peer> <channel_name>                  : Peer joins a channel.
  peer-leave-channel <peer> <channel_name>                 : Peer leaves a channel.
Options:
  -h, --help              : Display this help message
```

## Prerequisites

You will need following environment variables

```bash
export CC_RUNTIME_LANGUAGE=node # the runtime, right now only node is supported
export CC_SRC_PATH=./dist # the path where the builded chaincode is located, this is the path that will be packeged
export CC_NAME=chaincodeName # the name of the chaincode
export CC_VERSION=1.0 # the version of the chaincode
export CC_SEQUENCE=1 # the sequence number of the chaincode
```

Optionally, you can set the following environment variables

```bash
export CC_INIT_FCN=InitLedger # optional name of initialization function, if not set means no initialization is needed
export CC_INIT_ARGS="[]" # optional arguments for the initialization function
export CC_COLLECTIONS_CONFIG_PATH=./collections_config.json # optional path of the collections config, can be used to configure PDC
export CC_CHANNEL="mychannel" # optional override the channel to work on, by default this will be "default-channel"
```
