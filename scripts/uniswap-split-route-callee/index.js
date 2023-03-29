import path from 'path';
import url from 'url';
import * as dotenv from 'dotenv';
import { spawn } from 'child_process';
import { AlphaRouter, ChainId, SwapType } from '@uniswap/smart-order-router';
import { CurrencyAmount, Percent, Token, TradeType } from '@uniswap/sdk-core';
import { ethers } from 'ethers';

const fileDirectory = path.dirname(url.fileURLToPath(import.meta.url));
const rootDirectory = path.join(fileDirectory, '..', '..');
dotenv.config({ path: path.resolve(rootDirectory, '.env') });
const rpcUrl = process.env.FOUNDRY_ETH_RPC_URL;
if (!rpcUrl) {
    throw new Error('please provide FOUNDRY_ETH_RPC_URL env var');
}

const YEAR_IN_SECONDS = 60 * 60 * 24 * 365;

async function getProvider() {
    const rpcUrl = process.env.FOUNDRY_ETH_RPC_URL;
    if (!rpcUrl) {
        throw new Error('please provide FOUNDRY_ETH_RPC_URL env var');
    }
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const { chainId } = await provider.getNetwork();
    if (chainId !== ChainId.MAINNET) {
        throw new Error(
            `The FOUNDRY_ETH_RPC_URL env var should point to etherium mainnet, but currently returns chain id ${chainId}`
        );
    }
    return provider;
}

async function getLatestBlockNumber() {
    const provider = await getProvider();
    const latestBlock = await provider.getBlock('latest');
    return latestBlock.number;
}

async function getAlphaRouterResponse(recipient, amount) {
    const provider = await getProvider();
    const alphaRouter = new AlphaRouter({ chainId: ChainId.MAINNET, provider });
    const inputToken = new Token(ChainId.MAINNET, '0x514910771AF9Ca656af840dff83E8264EcF986CA', 18); // LINK token address, 18 decimals
    const outputToken = new Token(ChainId.MAINNET, '0x6B175474E89094C44Da98b954EedeAC495271d0F', 18); // DAI token address, 18 decimals
    const inputAmountCurrency = CurrencyAmount.fromRawAmount(inputToken, amount);
    const response = await alphaRouter.route(inputAmountCurrency, outputToken, TradeType.EXACT_INPUT, {
        recipient, // address of the wallet to receive the output token
        slippageTolerance: new Percent(10, 100),
        deadline: Math.floor(Date.now() / 1000 + YEAR_IN_SECONDS), // fail transaction if it can't be mined in respective time
        type: SwapType.SWAP_ROUTER_02, // use Uniswap V3 Router 2 to match expected calldata format
    });
    console.info('got alpharouter response for profit case:', response);
    if (!response || !response.methodParameters) {
        throw new Error('Uniswap alpha router could not find valid route for profit case');
    }
    return response
}


async function executeForgeTest(testName, environmentVariables) {
    console.info(`executing forge test of the "${testName}" function in "${rootDirectory}"...`);
    const child = spawn('forge', ['test', '--match', testName, '--use', '0.6.12', '--rpc-url', rpcUrl], {
        cwd: rootDirectory,
        stdio: 'inherit',
        env: {
            ...process.env,
            ...environmentVariables,
        },
    });
    await new Promise(resolve => {
        child.on('close', resolve);
    });
}

async function main() {
    const response = await getAlphaRouterResponse(
        '0x000000000000000000000000000000000000dEaD', // the address of the callee that is not yet deployed
        '4096516663605658381916'                      // amount of token to swap (auction amount)
                                                      // the function call has to return the same amount as within the sol test.
                                                      // the function reimplements the computation logic in the test.
    );
    const latestBlockNumber = await getLatestBlockNumber();
    await executeForgeTest('testTakeLinkUniswapSplitProfit', {
        UNISWAP_TX_DATA_PROFIT: ethers.utils.hexDataSlice(response.methodParameters.calldata, 4),
        UNISWAP_BLOCK: latestBlockNumber,
    });
}

main().catch(error => {
    throw new Error(error);
});
