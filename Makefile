all             :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.12 build
clean           :; dapp clean
# usage:        make test match=Burn
test            :; ./test.sh ${match}
deploy          :; echo "use deploy-goerli or deploy-mainnet"
deploy-goerli   :; make && ./scripts/deploy-goerli.sh
deploy-mainnet  :; make && ./scripts/deploy-mainnet.sh
flatten         :;
	hevm flatten --source-file "src/UniswapV2Callee.sol" > out/UniswapV2CalleeDai.sol
	hevm flatten --source-file "src/UniswapV2LpTokenCallee.sol" > out/UniswapV2LpTokenCalleeDai.sol
	hevm flatten --source-file "src/UniswapV3Callee.sol" > out/UniswapV3Callee.sol
	hevm flatten --source-file "src/WstETHCurveUniv3Callee.sol" > out/WstETHCurveUniv3Callee.sol
	hevm flatten --source-file "src/CurveLpTokenUniv3Callee.sol" > out/CurveLpTokenUniv3Callee.sol
	hevm flatten --source-file "src/rETHCurveUniv3Callee.sol" > out/rETHCurveUniv3Callee.sol
