all             :; FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=200 forge build --use solc:0.6.12
clean           :; forge clean
# usage:        make test match=Burn
test            :; ./test.sh ${match}
deploy          :; echo "use deploy-goerli or deploy-mainnet"
deploy-goerli   :; make && ./scripts/deploy-goerli.sh
deploy-mainnet  :; make && ./scripts/deploy-mainnet.sh
flatten         :;
		forge flatten src/UniswapV2Callee.sol         --output src/UniswapV2CalleeFlatten.sol
		forge flatten src/UniswapV2LpTokenCallee.sol  --output src/UniswapV2LpTokenCalleeFlatten.sol
		forge flatten src/UniswapV3Callee.sol         --output src/UniswapV3CalleeFlatten.sol
		forge flatten src/WstETHCurveUniv3Callee.sol  --output src/WstETHCurveUniv3CalleeFlatten.sol
		forge flatten src/CurveLpTokenUniv3Callee.sol --output src/CurveLpTokenUniv3CalleeFlatten.sol
