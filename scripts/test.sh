#!/usr/bin/env bash

if [[ $# -eq 0 ]] ; then
    forge test --fork-url "$ETH_RPC_URL"
else
    forge test --fork-url "$ETH_RPC_URL" -vvv --match-test ${1}
fi

