#! /bin/bash

[[ "$(cast chain --rpc-url="$ETH_RPC_URL")" == "ethlive"  ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1;  }

LATEST_BLOCK=$(cast block --rpc-url $ETH_RPC_URL latest number)
if test -f block; then
    BLOCK=$(cat block)
    AGE=$((LATEST_BLOCK - BLOCK))
    echo "using cached block ${BLOCK} (${AGE} blocks ago), delete ./block to refresh"
else
    BLOCK=$(($LATEST_BLOCK-6))
    echo "using fresh block ${BLOCK}"
fi
if [[ $# -eq 0 ]] ; then
    forge test --fork-url $ETH_RPC_URL --fork-block-number $BLOCK
else
    forge test --fork-url $ETH_RPC_URL --fork-block-number $BLOCK --match ${1} -vvv
fi
echo $BLOCK > block
