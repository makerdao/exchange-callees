// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Maker Ecosystem Growth Holdings, INC.
// Copyright (C) 2021 Dai Foundation
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
import {OneinchCallee} from '../OneinchCallee.sol';

import 'dss/clip.sol';
import 'dss/abaci.sol';

interface Hevm {
    function warp(uint256) external;

    function rollFork(uint256) external;

    function store(
        address c,
        bytes32 loc,
        bytes32 val
    ) external;

    function load(address, bytes32) external returns (bytes32);

    function envOr(string calldata, uint256) external returns (uint256);

    function envOr(string calldata, address) external returns (address);

    function envOr(string calldata, bytes calldata) external returns (bytes memory);
}

interface WethAbstract is GemAbstract {
    function deposit() external payable;
}

contract VaultHolder {
    constructor(VatAbstract vat) public {
        vat.hope(msg.sender);
    }
}

contract OneinchTests is DSTest {
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

    address wethAddr;
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
    WethAbstract weth;
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
        wethAddr = chainLog.getAddress('ETH');
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
        weth = WethAbstract(wethAddr);
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
    OneinchCallee dan;
    address danAddr;
    address ONE_INCH_ROUTER;
    bytes ONE_INCH_PARAMETERS;

    function getPermissions() private {
        hevm.store(dogAddr, keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));
        hevm.store(vatAddr, keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));
        hevm.store(linkPipAddr, keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));
        linkPip.kiss(address(this));
    }

    function setEnvVars() private {
        uint256 ONE_INCH_BLOCK = hevm.envOr('ONE_INCH_BLOCK', 16327090);
        hevm.rollFork(ONE_INCH_BLOCK);
        log_named_uint('loaded ONE_INCH_BLOCK env var:', ONE_INCH_BLOCK);
        ONE_INCH_ROUTER = hevm.envOr('ONE_INCH_ROUTER', 0x1111111254EEB25477B68fb85Ed929f73A960582);
        log_named_address('loaded ONE_INCH_ROUTER env var:', ONE_INCH_ROUTER);
        ONE_INCH_PARAMETERS = hevm.envOr(
            'ONE_INCH_PARAMETERS',
            hex'00000000000000000000000053222470cdcfb8081c0e3a50fd106f0d69e63f2000000000000000000000000053222470cdcfb8081c0e3a50fd106f0d69e63f20000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c10000000000000000000000000000000000000001a300017500012b00001a0020d6bdbf78514910771af9ca656af840dff83e8264ecf986ca00a007e5c0d20000000000000000000000000000000000000000000000ed00009e00004f02a00000000000000000000000000000000000000000000000000000000000000001ee63c1e501a6cc3c2531fdaa6ae1a3ca84c2855806728693e8514910771af9ca656af840dff83e8264ecf986ca02a00000000000000000000000000000000000000000000000000000000000000001ee63c1e50088e6a0c2ddd26feeb64f039a2c41296fcb3f5640c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0fbb7cd060006df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000063a0b86991c6218b36c1d19d4a2e9eb0ce3606eb486b175474e89094c44da98b954eedeac495271d0f00a0f2fa6b666b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000c0c1f36669d98b707650000000000000000455dd6045965672880a06c4eca276b175474e89094c44da98b954eedeac495271d0f1111111254eeb25477b68fb85ed929f73a96058200000000000000000000000000000000000000000000000000000000000000'
        );
        log_named_bytes('loaded ONE_INCH_PARAMETERS env var:', ONE_INCH_PARAMETERS);
    }

    function setUp() public {
        setAddresses();
        setInterfaces();
        setEnvVars();
        ali = new VaultHolder(vat);
        aliAddr = address(ali);
        dan = new OneinchCallee(daiJoinAddr);
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

    function takeLink(
        uint256 auctionId,
        uint256 amt,
        uint256 max,
        uint256 minProfit
    ) public {
        vat.hope(linkClipAddr);
        link.approve(ONE_INCH_ROUTER, amt);
        bytes memory data = abi.encode(
            danAddr,
            linkJoinAddr,
            minProfit,
            ONE_INCH_ROUTER,
            ONE_INCH_PARAMETERS,
            address(0)
        );
        linkClip.take(auctionId, amt, max, danAddr, data);
    }

    function testTakeLinkOneinchProfit() public {
        uint256 minProfitPct = 30;
        (, , , , uint256 dustRad) = vat.ilks(linkName);
        uint256 amountLink = (dustRad / getLinkPriceRay()) * 2;
        getLink(amountLink);
        joinLink(amountLink);
        frobMax(amountLink, linkName);
        drip(linkName);
        uint256 auctionId = barkLink();
        (, uint256 auctionPrice, , ) = linkClip.getStatus(auctionId);
        uint256 linkPrice = getLinkPrice();
        while (((((auctionPrice / uint256(1e9)) * 11) / 10) * (100 + minProfitPct)) / 100 > linkPrice) {
            hevm.warp(block.timestamp + 10 minutes);
            (, auctionPrice, , ) = linkClip.getStatus(auctionId);
        }
        uint256 minProfit = (((amountLink * auctionPrice) / RAY) * minProfitPct) / 100;
        assertEq(dai.balanceOf(danAddr), 0);
        takeLink(auctionId, amountLink, auctionPrice, minProfit);
        assertGe(dai.balanceOf(danAddr), minProfit);
    }
}
