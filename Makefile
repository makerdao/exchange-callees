all    :; dapp build
clean  :; dapp clean
test   :; dapp --use solc:0.6.12 test ${flags}
deploy :; dapp create
