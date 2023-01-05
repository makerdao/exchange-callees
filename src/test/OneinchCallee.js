import path from 'path';
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
    const response = await executeOneinchRequest('/liquidity-sources');
    const protocolIds = response.protocols.map(protocol => protocol.id);
    return protocolIds.filter(protocolId => !protocolId.toLowerCase().includes('limit')); // filter out limit orders
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

function repackageCallData(callData) {
    // We don't want to send certain data twice to the callee (because storage is expensive)
    // swapDescription.srcToken – as it's already known to callee as gem address
    // swapDescription.dstToken - as it should always be DAI
    // swapDescription.dstReceiver - as it will be the callee address itself
    // swapDescription.amount – as it will be overwritten to the exact amount of collateral available
    // swapDescription.minReturnAmount - as it will be overwritten to the exact amount of debt + profit
    const functionSignature = utils.hexDataSlice(callData, 0, 4);
    if (functionSignature !== EXPECTED_SIGNATURE) {
        throw new Error(`Unexpected 1inch function signature: ${functionSignature}, expected: ${EXPECTED_SIGNATURE}`);
    }
    const encodedParameters = utils.hexDataSlice(callData, 4);
    const decodedParameters = utils.defaultAbiCoder.decode(
        // according to https://etherscan.io/address/0x11111112542D85B3EF69AE05771c2dCCff4fAa26#code
        [
            'address executor',
            '(address srcToken, address dstToken, address srcReceiver, address dstReceiver, uint256 amount, uint256 minReturnAmount, uint256 flags) swapDescription',
            'bytes permit',
            'bytes tradeData',
        ],
        encodedParameters
    );
    console.info('decoded 1inch parameters', decodedParameters);
    const repackagedParameters = utils.defaultAbiCoder.encode(
        ['address', 'address', 'uint256', 'bytes', 'bytes'],
        [
            decodedParameters.executor,
            decodedParameters.swapDescription.srcReceiver,
            decodedParameters.swapDescription.flags,
            decodedParameters.permit,
            decodedParameters.tradeData,
        ]
    );
    console.info('repackaged parameters', repackagedParameters);
    console.info('saved calldata space (in bytes)', (callData.length - repackagedParameters.length) / 2);
    return repackagedParameters;
}

async function main() {
    const oneinchResponse = await getOneinchSwapParameters(
        '10000' + '0'.repeat(18) // LINK amount to swap
    );
    console.info('received oneinch API response:', oneinchResponse);
    console.info('cleaning up call data...');
    const repackagedParameters = repackageCallData(oneinchResponse.tx.data);
    console.info('executing forge test...');
    const child = spawn('forge', ['test', '--match', 'testTakeLinkOneinchProfit'], {
        cwd: path.resolve(),
        stdio: 'inherit',
        env: {
            ...process.env,
            ONE_INCH_ROUTER: oneinchResponse.tx.to,
            ONE_INCH_PARAMETERS: repackagedParameters,
        },
    });
    await new Promise(resolve => {
        child.on('close', resolve);
    });
}

main().catch(error => {
    throw new Error(error);
});
