# Exchange Callees
![Build Status](https://github.com/makerdao/exchange-callees/actions/workflows/.github/workflows/tests.yaml/badge.svg?branch=master)

This repository contains exchange callee contracts, which wrap around decentralized exchanges and interact with the [Maker Protocol](https://github.com/makerdao/dss). They are used in conjunction with the `auction-demo-keeper` to demonstrate flash loan functionality within LIQ2.0's collateral auctions.

With built-in flash loans, auction participants can accept a collateral advance from LIQ2.0, send it to an exchange callee contract to be traded for Dai, forward any Dai profit to an external address, and pay back the auction - all in a single transaction. In terms of capital, the participant only needs ETH to pay for gas costs.

**NOTE: These contracts are intended as a code example, and have not been audited or tested in a production environment.**


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

The addresses of the currently deployed contracts can be found in the [`/addresses.json`](./addresses.json) file.

## Improvements
To slow down or defend against [generalized frontrunning bots](https://medium.com/@danrobinson/ethereum-is-a-dark-forest-ecc5f0505dff), consider:
- Deploying an ownable `exchange-callee` contract and add an `auth` modifier to `clipperCall()`, so only the owner (you) can call the function
- Using a mempool-shielded transaction service, as outlined in [this blog post](https://samczsun.com/escaping-the-dark-forest/)

## Testing
Requires [Forge](https://github.com/foundry-rs/foundry)
```
$ forge install
$ forge test --use solc:0.6.12
```

## Disclaimer
YOU (MEANING ANY INDIVIDUAL OR ENTITY ACCESSING, USING OR BOTH THE SOFTWARE INCLUDED IN THIS GITHUB REPOSITORY) EXPRESSLY UNDERSTAND AND AGREE THAT YOUR USE OF THE SOFTWARE IS AT YOUR SOLE RISK. THE SOFTWARE IN THIS GITHUB REPOSITORY IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. YOU RELEASE AUTHORS OR COPYRIGHT HOLDERS FROM ALL LIABILITY FOR YOU HAVING ACQUIRED OR NOT ACQUIRED CONTENT IN THIS GITHUB REPOSITORY. THE AUTHORS OR COPYRIGHT HOLDERS MAKE NO REPRESENTATIONS CONCERNING ANY CONTENT CONTAINED IN OR ACCESSED THROUGH THE SERVICE, AND THE AUTHORS OR COPYRIGHT HOLDERS WILL NOT BE RESPONSIBLE OR LIABLE FOR THE ACCURACY, COPYRIGHT COMPLIANCE, LEGALITY OR DECENCY OF MATERIAL CONTAINED IN OR ACCESSED THROUGH THIS GITHUB REPOSITORY.
