all             :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.12 build
clean           :; dapp clean
# usage:        make test match=Burn
test            :; ./test.sh ${match}
deploy          :; echo "use deploy-kovan or deploy-mainnet"
deploy-kovan    :; make && ./scripts/deploy-kovan.sh
deploy-mainnet  :; make && ./scripts/deploy-mainnet.sh
flatten         :;
	hevm flatten --source-file "src/UniswapV2Callee.sol" > out/UniswapV2CalleeDai.sol
	hevm flatten --source-file "src/UniswapV2LpTokenCallee.sol" > out/UniswapV2LpTokenCallee.sol
