# Exchange Callees
[![Build Status](https://travis-ci.com/makerdao/exchange-callees.svg?branch=master)](https://travis-ci.com/makerdao/exchange-callees)

This repository contains exchange callee contracts, which wrap around decentralized exchanges and interact with the [Maker Protocol](https://github.com/makerdao/dss). They are used in conjunction with the `auction-demo-keeper` to demonstrate flash loan functionality within LIQ2.0's collateral auctions.

With built-in flash loans, auction participants can accept a collateral advance from LIQ2.0, send it to an exchange callee contract to be traded for Dai, forward any Dai profit to an external address, and pay back the auction - all in a single transaction. In terms of capital, the participant only needs ETH to pay for gas costs.

## Architecture

Each exchange has its own public callee contract, which exposes a function called `clipperCall(owe,slice,data)`. This method is called by the `Clipper` contract, the collateral auction house of LIQ2.0. After receiving internal `gem` (i.e. collateral) from `Clipper`, it conducts the following steps:

1. Converts internal `gem` to ERC20 `gem`
2. Approves exchange to pull ERC20 `gem`
3. Trades ERC20 `gem` for ERC20 `dai`
4. Forwards any ERC20 `gem` (if present) to external address
5. Converts ERC20 `dai` to internal `dai` and sends to msg.sender
6. Forwards ERC20 `dai` profit (if present) to external address
7. Sends internal `dai` to `Clipper` for repayment (occurs in `Clipper.take`)

NOTE:
* NEVER DIRECTLY SEND internal/ERC20 `gem`/`dai` to an exchange callee contract.
* Remember to call `vat.hope(clipper)` from the msg.sender once before calling `Clipper.take`

## Exchanges supported
* [OasisDex](https://oasisdex.com/)
* [UniswapV2](https://uniswap.org/) (Only ETH collateral types are supported at the moment)

## Public addresses

## Improvements
To slow down or defend against [generalized frontrunning bots](https://medium.com/@danrobinson/ethereum-is-a-dark-forest-ecc5f0505dff), consider:
- Deploying an ownable `exchange-callee` contract and add an `auth` modifier to `clipperCall()`, so only the owner (you) can call the function
- Using a mempool-shielded transaction service, as outlined in [this blog post](https://samczsun.com/escaping-the-dark-forest/)

## Testing
Requires [Dapptools](https://github.com/dapphub/dapptools)
```
$ dapp update
$ dapp --use solc:0.6.11 test
```
