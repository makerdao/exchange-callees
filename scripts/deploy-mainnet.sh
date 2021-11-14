#!/bin/sh

UniswapV2CalleeDai=$(dapp create UniswapV2CalleeDai \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \
  0x9759A6Ac90977b93B58547b4A71c78317f391A28)

UniswapV2LpTokenCalleeDai=$(dapp create UniswapV2LpTokenCalleeDai \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \
  0x9759A6Ac90977b93B58547b4A71c78317f391A28)

UniswapV3Callee=$(dapp create UniswapV3Callee \
  0xE592427A0AEce92De3Edee1F18E0157C05861564 \
  0x9759A6Ac90977b93B58547b4A71c78317f391A28)

UniV3Callee=$(dapp create UniV3Callee \
  0xE592427A0AEce92De3Edee1F18E0157C05861564 \
  0x9759A6Ac90977b93B58547b4A71c78317f391A28)

WstETHCurveUniv3Callee=$(dapp create WstETHCurveUniv3Callee \
  0xDC24316b9AE028F1497c275EB9192a3Ea0f67022 \
  ${UniV3Callee} \
  0x6a60b7070befb2bfc964F646efDF70388320f4E0 \
  0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6)

echo "UniswapV2CalleeDai: ${UniswapV2CalleeDai}"
echo "UniswapV2LpTokenCalleeDai: ${UniswapV2LpTokenCalleeDai}"
echo "UniswapV3Callee: ${UniswapV3Callee}"
echo "UniV3Callee: ${UniV3Callee}"
echo "WstETHCurveUniv3Callee: ${WstETHCurveUniv3Callee}"
