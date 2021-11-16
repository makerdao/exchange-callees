#!/bin/sh

UniswapV2CalleeDai=$(dapp create UniswapV2CalleeDai \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \
  0x6a60b7070befb2bfc964F646efDF70388320f4E0)

UniswapV2LpTokenCalleeDai=$(dapp create UniswapV2LpTokenCalleeDai \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \
  0x6a60b7070befb2bfc964F646efDF70388320f4E0)

UniswapV3Callee=$(dapp create UniswapV3Callee \
  0xE592427A0AEce92De3Edee1F18E0157C05861564 \
  0x6a60b7070befb2bfc964F646efDF70388320f4E0)

#
# No curve pool for stETH on goerli yet
#
# WstETHCurveUniv3Callee=$(dapp create WstETHCurveUniv3Callee \
#   0x0 \
#   ${UniswapV3Callee} \
#   0x6a60b7070befb2bfc964F646efDF70388320f4E0 \
#   0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6)

echo "UniswapV2CalleeDai: ${UniswapV2CalleeDai}"
echo "UniswapV2LpTokenCalleeDai: ${UniswapV2LpTokenCalleeDai}"
echo "UniswapV3Callee: ${UniswapV3Callee}"
# echo "WstETHCurveUniv3Callee: ${WstETHCurveUniv3Callee}"
