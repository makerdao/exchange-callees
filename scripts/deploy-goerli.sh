#!/usr/bin/env bash

echo "UniswapV2CalleeDai:"
forge create src/UniswapV2Callee.sol:UniswapV2CalleeDai --constructor-args \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \
  0x6a60b7070befb2bfc964F646efDF70388320f4E0

echo "UniswapV2LpTokenCalleeDai:"
forge create src/UniswapV2LpTokenCallee.sol:UniswapV2LpTokenCalleeDai --constructor-args \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \
  0x6a60b7070befb2bfc964F646efDF70388320f4E0

echo "UniswapV3Callee:"
forge create src/UniswapV3Callee.sol:UniswapV3Callee --constructor-args \
  0xE592427A0AEce92De3Edee1F18E0157C05861564 \
  0x6a60b7070befb2bfc964F646efDF70388320f4E0

