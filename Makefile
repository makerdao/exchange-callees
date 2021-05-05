all     :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.12 build
clean   :; dapp clean
test    :; dapp --use solc:0.6.12 test ${flags}
deploy  :; make && dapp create UniswapV2CalleeDai 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D 0x9759A6Ac90977b93B58547b4A71c78317f391A28
flatten :; hevm flatten --source-file "src/UniswapV2Callee.sol" > out/UniswapV2CalleeDai.sol
