import path from 'path';
import url from 'url';
import { spawn } from 'child_process';
import fetch from 'node-fetch';
import { utils } from 'ethers';

const CHAIN_ID = 1;
const BASE_URL = `https://api.1inch.io/v5.0/${CHAIN_ID}`; // see https://docs.1inch.io/docs/aggregation-protocol/api/swagger/
const EXPECTED_SIGNATURE = '0x12aa3caf'; // see https://www.4byte.directory/signatures/?bytes4_signature=0x12aa3caf

async function executeOneinchRequest(methodName, queryParams) {
    const url = `${BASE_URL}${methodName}?${new URLSearchParams(queryParams)}`;
    const response = await fetch(url).then(res => res.json());
    if (response.error) {
        console.error(
            `1inch API call to "${methodName}" failed with:`,
            response.error,
            'request parameters:',
            swapParams
        );
        throw new Error(`1inch API call failed with "${response.error}"`);
    }
    return response;
}

async function getOneinchValidProtocols() {
    // Fetch all supported protocols except for the limit orders
    const response = await executeOneinchRequest('/liquidity-sources');
    const protocolIds = response.protocols.map(protocol => protocol.id);
    return protocolIds.filter(protocolId => !protocolId.toLowerCase().includes('limit'));
}

async function getOneinchSwapParameters({ amount, slippage }) {
    // Documentation https://docs.1inch.io/docs/aggregation-protocol/api/swap-params/
    const swapParams = {
        fromTokenAddress: '0x514910771AF9Ca656af840dff83E8264EcF986CA', // LINK
        toTokenAddress: '0x6B175474E89094C44Da98b954EedeAC495271d0F', // MCD_DAI
        fromAddress: '0x0000000000000000000000000000000000000000', // have to be callee address
        amount,
        slippage,
        allowPartialFill: false, // disable partial fill
        disableEstimate: true, // disable eth_estimateGas
        compatibilityMode: true, // always receive parameters for the `swap` call
        protocols: (await getOneinchValidProtocols()).join(','),
    };
    const oneinchResponse = await executeOneinchRequest('/swap', swapParams);
    console.info('received oneinch API response:', oneinchResponse);
    const functionSignature = utils.hexDataSlice(oneinchResponse.tx.data, 0, 4); // see https://docs.soliditylang.org/en/develop/abi-spec.html#function-selector
    if (functionSignature !== EXPECTED_SIGNATURE) {
        throw new Error(`Unexpected 1inch function signature: ${functionSignature}, expected: ${EXPECTED_SIGNATURE}`);
    }
    return oneinchResponse;
}

async function executeForgeTest(testName, environmentVariables) {
    const fileDirectory = path.dirname(url.fileURLToPath(import.meta.url));
    const rootDirectory = path.resolve('..', '..', fileDirectory);
    console.info(`executing forge test of the "${testName}" function in "${rootDirectory}"...`);
    const child = spawn('forge', ['test', '--match', testName], {
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
    const oneinchResponse = await getOneinchSwapParameters({
        amount: '10000' + '0'.repeat(18), // LINK amount to swap
        slippage: 1, // Desired slippage value from 0 to 50
    });
    await executeForgeTest('testTakeLinkOneInchProfit', {
        ONE_INCH_ROUTER: oneinchResponse.tx.to,
        ONE_INCH_TX_DATA: utils.hexDataSlice(oneinchResponse.tx.data, 4), // remove function signature
    });
}

main().catch(error => {
    throw new Error(error);
});
