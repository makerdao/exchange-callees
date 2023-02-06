#! /bin/bash

if [[ $# -eq 0 ]] ; then
    forge test --use solc:0.6.12 --fork-url "$ETH_RPC_URL"
else
    forge test --use solc:0.6.12 --fork-url "$ETH_RPC_URL" -vvv --match-test ${1}
fi

