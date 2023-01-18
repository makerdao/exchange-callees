// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2023 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import 'ds-test/test.sol';
import 'dss-interfaces/Interfaces.sol';
import {OneInchCallee} from '../OneInchCallee.sol';

import 'dss/clip.sol';
import 'dss/abaci.sol';

interface Hevm {
    function warp(uint256) external;
    function rollFork(uint256) external;
    function store(address, bytes32, bytes32) external;
    function load(address, bytes32) external returns (bytes32);
    function envOr(string calldata, uint256) external returns (uint256);
    function envOr(string calldata, address) external returns (address);
    function envOr(string calldata, bytes calldata) external returns (bytes memory);
}

interface OneInchRouter {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }
}

contract VaultHolder {
    constructor(VatAbstract vat) public {
        vat.hope(msg.sender);
    }
}

contract OneInchTests is DSTest {
    address constant hevmAddr = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    bytes32 constant linkName = 'LINK-A';

    uint256 constant WAD = 1E18;
    uint256 constant RAY = 1E27;
    uint256 constant RAD = 1E45;

    function giveTokens(address token, uint256 amount) public {
        // Edge case - balance is already set for some reason
        if (GemAbstract(token).balanceOf(address(this)) == amount) return;

        // Solidity-style
        for (uint256 i = 0; i < 20; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(token, keccak256(abi.encode(address(this), uint256(i))));
            hevm.store(token, keccak256(abi.encode(address(this), uint256(i))), bytes32(amount));
            if (GemAbstract(token).balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(token, keccak256(abi.encode(address(this), uint256(i))), prevValue);
            }
        }

        // Vyper-style
        for (uint256 i = 0; i < 20; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(token, keccak256(abi.encode(uint256(i), address(this))));
            hevm.store(token, keccak256(abi.encode(uint256(i), address(this))), bytes32(amount));
            if (GemAbstract(token).balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(token, keccak256(abi.encode(uint256(i), address(this))), prevValue);
            }
        }
    }

    address linkAddr;
    address daiAddr;
    address vatAddr;
    address linkJoinAddr;
    address daiJoinAddr;
    address dogAddr;
    address jugAddr;
    address linkClipAddr;
    address linkPipAddr;

    Hevm hevm;
    GemAbstract link;
    VatAbstract vat;
    DaiAbstract dai;
    GemJoinAbstract linkJoin;
    DogAbstract dog;
    JugAbstract jug;
    ClipAbstract linkClip;

    OsmAbstract linkPip;

    function setAddresses() private {
        ChainlogHelper helper = new ChainlogHelper();
        ChainlogAbstract chainLog = helper.ABSTRACT();
        linkAddr = chainLog.getAddress('LINK');
        vatAddr = chainLog.getAddress('MCD_VAT');
        daiAddr = chainLog.getAddress('MCD_DAI');
        linkJoinAddr = chainLog.getAddress('MCD_JOIN_LINK_A');
        daiJoinAddr = chainLog.getAddress('MCD_JOIN_DAI');
        dogAddr = chainLog.getAddress('MCD_DOG');
        jugAddr = chainLog.getAddress('MCD_JUG');
        linkClipAddr = chainLog.getAddress('MCD_CLIP_LINK_A');
        linkPipAddr = chainLog.getAddress('PIP_LINK');
    }

    function setInterfaces() private {
        hevm = Hevm(hevmAddr);
        link = GemAbstract(linkAddr);
        vat = VatAbstract(vatAddr);
        dai = DaiAbstract(daiAddr);
        linkJoin = GemJoinAbstract(linkJoinAddr);
        dog = DogAbstract(dogAddr);
        jug = JugAbstract(jugAddr);
        linkClip = ClipAbstract(linkClipAddr);
        linkPip = OsmAbstract(linkPipAddr);
    }

    VaultHolder ali;
    address aliAddr;
    OneInchCallee dan;
    address danAddr;
    address oneInchRouter;
    bytes oneInchTxData;

    function getPermissions() private {
        hevm.store(dogAddr, keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));
        hevm.store(vatAddr, keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));
        hevm.store(linkPipAddr, keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));
        linkPip.kiss(address(this));
    }

    function setEnvVars() private {
        // Execute this test with fresh data via
        // `(cd scripts/1inch-callee-data-fetcher && npm ci && node index.js)`
        // check the script for more details on how to use 1inch API
        uint256 oneInchBlock = hevm.envOr('ONE_INCH_BLOCK', 16327090);
        log_named_uint('oneInchBlock value (default or loaded from ONE_INCH_BLOCK env var):', oneInchBlock);
        hevm.rollFork(oneInchBlock);
        oneInchRouter = hevm.envOr('ONE_INCH_ROUTER', 0x1111111254EEB25477B68fb85Ed929f73A960582);
        log_named_address('oneInchRouter value (default or loaded from ONE_INCH_ROUTER env var):', oneInchRouter);
        oneInchTxData = hevm.envOr('ONE_INCH_TX_DATA', hex'00000000000000000000000053222470cdcfb8081c0e3a50fd106f0d69e63f20000000000000000000000000514910771af9ca656af840dff83e8264ecf986ca0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000053222470cdcfb8081c0e3a50fd106f0d69e63f20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000021e19e0c9bab2400000000000000000000000000000000000000000000000000bf54254f482ad99e71b000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002d60000000000000000000000000000000000000002b800028a00024000001a0020d6bdbf78514910771af9ca656af840dff83e8264ecf986ca00a007e5c0d200000000000000000000000000000000000000000000020200011b0000cc00a0c9e75c480000000000000000310100000000000000000000000000000000000000000000000000009e00004f00a0fbb7cd0600e99481dc77691d8e2456e5f3f61c1810adfc1503000200000000000000000018514910771af9ca656af840dff83e8264ecf986cac02aaa39b223fe8d0a0e5c4f27ead9083c756cc202a00000000000000000000000000000000000000000000000000000000000000001ee63c1e501a6cc3c2531fdaa6ae1a3ca84c2855806728693e8514910771af9ca656af840dff83e8264ecf986ca02a00000000000000000000000000000000000000000000000000000000000000001ee63c1e50088e6a0c2ddd26feeb64f039a2c41296fcb3f5640c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0bd46a3430382698aecc9e28e9bb27608bd52cf57f704bd1b83000000000000000000000336a13a9247ea42d743238089903570127dda72fe4400000000000000000000035dae37d54ae477268b9997d4161b96b8200755935c000000000000000000000337000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000082698aecc9e28e9bb27608bd52cf57f704bd1b83000000000000000000000000ae37d54ae477268b9997d4161b96b8200755935c0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00a0f2fa6b666b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000c142e50a43b9814fe2100000000000000004559e3d83a48a2da80a06c4eca276b175474e89094c44da98b954eedeac495271d0f1111111254eeb25477b68fb85ed929f73a96058200000000000000000000cfee7c08');
        log_named_bytes('oneInchTxData (default or loaded from ONE_INCH_TX_DATA env var):', oneInchTxData);
    }

    function setUp() public {
        setAddresses();
        setInterfaces();
        setEnvVars();
        ali = new VaultHolder(vat);
        aliAddr = address(ali);
        dan = new OneInchCallee(daiJoinAddr);
        danAddr = address(dan);
        getPermissions();
    }

    function getLinkPrice() private view returns (uint256 val) {
        val = uint256(linkPip.read());
    }

    function getLinkPriceRay() private view returns (uint256) {
        return getLinkPrice() * 10**9;
    }

    function getLink(uint256 amountLink) private {
        giveTokens(linkAddr, amountLink);
    }

    function testGetLink() public {
        uint256 amount = 10 * WAD;
        assertEq(link.balanceOf(address(this)), 0);
        getLink(amount);
        assertEq(link.balanceOf(address(this)), amount);
    }

    function joinLink(uint256 amount) private {
        link.approve(linkJoinAddr, amount);
        linkJoin.join(aliAddr, amount);
    }

    function testJoinLink() public {
        uint256 amountLink = 100 * WAD;
        getLink(amountLink);
        joinLink(amountLink);
        assertEq(vat.gem(linkName, aliAddr), amountLink);
    }

    function frobMax(uint256 gem, bytes32 ilkName) private {
        uint256 ink = gem;
        (, uint256 rate, uint256 spot, , ) = vat.ilks(ilkName);
        uint256 art = (ink * spot) / rate;
        vat.frob(ilkName, aliAddr, aliAddr, aliAddr, int256(ink), int256(art));
    }

    function testFrobMax() public {
        (, , , , uint256 dustRad) = vat.ilks(linkName);
        uint256 amountLink = (dustRad / getLinkPriceRay()) * 2;
        getLink(amountLink);
        joinLink(amountLink);
        frobMax(amountLink, linkName);
        try vat.frob(linkName, aliAddr, aliAddr, aliAddr, 0, 1) {
            log('not at maximum frob');
            fail();
        } catch {
            log('success');
        }
    }

    function drip(bytes32 ilkName) private {
        jug.drip(ilkName);
    }

    function testDrip() public {
        (, uint256 ratePre, , , ) = vat.ilks(linkName);
        drip(linkName);
        (, uint256 ratePost, , , ) = vat.ilks(linkName);
        assertGt(ratePost, ratePre);
    }

    function barkLink() private returns (uint256 auctionId) {
        dog.bark(linkName, aliAddr, aliAddr);
        auctionId = linkClip.kicks();
    }

    function testBarkLink() public {
        (, , , , uint256 dustRad) = vat.ilks(linkName);
        uint256 amountLink = (dustRad / getLinkPriceRay()) * 2;
        uint256 kicksPre = linkClip.kicks();
        getLink(amountLink);
        joinLink(amountLink);
        frobMax(amountLink, linkName);
        drip(linkName);
        uint256 auctionId = barkLink();
        uint256 kicksPost = linkClip.kicks();
        assertEq(auctionId, kicksPost);
        assertEq(kicksPost, kicksPre + 1);
        (, , uint256 lot, address usr, uint96 tic, ) = linkClip.sales(auctionId);
        assertEq(usr, aliAddr);
        assertEq(lot, amountLink);
        assertEq(tic, block.timestamp);
    }

    function createLinkAuction() private returns (uint256 auctionId, uint256 amountLinkRay, uint256 auctionPrice) {
        (, , , , uint256 dustRad) = vat.ilks(linkName);
        amountLinkRay = (dustRad / getLinkPriceRay()) * 2;
        getLink(amountLinkRay);
        joinLink(amountLinkRay);
        frobMax(amountLinkRay, linkName);
        drip(linkName);
        auctionId = barkLink();
        (, auctionPrice, , ) = linkClip.getStatus(auctionId);
    }

    function reencodedOneInchData() private view returns (bytes memory output) {
        // We wouldn't need to reincode 1inch data outside of the tests
        // if OneInchCallee address would be known at the time of the API request
        // this is just a workaround for the test
        (
            address executor,
            OneInchRouter.SwapDescription memory swapDescription,
            bytes memory permit,
            bytes memory tradeData
        ) = abi.decode(oneInchTxData, (address, OneInchRouter.SwapDescription, bytes, bytes));
        swapDescription.dstReceiver = address(dan);
        output = abi.encode(
            executor,
            swapDescription,
            permit,
            tradeData
        );
    }

    function takeLink(
        uint256 auctionId,
        uint256 amt,
        uint256 max,
        uint256 minProfit
    ) public {
        vat.hope(linkClipAddr);
        link.approve(oneInchRouter, amt);
        bytes memory data = abi.encode(
            danAddr,
            linkJoinAddr,
            minProfit,
            address(0),
            oneInchRouter,
            reencodedOneInchData()
        );
        linkClip.take(auctionId, amt, max, danAddr, data);
    }

    function testTakeLinkOneInchProfit() public {
        (uint256 auctionId, uint256 amountLinkRay, uint256 auctionPrice) = createLinkAuction();
        uint256 linkPrice = getLinkPrice();
        uint256 minProfitPct = 30;
        while (((((auctionPrice / uint256(1e9)) * 11) / 10) * (100 + minProfitPct)) / 100 > linkPrice) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice, , ) = linkClip.getStatus(auctionId);
        }
        uint256 minProfit = (((amountLinkRay * auctionPrice) / RAY) * minProfitPct) / 100;
        assertEq(dai.balanceOf(danAddr), 0);
        takeLink(auctionId, amountLinkRay, auctionPrice, minProfit);
        assertGe(dai.balanceOf(danAddr), minProfit);
    }

    function testTakeLinkOneInchNoProfit() public {
        (uint256 auctionId, uint256 amountLinkRay, uint256 auctionPrice) = createLinkAuction();
        uint256 linkPrice = getLinkPrice();
        while (auctionPrice / uint256(1e9) * 11 / 10 > linkPrice) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = linkClip.getStatus(auctionId);
        }
        assertEq(dai.balanceOf(danAddr), 0);
        takeLink(auctionId, amountLinkRay, auctionPrice, 0);
        assertLt(dai.balanceOf(danAddr), amountLinkRay * auctionPrice / RAY / 5);
    }

    function testFailTakeLinkOneInchWithTooMuchProfit() public {
        (uint256 auctionId, uint256 amountLinkRay, uint256 auctionPrice) = createLinkAuction();
        uint256 linkPrice = getLinkPrice();
        while (auctionPrice / uint256(1e9) * 11 / 10 > linkPrice) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = linkClip.getStatus(auctionId);
        }
        assertEq(dai.balanceOf(danAddr), 0);
        uint256 tooMuchProfit = ((amountLinkRay * auctionPrice) / RAY) * 10;
        takeLink(auctionId, amountLinkRay, auctionPrice, tooMuchProfit);
    }
}
