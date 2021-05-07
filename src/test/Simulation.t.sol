// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Maker Ecosystem Growth Holdings, INC.
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

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";
import { UniswapV2CalleeDai } from "../UniswapV2Callee.sol";

interface Hevm {
    function warp(uint256) external;
}

interface UniV2Router02Abstract {

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint[] memory amounts);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (
        uint amountToken,
        uint amountETH,
        uint liquidity
    );

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
}

interface WethAbstract is GemAbstract {
    function deposit() external payable;
}

contract Constants {

    // mainnet UniswapV2Router02 address
    address constant uniAddr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant hevmAddr = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    uint256 constant WAD = 1E18;
    uint256 constant RAY = 1E27;
    bytes32 constant linkName = "LINK-A";

    address wethAddr;
    address linkAddr;
    address daiAddr;
    address vatAddr;
    address linkJoinAddr;
    address spotterAddr;
    address daiJoinAddr;
    address dogAddr;
    address jugAddr;
    address clipAddr;
    address lpDaiEthAddr;

    Hevm hevm;
    UniV2Router02Abstract uniRouter;
    WethAbstract weth;
    GemAbstract link;
    VatAbstract vat;
    DaiAbstract dai;
    GemJoinAbstract linkJoin;
    DogAbstract dog;
    JugAbstract jug;
    ClipAbstract clip;
    GemAbstract lpDaiEth;

    UniswapV2CalleeDai callee;

    function setAddresses() private {
        ChainlogHelper helper = new ChainlogHelper();
        ChainlogAbstract chainLog = helper.ABSTRACT();
        wethAddr = chainLog.getAddress("ETH");
        linkAddr = chainLog.getAddress("LINK");
        vatAddr = chainLog.getAddress("MCD_VAT");
        daiAddr = chainLog.getAddress("MCD_DAI");
        linkJoinAddr = chainLog.getAddress("MCD_JOIN_LINK_A");
        spotterAddr = chainLog.getAddress("MCD_SPOT");
        daiJoinAddr = chainLog.getAddress("MCD_JOIN_DAI");
        dogAddr = chainLog.getAddress("MCD_DOG");
        jugAddr = chainLog.getAddress("MCD_JUG");
        clipAddr = chainLog.getAddress("MCD_CLIP_LINK_A");
        lpDaiEthAddr = chainLog.getAddress("UNIV2DAIETH");
    }

    function setInterfaces() private {
        hevm = Hevm(hevmAddr);
        uniRouter = UniV2Router02Abstract(uniAddr);
        weth = WethAbstract(wethAddr);
        link = GemAbstract(linkAddr);
        vat = VatAbstract(vatAddr);
        dai = DaiAbstract(daiAddr);
        linkJoin = GemJoinAbstract(linkJoinAddr);
        dog = DogAbstract(dogAddr);
        jug = JugAbstract(jugAddr);
        clip = ClipAbstract(clipAddr);
        lpDaiEth = GemAbstract(lpDaiEthAddr);
    }

    function deployContracts() private {
        callee = new UniswapV2CalleeDai(uniAddr, daiJoinAddr);
    }

    constructor () public {
        setAddresses();
        setInterfaces();
        deployContracts();
    }
}

contract VaultHolder is Constants {

    constructor() public {
        weth.approve(uniAddr, type(uint256).max);
        link.approve(uniAddr, type(uint256).max);
        link.approve(msg.sender, type(uint256).max);
        vat.hope(msg.sender);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        uniRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }
}

contract SimulationTests is DSTest, Constants {

    VaultHolder ali;
    address aliAddr;
    UniswapV2CalleeDai bob;
    address bobAddr;

    function setUp() public {
        ali = new VaultHolder();
        aliAddr = address(ali);
        bob = new UniswapV2CalleeDai(uniAddr, daiJoinAddr);
        bobAddr = address(bob);
    }

    function wrapEth(uint256 value, address to) private {
        weth.deposit{ value: value }();
        weth.transfer(to, value);
    }

    function testWrapEth() public {
        uint256 balancePre = weth.balanceOf(aliAddr);
        uint256 value = 1 * WAD;
        wrapEth(value, aliAddr);
        uint256 balancePost = weth.balanceOf(aliAddr);
        assertEq(balancePost, balancePre + value);
    }

    function swapEthDai(uint256 amountIn, uint256 amountOutMin) private {
        address[] memory path = new address[](2);
        path[0] = wethAddr;
        path[1] = daiAddr;
        uniRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });
    }

    function testSwapEthDai() public {
        wrapEth(1 * WAD, address(this));
        weth.approve(uniAddr, type(uint256).max);
        uint256 amountIn = 1 * WAD;
        uint256 amountOutMin = 100 * WAD;
        uint256 wethPre = weth.balanceOf(address(this));
        uint256 daiPre = dai.balanceOf(address(this));
        swapEthDai(amountIn, amountOutMin);
        uint256 wethPost = weth.balanceOf(address(this));
        uint256 daiPost = dai.balanceOf(address(this));
        assertEq(wethPost, wethPre - amountIn);
        assertGe(daiPost, daiPre + amountOutMin);
    }

    function getLpDaiEth() private {
        uniRouter.addLiquidityETH{value: 1 ether}({
            token: daiAddr,
            amountTokenDesired: 3000 * WAD,
            amountTokenMin: 50 * WAD,
            amountETHMin: 1 szabo,
            to: address(this),
            deadline: block.timestamp + 1 days
        });
    }

    receive() external payable {}

    function testGetLpDaiEth() public {
        wrapEth(1 * WAD, address(this));
        weth.approve(uniAddr, type(uint256).max);
        swapEthDai(1 * WAD, 100 * WAD);
        dai.approve(uniAddr, type(uint256).max);
        uint256 lpDaiEthPre = lpDaiEth.balanceOf(address(this));
        getLpDaiEth();
        uint256 lpDaiEthPost = lpDaiEth.balanceOf(address(this));
        assertGt(lpDaiEthPost, lpDaiEthPre);
    }

    function burnLpDaiEth() private {
        uniRouter.removeLiquidityETH({
            token: daiAddr,
            liquidity: 30 * WAD,
            amountTokenMin: 1 * WAD,
            amountETHMin: 1 szabo,
            to: address(this),
            deadline: block.timestamp + 1 days
        });
    }

    function testBurnLpDaiEth() public {
        wrapEth(1 * WAD, address(this));
        weth.approve(uniAddr, type(uint256).max);
        swapEthDai(1 * WAD, 100 * WAD);
        dai.approve(uniAddr, type(uint256).max);
        getLpDaiEth();
        lpDaiEth.approve(uniAddr, type(uint256).max);
        uint256 lpDaiEthPre = lpDaiEth.balanceOf(address(this));
        uint256 ethPre = address(this).balance;
        burnLpDaiEth();
        uint256 lpDaiEthPost = lpDaiEth.balanceOf(address(this));
        uint256 ethPost = address(this).balance;
        assertLt(lpDaiEthPost, lpDaiEthPre);
        assertGt(ethPost, ethPre);
    }

    function swapEthLink(uint256 amountIn, uint256 amountOutMin) private {
        address[] memory path = new address[](2);
        path[0] = wethAddr;
        path[1] = linkAddr;
        ali.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            path: path,
            to: aliAddr,
            deadline: block.timestamp
        });
    }

    function testSwapEthLink() public {
        wrapEth(10 * WAD, aliAddr);
        uint256 amountIn = 10 * WAD;
        uint256 amountOutMin = 100 * WAD;
        uint256 wethPre = weth.balanceOf(aliAddr);
        uint256 linkPre = link.balanceOf(aliAddr);
        swapEthLink(amountIn, amountOutMin);
        uint256 wethPost = weth.balanceOf(aliAddr);
        uint256 linkPost = link.balanceOf(aliAddr);
        assertEq(wethPost, wethPre - amountIn);
        assertGe(linkPost, linkPre + amountOutMin);
    }

    function swapLinkDai(uint256 amountIn, uint256 amountOutMin) private {
        address[] memory path = new address[](3);
        path[0] = linkAddr;
        path[1] = wethAddr;
        path[2] = daiAddr;
        ali.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            path: path,
            to: aliAddr,
            deadline: block.timestamp
        });
    }

    function testSwapLinkDai() public {
        wrapEth(10 * WAD, aliAddr);
        swapEthLink(10 * WAD, 100 * WAD);
        uint256 linkPre = link.balanceOf(aliAddr);
        uint256 daiPre = dai.balanceOf(aliAddr);
        uint256 amountIn = 100 * WAD;
        uint256 amountOutMin = 1000 * WAD;
        swapLinkDai(amountIn, amountOutMin);
        uint256 linkPost = link.balanceOf(aliAddr);
        uint256 daiPost = dai.balanceOf(aliAddr);
        assertEq(linkPost, linkPre - amountIn);
        assertGe(daiPost, daiPre + amountOutMin);
    }

    function joinLink(uint256 value) private {
        link.transferFrom(aliAddr, address(this), value);
        link.approve(linkJoinAddr, type(uint256).max);
        linkJoin.join(aliAddr, value);
    }

    function testJoinLink() public {
        uint256 value = 100 * WAD;
        wrapEth(10 * WAD, aliAddr);
        swapEthLink(10 * WAD, value);
        joinLink(value);
        assertEq(vat.gem(linkName, aliAddr), value);
    }

    function frobMax(uint256 gem) private {
        uint256 ink = gem;
        (, uint256 rate, uint256 spot, ,) = vat.ilks(linkName);
        uint256 art = ink * spot / rate;
        vat.frob(linkName, aliAddr, aliAddr, aliAddr, int256(ink), int256(art));
    }

    function testFrobMax() public {
        wrapEth(50 * WAD, aliAddr);
        swapEthLink(50 * WAD, 500 * WAD);
        joinLink(500 * WAD);
        frobMax(500 * WAD);
        assertEq(vat.gem(linkName, aliAddr), 0);
        (uint256 ink, uint256 actualArt) = vat.urns(linkName, aliAddr);
        assertEq(ink, 500 * WAD);
        (, uint256 rate, uint256 spot, ,) = vat.ilks(linkName);
        uint256 expectedArt = ink * spot / rate;
        assertEq(actualArt, expectedArt);
    }

    function drip() private {
        jug.drip(linkName);
    }

    function testDrip() public {
        (, uint256 ratePre, , , ) = vat.ilks(linkName);
        drip();
        (, uint256 ratePost, , , ) = vat.ilks(linkName);
        assertGt(ratePost, ratePre);
    }

    function bark() private returns (uint256 auctionId) {
        dog.bark(linkName, aliAddr, aliAddr);
        auctionId = clip.kicks();
    }

    function testBark() public {
        uint256 kicksPre = clip.kicks();
        wrapEth(50 * WAD, aliAddr);
        swapEthLink(50 * WAD, 500 * WAD);
        joinLink(500 * WAD);
        frobMax(500 * WAD);
        drip();
        uint256 auctionId = bark();
        uint256 kicksPost = clip.kicks();
        assertEq(auctionId, kicksPost);
        assertEq(kicksPost, kicksPre + 1);
        (, , uint256 lot, address usr, uint96 tic, ) = clip.sales(auctionId);
        assertEq(usr, aliAddr);
        assertEq(lot, 500 * WAD);
        assertEq(tic, block.timestamp);
    }

    function take(
        uint256 auctionId,
        uint256 amt,
        uint256 max,
        uint256 minProfit
    ) public {
        vat.hope(clipAddr);
        address[] memory path = new address[](3);
        path[0] = linkAddr;
        path[1] = wethAddr;
        path[2] = daiAddr;
        bytes memory data = abi.encode(bobAddr, linkJoinAddr, minProfit, path);
        clip.take(auctionId, amt, max, bobAddr, data);
    }

    function testTakeBasic() public {
        wrapEth(50 * WAD, aliAddr);
        swapEthLink(50 * WAD, 500 * WAD);
        joinLink(500 * WAD);
        frobMax(500 * WAD);
        drip();
        uint256 auctionId = bark();
        hevm.warp(block.timestamp + 50 minutes);
        take(auctionId, 500 * WAD, 500 * RAY, 0);
    }

    function testTakeNoProfit() public {
        wrapEth(50 * WAD, aliAddr);
        swapEthLink(50 * WAD, 500 * WAD);
        joinLink(500 * WAD);
        frobMax(500 * WAD);
        drip();
        uint256 auctionId = bark();
        hevm.warp(block.timestamp + 50 minutes);
        uint256 daiBobPre = dai.balanceOf(bobAddr);
        uint256 linkBobPre = link.balanceOf(bobAddr);
        take(auctionId, 500 * WAD, 500 * RAY, 0);
        uint256 daiBobPost = dai.balanceOf(bobAddr);
        uint256 linkBobPost = link.balanceOf(bobAddr);
        assertGe(daiBobPost, daiBobPre);
        assertEq(linkBobPre, linkBobPost);
    }

    function testTakeProfit() public {
        wrapEth(50 * WAD, aliAddr);
        swapEthLink(50 * WAD, 500 * WAD);
        joinLink(500 * WAD);
        frobMax(500 * WAD);
        drip();
        uint256 auctionId = bark();
        hevm.warp(block.timestamp + 50 minutes);
        uint256 daiBobPre = dai.balanceOf(bobAddr);
        uint256 linkBobPre = link.balanceOf(bobAddr);
        take(auctionId, 500 * WAD, 500 * RAY, 100 * WAD);
        uint256 daiBobPost = dai.balanceOf(bobAddr);
        uint256 linkBobPost = link.balanceOf(bobAddr);
        assertGt(daiBobPost, daiBobPre + 1 * WAD);
        assertEq(linkBobPre, linkBobPost);
    }

    function testFailTakeInsufficientProfit() public {
        wrapEth(50 * WAD, aliAddr);
        swapEthLink(50 * WAD, 500 * WAD);
        joinLink(500 * WAD);
        frobMax(500 * WAD);
        drip();
        uint256 auctionId = bark();
        hevm.warp(block.timestamp + 50 minutes);
        take(auctionId, 500 * WAD, 500 * RAY, 5000 * WAD);
    }

    function testFailTakeTooExpensive() public {
        wrapEth(50 * WAD, aliAddr);
        swapEthLink(50 * WAD, 500 * WAD);
        joinLink(500 * WAD);
        frobMax(500 * WAD);
        drip();
        uint256 auctionId = bark();
        hevm.warp(block.timestamp + 30 minutes);
        take(auctionId, 500 * WAD, 5 * RAY, 0);
    }
}
