#!/usr/bin/env bash

echo "UniswapV2CalleeDai:"
forge create src/UniswapV2Callee.sol:UniswapV2CalleeDai --constructor-args \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \
  0x9759A6Ac90977b93B58547b4A71c78317f391A28

echo "UniswapV2LpTokenCalleeDai:"
forge create src/UniswapV2LpTokenCallee.sol:UniswapV2LpTokenCalleeDai --constructor-args \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \
  0x9759A6Ac90977b93B58547b4A71c78317f391A28

echo "UniswapV3Callee:"
forge create src/UniswapV3Callee.sol:UniswapV3Callee --constructor-args \
  0xE592427A0AEce92De3Edee1F18E0157C05861564 \
  0x9759A6Ac90977b93B58547b4A71c78317f391A28

echo "WstETHCurveUniv3Callee.sol:WstETHCurveUniv3Callee:"
forge create src/WstETHCurveUniv3Callee.sol:WstETHCurveUniv3Callee --constructor-args \
  0xDC24316b9AE028F1497c275EB9192a3Ea0f67022 \
  0xE592427A0AEce92De3Edee1F18E0157C05861564 \
  0x9759A6Ac90977b93B58547b4A71c78317f391A28 \
  0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

echo "CurveLpTokenUniv3Callee:"
forge create src/CurveLpTokenUniv3Callee.sol:CurveLpTokenUniv3Callee --constructor-args \
  0xE592427A0AEce92De3Edee1F18E0157C05861564 \
  0x9759A6Ac90977b93B58547b4A71c78317f391A28 \
  0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

echo ""
echo "NOTE: update this repo's addresses.json file with the new addresses."
