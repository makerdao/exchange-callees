// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2023 Maker Ecosystem Growth Holdings, INC.
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

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";
import {UniswapV3SplitCallee} from "src/UniswapV3SplitRouteCallee.sol";

import "dss/clip.sol";
import "dss/abaci.sol";

interface Hevm {
    function warp(uint256) external;
    function rollFork(uint256) external;
    function store(address c, bytes32 loc, bytes32 val) external;
    function load(address, bytes32) external returns (bytes32);
    function envOr(string calldata, uint256) external returns (uint256);
    function envOr(string calldata, address) external returns (address);
    function envOr(string calldata, bytes calldata) external returns (bytes memory);
}

struct UniswapV3ExactInputParams {
    bytes path;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
}

interface WethAbstract is GemAbstract {
    function deposit() external payable;
}

contract VaultHolder {
    constructor(VatAbstract vat_) public {
        vat_.hope(msg.sender);
    }
}

contract UniswapSplitTests is DSTest {
    address constant hevmAddr = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    bytes32 constant linkName = "LINK-A";

    uint256 constant WAD = 1e18;
    uint256 constant RAY = 1e27;
    uint256 constant RAD = 1e45;

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
    WethAbstract    weth;
    GemAbstract     link;
    VatAbstract     vat;
    DaiAbstract     dai;
    GemJoinAbstract linkJoin;
    DogAbstract     dog;
    JugAbstract     jug;
    ClipAbstract    linkClip;

    OsmAbstract linkPip;

    function setAddresses() private {
        ChainlogHelper helper = new ChainlogHelper();
        ChainlogAbstract chainLog = helper.ABSTRACT();
        wethAddr = chainLog.getAddress("ETH");
        linkAddr = chainLog.getAddress("LINK");
        vatAddr = chainLog.getAddress("MCD_VAT");
        daiAddr = chainLog.getAddress("MCD_DAI");
        linkJoinAddr = chainLog.getAddress("MCD_JOIN_LINK_A");
        daiJoinAddr = chainLog.getAddress("MCD_JOIN_DAI");
        dogAddr = chainLog.getAddress("MCD_DOG");
        jugAddr = chainLog.getAddress("MCD_JUG");
        linkClipAddr = chainLog.getAddress("MCD_CLIP_LINK_A");
        linkPipAddr = chainLog.getAddress("PIP_LINK");
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

    VaultHolder          ali;
    UniswapV3SplitCallee dan;

    address aliAddr;
    address danAddr;
    address UniswapV3Router2;
    bytes   uniswapTxDataProfit;
    bytes   uniswapTxDataNoProfit;

    function getPermissions() private {
        hevm.store(dogAddr, keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));
        hevm.store(vatAddr, keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));
        hevm.store(linkPipAddr, keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));
        linkPip.kiss(address(this));
    }

    function setEnvVars() private {
        UniswapV3Router2 = hevm.envOr("UniswapV3Router2", 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
        uniswapTxDataNoProfit = hevm.envOr(
            "UNISWAP_TX_DATA_NO_PROFIT",
            hex"0000000000000000000000000000000000000000000000000000000065ba477d0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000124b858183f00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000dead0000000000000000000000000000000000000000000000b01216b3936f60727d0000000000000000000000000000000000000000000004521f9d637a369a8de90000000000000000000000000000000000000000000000000000000000000059514910771af9ca656af840dff83e8264ecf986ca000bb8c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f4a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000646b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000000000000000000000000"
        );
        uniswapTxDataProfit = hevm.envOr(
            "UNISWAP_TX_DATA_PROFIT",
            hex"0000000000000000000000000000000000000000000000000000000063c7bba90000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000124b858183f00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000dead0000000000000000000000000000000000000000000000eb50c6636ac5f312f00000000000000000000000000000000000000000000005a1d6fc842061b484280000000000000000000000000000000000000000000000000000000000000059514910771af9ca656af840dff83e8264ecf986ca000bb8c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f4a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000646b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000000000000000000000000"
        );

        /* Uncomment the following lines to use historical data related to the hardcoded UNISWAP_TX_DATA_* above */
        /* uint256 uniswapBlock = hevm.envOr("UNISWAP_BLOCK", 16432621); */
        /* hevm.rollFork(uniswapBlock); */
    }

    function setUp() public {
        setAddresses();
        setInterfaces();
        setEnvVars();
        ali = new VaultHolder(vat);
        aliAddr = address(ali);
        dan = new UniswapV3SplitCallee(address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45), daiJoinAddr);
        danAddr = address(dan);
        getPermissions();
    }

    function getLinkPrice() private view returns (uint256 val) {
        val = uint256(linkPip.read());
    }

    function getLinkPriceRay() private view returns (uint256) {
        return getLinkPrice() * 10 ** 9;
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
        (, uint256 rate, uint256 spot,,) = vat.ilks(ilkName);
        uint256 art = (ink * spot) / rate;
        vat.frob(ilkName, aliAddr, aliAddr, aliAddr, int256(ink), int256(art));
    }

    function testFrobMax() public {
        (,,,, uint256 dustRad) = vat.ilks(linkName);
        uint256 amountLink = (dustRad / getLinkPriceRay()) * 2;
        getLink(amountLink);
        joinLink(amountLink);
        frobMax(amountLink, linkName);
        try vat.frob(linkName, aliAddr, aliAddr, aliAddr, 0, 1) {
            log("not at maximum frob");
            fail();
        } catch {
            log("success");
        }
    }

    function drip(bytes32 ilkName) private {
        jug.drip(ilkName);
    }

    function testDrip() public {
        (, uint256 ratePre,,,) = vat.ilks(linkName);
        drip(linkName);
        (, uint256 ratePost,,,) = vat.ilks(linkName);
        assertGt(ratePost, ratePre);
    }

    function barkLink() private returns (uint256 auctionId) {
        dog.bark(linkName, aliAddr, aliAddr);
        auctionId = linkClip.kicks();
    }

    function trimFunctionHash(bytes calldata data) public pure returns (bytes calldata, bytes calldata) {
        return (data[:4], data[4:]);
    }

    function buildCalldata(bytes calldata signature, bytes calldata data) public pure returns (bytes memory) {
        return abi.encodePacked(signature, data);
    }

    function reencodedAutoRouterData(bytes memory txData) private view returns (bytes memory output) {
        (uint256 deadline, bytes[] memory calls) = abi.decode(txData, (uint256, bytes[]));
        bytes[] memory transformedCalls = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bytes memory signature, bytes memory callWithTrimmedHash) = this.trimFunctionHash(calls[i]);
            UniswapV3ExactInputParams memory mCalldata = abi.decode(callWithTrimmedHash, (UniswapV3ExactInputParams));
            UniswapV3ExactInputParams memory modifiedParams = UniswapV3ExactInputParams({
                path: mCalldata.path,
                recipient: address(dan),
                amountIn: mCalldata.amountIn,
                amountOutMinimum: mCalldata.amountOutMinimum
            });
            transformedCalls[i] = this.buildCalldata(signature, abi.encode(modifiedParams));
        }
        output = abi.encode(deadline, transformedCalls);
    }

    function testBarkLink() public {
        (,,,, uint256 dustRad) = vat.ilks(linkName);
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
        (,, uint256 lot, address usr, uint96 tic,) = linkClip.sales(auctionId);
        assertEq(usr, aliAddr);
        assertEq(lot, amountLink);
        assertEq(tic, block.timestamp);
    }

    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _add(x, _sub(y, 1)) / y;
    }

    function takeLink(uint256 auctionId, uint256 amt, uint256 max, uint256 minProfit, bytes memory txData) public {
        vat.hope(linkClipAddr);
        link.approve(UniswapV3Router2, amt);
        bytes memory data = abi.encode(danAddr, linkJoinAddr, minProfit, address(0), reencodedAutoRouterData(txData));
        linkClip.take(auctionId, amt, max, danAddr, data);
    }

    function createLinkAuction()
        private
        returns (uint256 auctionId, uint256 amountLinkWad, uint256 auctionPrice, uint256 auctionDebt)
    {
        (,,,, uint256 dustRad) = vat.ilks(linkName);
        amountLinkWad = (dustRad / getLinkPriceRay()) * 2;
        getLink(amountLinkWad);
        joinLink(amountLinkWad);
        frobMax(amountLinkWad, linkName);
        drip(linkName);
        auctionId = barkLink();
        uint256 lot;
        (, auctionPrice, lot, auctionDebt) = linkClip.getStatus(auctionId);
    }

    function testTakeLinkUniswapSplitProfit() public {
        uint256 minProfitPct = 30;
        uint256 linkPrice = getLinkPrice();
        (uint256 auctionId, uint256 amountLinkWad, uint256 auctionPrice,) = createLinkAuction();
        while (((((auctionPrice / uint256(1e9)) * 11) / 10) * (100 + minProfitPct)) / 100 > linkPrice) {
            hevm.warp(block.timestamp + 10 minutes);
            (, auctionPrice,,) = linkClip.getStatus(auctionId);
        }
        uint256 minProfit = (((amountLinkWad * auctionPrice) / RAY) * minProfitPct) / 100;
        assertEq(dai.balanceOf(danAddr), 0);
        takeLink(auctionId, amountLinkWad, auctionPrice, minProfit, uniswapTxDataProfit);
        assertGe(dai.balanceOf(danAddr), minProfit);
    }

    function testTakeLinkUniswapSplitNoProfit() public {
        uint256 linkPriceWad = getLinkPrice();
        (uint256 auctionId, uint256 amountLinkWad, uint256 auctionPriceRay, uint256 tabRad) = createLinkAuction();
        // the condition of the loop is different from the rest of the test because the liuidation happens for the whole auction amount, with the least profit possible.
        while (auctionPriceRay / uint256(1e9) * 11 / 10 > linkPriceWad) {
            // wait for the price to be so that we can liquidate the whole vault;
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPriceRay,,) = linkClip.getStatus(auctionId);
        }
        assertEq(dai.balanceOf(danAddr), 0);
        uint256 oweRad = auctionPriceRay * amountLinkWad;
        takeLink(auctionId, amountLinkWad, auctionPriceRay, 0, uniswapTxDataNoProfit);
        assertLt(dai.balanceOf(danAddr), amountLinkWad * auctionPriceRay / RAY / 5);
    }

    function testFailTakeLinkUniswapSplitTooMuchProfit() public {
        uint256 linkPrice = getLinkPrice();
        (uint256 auctionId, uint256 amountLinkRay, uint256 auctionPrice,) = createLinkAuction();
        while (auctionPrice / uint256(1e9) * 11 / 10 > linkPrice) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = linkClip.getStatus(auctionId);
        }
        assertEq(dai.balanceOf(danAddr), 0);
        uint256 tooMuchProfit = ((amountLinkRay * auctionPrice) / RAY) * 10;
        takeLink(auctionId, amountLinkRay, auctionPrice, tooMuchProfit, uniswapTxDataProfit);
    }
}
