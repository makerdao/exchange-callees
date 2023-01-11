import path from 'path';
import { spawn } from 'child_process';
import fetch from 'node-fetch';

const CHAIN_ID = 1;
const BASE_URL = `https://api.1inch.io/v5.0/${CHAIN_ID}`; // see https://docs.1inch.io/docs/aggregation-protocol/api/swagger/

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

async function getOneinchSwapParameters(linkAmount) {
    const swapParams = {
        fromTokenAddress: '0x514910771AF9Ca656af840dff83E8264EcF986CA', // LINK
        toTokenAddress: '0x6B175474E89094C44Da98b954EedeAC495271d0F', // MCD_DAI
        fromAddress: '0x0000000000000000000000000000000000000000', // yet unknown callee address
        amount: linkAmount,
        slippage: 1,
        allowPartialFill: false, // disable partial fill
        disableEstimate: true, // disable allowance checks
        compatibilityMode: true, // always receive parameters for the `swap` call
        protocols: (await getOneinchValidProtocols()).join(','),
    };
    return await executeOneinchRequest('/swap', swapParams);
}

async function executeForgeTest(testName, environmentVariables) {
    console.info(`executing forge test "${testName}"...`);
    const child = spawn('forge', ['test', '--match', testName], {
        cwd: path.resolve(),
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
    const oneinchResponse = await getOneinchSwapParameters(
        '10000' + '0'.repeat(18) // LINK amount to swap
    );
    console.info('received oneinch API response:', oneinchResponse);
    await executeForgeTest('testTakeLinkOneinchProfit', {
        ONE_INCH_ROUTER: oneinchResponse.tx.to,
        ONE_INCH_PARAMETERS: oneinchResponse.tx.data,
    });
}

main().catch(error => {
    throw new Error(error);
});
