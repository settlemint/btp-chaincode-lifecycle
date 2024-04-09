# btp-chaincode-lifecycle

Scripts to manage the chaincode lifecycle on the BTP platform

```
Usage: ./chaincode.sh <command> [options]
Commands:
  peers                   : Query the peers on which we can install the chaincode
  installed <peer>        : Query installed chaincodes
  approved <peer>         : Query approved definition of chaincode
  committed <peer>        : Query commit definition of chaincode
  commit-readiness <peer> : Checking commit readiness of chaincode
  package                 : Package the chaincode
  install <peer>          : Install the chaincode
  approve <peer>          : Approve the chaincode
  commit <peer>           : Commit the chaincode
  init <peer>             : Initialize the chaincode
Options:
  -h, --help              : Display this help message
```
