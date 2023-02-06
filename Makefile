all             :; FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=200 forge build --use solc:0.6.12
clean           :; forge clean
# usage:        make test match=Burn
test            :; ./test.sh ${match}
deploy          :; echo "use deploy-goerli or deploy-mainnet"
deploy-goerli   :; make && ./scripts/deploy-goerli.sh
deploy-mainnet  :; make && ./scripts/deploy-mainnet.sh
flatten         :;
	forge flatten "src/UniswapV2Callee.sol" > out/UniswapV2CalleeDai.sol
	forge flatten "src/UniswapV2LpTokenCallee.sol" > out/UniswapV2LpTokenCalleeDai.sol
	forge flatten "src/UniswapV3Callee.sol" > out/UniswapV3Callee.sol
	forge flatten "src/WstETHCurveUniv3Callee.sol" > out/WstETHCurveUniv3Callee.sol
	forge flatten "src/CurveLpTokenUniv3Callee.sol" > out/CurveLpTokenUniv3Callee.sol
