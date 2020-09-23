# Exchange Callees
[![Build Status](https://travis-ci.com/makerdao/exchange-callees.svg?branch=master)](https://travis-ci.com/makerdao/exchange-callees)

This repository contains exchange callee contracts, which wrap around decentralized exchanges and interact with the [Maker Protocol](https://github.com/makerdao/dss). They are used in conjunction with the `auction-demo-keeper` to demonstrate flash loan functionality within LIQ2.0's collateral auctions.

With built-in flash loans, auction participants can accept a collateral advance from LIQ2.0, send it to an exchange callee contract to be traded for Dai, forward any Dai profit to an external address, and pay back the auction - all in a single transaction. In terms of capital, the participant only needs ETH to pay for gas costs.

## Architecture

Each exchange has its own public callee contract, which exposes a function called `clipperCall(owe,slice,data)`. This method is called in by the `Clipper` contract, the collateral auction house of LIQ2.0. At a high level, it conducts the following steps:
0. Recieves internal `gem` from `Clipper`
1. Converts internal `gem` to ERC20 `gem`
2. Approves exchange to pull ERC20 `gem`
3. Trades ERC20 `gem` for ERC20 `dai`
4. Converts ERC20 `dai` to internal `dai`
5. Forwards ERC20 `dai` profit to external address (if present)
6. Sends internal `dai` to `Clipper` for repayment

## Exchanges supported
* [OasisDex](https://oasisdex.com/)

## Public addresses


## Testing
Requires [Dapptools](https://github.com/dapphub/dapptools)
```
$ dapp update
$ dapp test
```
