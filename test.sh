#! /bin/bash

if [[ $# -eq 0 ]] ; then
    dapp --use solc:0.6.12 test --rpc
else
    dapp --use solc:0.6.12 test --rpc --verbosity 3 -m ${1}
fi
