#!/bin/sh

UniswapV2CalleeDai=$(dapp create UniswapV2CalleeDai \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \
  0x5AA71a3ae1C0bd6ac27A1f28e1415fFFB6F15B8c)

UniswapV2LpTokenCalleeDai=$(dapp create UniswapV2LpTokenCalleeDai \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D \
  0x5AA71a3ae1C0bd6ac27A1f28e1415fFFB6F15B8c)

echo "UniswapV2CalleeDai: ${UniswapV2CalleeDai}"
echo "UniswapV2LpTokenCalleeDai: ${UniswapV2LpTokenCalleeDai}"
