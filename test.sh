#! /bin/bash

if test -f block; then
    BLOCK=$(cat block)
    echo "using cached block ${BLOCK}, delete ./block to refresh"
else
    LATEST_BLOCK=$(cast block --rpc-url $ETH_RPC_URL latest number)
    BLOCK=$(($LATEST_BLOCK-6))
    echo "using fresh block ${BLOCK}"
fi
if [[ $# -eq 0 ]] ; then
    forge test --fork-url $ETH_RPC_URL --fork-block-number $BLOCK
else
    forge test --fork-url $ETH_RPC_URL --fork-block-number $BLOCK --match ${1} -vvv
fi
echo $BLOCK > block
