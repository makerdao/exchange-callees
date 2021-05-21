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

import "dss/clip.sol";
import "dss/abaci.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address c, bytes32 loc, bytes32 val) external;
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

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
}

interface WethAbstract is GemAbstract {
    function deposit() external payable;
}

interface LpTokenAbstract is GemAbstract {
    function getReserves() external view 
    returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract Constants {

    // mainnet UniswapV2Router02 address
    address constant uniAddr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant hevmAddr = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    uint256 constant WAD = 1E18;
    uint256 constant RAY = 1E27;
    uint256 constant RAD = 1E45;

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y / WAD;
    }

    bytes32 constant linkName = "LINK-A";
    bytes32 constant lpDaiEthName = "UNIV2DAIETH-A";

    address wethAddr;
    address linkAddr;
    address daiAddr;
    address vatAddr;
    address linkJoinAddr;
    address spotterAddr;
    address daiJoinAddr;
    address dogAddr;
    address jugAddr;
    address linkClipAddr;
    address lpDaiEthAddr;
    address lpDaiEthJoinAddr;
    address lpDaiEthClipAddr;
    address vowAddr;
    address lpDaiEthCalcAddr;
    address lpDaiEthPipAddr;
    address linkPipAddr;

    Hevm hevm;
    UniV2Router02Abstract uniRouter;
    WethAbstract weth;
    GemAbstract link;
    VatAbstract vat;
    DaiAbstract dai;
    GemJoinAbstract linkJoin;
    DogAbstract dog;
    JugAbstract jug;
    ClipAbstract linkClip;
    LpTokenAbstract lpDaiEth;
    GemJoinAbstract lpDaiEthJoin;
    LPOsmAbstract lpDaiEthPip;
    OsmAbstract linkPip;

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
        linkClipAddr = chainLog.getAddress("MCD_CLIP_LINK_A");
        lpDaiEthAddr = chainLog.getAddress("UNIV2DAIETH");
        lpDaiEthJoinAddr = chainLog.getAddress("MCD_JOIN_UNIV2DAIETH_A");
        vowAddr = chainLog.getAddress("MCD_VOW");
        lpDaiEthPipAddr = chainLog.getAddress("PIP_UNIV2DAIETH");
        linkPipAddr = chainLog.getAddress("PIP_LINK");
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
        linkClip = ClipAbstract(linkClipAddr);
        lpDaiEth = LpTokenAbstract(lpDaiEthAddr);
        lpDaiEthJoin = GemJoinAbstract(lpDaiEthJoinAddr);
        lpDaiEthPip = LPOsmAbstract(lpDaiEthPipAddr);
        linkPip = OsmAbstract(linkPipAddr);
    }

    constructor () public {
        setAddresses();
        setInterfaces();
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
    Clipper lpDaiEthClip;
    StairstepExponentialDecrease lpDaiEthCalc;
    UniswapV2CalleeDai callee;

    function getPermissions() private {
        hevm.store(
            dogAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        hevm.store(
            vatAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        hevm.store(
            lpDaiEthPipAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        hevm.store(
            linkPipAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
    }

    function deployLpDaiEthClip() private {
        getPermissions();
        lpDaiEthClip = new Clipper(vatAddr, spotterAddr, dogAddr, lpDaiEthName);
        lpDaiEthClipAddr = address(lpDaiEthClip);
        dog.file(lpDaiEthName, "clip", lpDaiEthClipAddr);
        lpDaiEthClip.file("vow", vowAddr);
        lpDaiEthCalc = new StairstepExponentialDecrease();
        lpDaiEthCalcAddr = address(lpDaiEthCalc);
        lpDaiEthClip.file("calc", lpDaiEthCalcAddr);
        vat.rely(lpDaiEthClipAddr);
        dog.rely(lpDaiEthClipAddr);
        lpDaiEthClip.rely(dogAddr);
        lpDaiEthPip.kiss(lpDaiEthClipAddr);
        dog.file(lpDaiEthName, "hole", 22_000_000 * RAD);
        dog.file(lpDaiEthName, "chop", 113 * WAD / 100);
        lpDaiEthClip.file("buf", 130 * RAY / 100);
        lpDaiEthClip.file("tail", 140 minutes);
        lpDaiEthClip.file("cusp", 40 * RAY / 100);
        lpDaiEthClip.file("chip", 1 * WAD / 1000);
        lpDaiEthClip.file("tip", 0);
        lpDaiEthCalc.file("cut", 99 * RAY / 100);
        lpDaiEthCalc.file("step", 90 seconds);
        lpDaiEthClip.upchost();
    }

    function setUp() public {
        callee = new UniswapV2CalleeDai(uniAddr, daiJoinAddr);
        ali = new VaultHolder();
        aliAddr = address(ali);
        bob = new UniswapV2CalleeDai(uniAddr, daiJoinAddr);
        bobAddr = address(bob);
        deployLpDaiEthClip();
    }

    function getLinkPrice() private returns (uint256 val) {
        linkPip.kiss(address(this));
        val = uint256(linkPip.read());
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

    function swapWethDai(uint256 amountWeth) 
        private returns (uint256 amountDai) {
        address[] memory path = new address[](2);
        path[0] = wethAddr;
        path[1] = daiAddr;
        uniRouter.swapExactTokensForTokens({
            amountIn: amountWeth,
            amountOutMin: 0,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });
        amountDai = dai.balanceOf(address(this));
    }

    function testSwapWethDai() public {
        uint256 amountEth = 1 * WAD;
        wrapEth(amountEth, address(this));
        weth.approve(uniAddr, type(uint256).max);
        uint256 wethPre = weth.balanceOf(address(this));
        uint256 daiPre = dai.balanceOf(address(this));
        uint256 amountDai = swapWethDai(amountEth);
        uint256 wethPost = weth.balanceOf(address(this));
        uint256 daiPost = dai.balanceOf(address(this));
        assertEq(wethPost, wethPre - amountEth);
        assertEq(daiPost, daiPre + amountDai);
    }

    function getLpDaiEth(uint256 amountEth) private returns (uint256 amount) {
        (uint112 amountDai, uint112 amountWeth,) = lpDaiEth.getReserves();
        uint256 priceDai = amountDai / amountWeth;
        uniRouter.addLiquidityETH{value: amountEth}({
            token: daiAddr,
            amountTokenDesired: 10 * priceDai * 9 / 10 * WAD,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: address(this),
            deadline: block.timestamp + 1 days
        });
        amount = lpDaiEth.balanceOf(address(this));
    }

    receive() external payable {}

    function testGetLpDaiEth() public {
        wrapEth(10 * WAD, address(this));
        weth.approve(uniAddr, type(uint256).max);
        swapWethDai(10 * WAD);
        dai.approve(uniAddr, type(uint256).max);
        uint256 lpDaiEthPre = lpDaiEth.balanceOf(address(this));
        uint256 amount = getLpDaiEth(10 * WAD);
        uint256 lpDaiEthPost = lpDaiEth.balanceOf(address(this));
        assertGt(amount, WAD);
        assertEq(lpDaiEthPost, lpDaiEthPre + amount);
    }

    function burnLpDaiEth() private {
        uniRouter.removeLiquidity({
            tokenA: daiAddr,
            tokenB: wethAddr,
            liquidity: 30 * WAD,
            amountAMin: 1 * WAD,
            amountBMin: 1 szabo,
            to: address(this),
            deadline: block.timestamp + 1 days
        });
    }

    function testBurnLpDaiEth() public {
        wrapEth(10 * WAD, address(this));
        weth.approve(uniAddr, type(uint256).max);
        swapWethDai(10 * WAD);
        dai.approve(uniAddr, type(uint256).max);
        getLpDaiEth(10 * WAD);
        lpDaiEth.approve(uniAddr, type(uint256).max);
        uint256 lpDaiEthPre = lpDaiEth.balanceOf(address(this));
        uint256 daiPre = dai.balanceOf(address(this));
        uint256 wethPre = weth.balanceOf(address(this));
        burnLpDaiEth();
        uint256 lpDaiEthPost = lpDaiEth.balanceOf(address(this));
        uint256 daiPost = dai.balanceOf(address(this));
        uint256 wethPost = weth.balanceOf(address(this));
        assertLt(lpDaiEthPost, lpDaiEthPre);
        assertGt(daiPost, daiPre);
        assertGt(wethPost, wethPre);
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
        uint256 linkPrice = getLinkPrice();
        uint256 amountOutMin = wmul(amountIn, linkPrice) * 9 / 10;
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

    function joinLpDaiEth(uint256 value) private {
        lpDaiEth.approve(lpDaiEthJoinAddr, value);
        lpDaiEthJoin.join(aliAddr, value);
    }

    function testJoinLpDaiEth() public {
        wrapEth(10 * WAD, address(this));
        weth.approve(uniAddr, type(uint256).max);
        swapWethDai(10 * WAD);
        dai.approve(uniAddr, type(uint256).max);
        uint256 amount = getLpDaiEth(10 * WAD);
        uint256 gemPre = vat.gem(lpDaiEthName, aliAddr);
        joinLpDaiEth(amount);
        uint256 gemPost = vat.gem(lpDaiEthName, aliAddr);
        assertEq(gemPost, gemPre + amount);
    }

    function frobMax(uint256 gem, bytes32 ilkName) private {
        uint256 ink = gem;
        (, uint256 rate, uint256 spot, ,) = vat.ilks(ilkName);
        uint256 art = ink * spot / rate;
        vat.frob(ilkName, aliAddr, aliAddr, aliAddr, int256(ink), int256(art));
    }

    function testFrobMax() public {
        wrapEth(200 * WAD, aliAddr);
        swapEthLink(200 * WAD, 2_000 * WAD);
        joinLink(2_000 * WAD);
        frobMax(2_000 * WAD, linkName);
        assertEq(vat.gem(linkName, aliAddr), 0);
        (uint256 ink, uint256 actualArt) = vat.urns(linkName, aliAddr);
        assertEq(ink, 2_000 * WAD);
        (, uint256 rate, uint256 spot, ,) = vat.ilks(linkName);
        uint256 expectedArt = ink * spot / rate;
        assertEq(actualArt, expectedArt);
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
        uint256 kicksPre = linkClip.kicks();
        wrapEth(200 * WAD, aliAddr);
        swapEthLink(200 * WAD, 2_000 * WAD);
        joinLink(2_000 * WAD);
        frobMax(2_000 * WAD, linkName);
        drip(linkName);
        uint256 auctionId = barkLink();
        uint256 kicksPost = linkClip.kicks();
        assertEq(auctionId, kicksPost);
        assertEq(kicksPost, kicksPre + 1);
        (,, uint256 lot, address usr, uint96 tic,) = linkClip.sales(auctionId);
        assertEq(usr, aliAddr);
        assertEq(lot, 2_000 * WAD);
        assertEq(tic, block.timestamp);
    }

    function barkLpDaiEth() private returns (uint256 auctionId) {
        dog.bark(lpDaiEthName, aliAddr, aliAddr);
        auctionId = lpDaiEthClip.kicks();
    }

    function testBarkLpDaiEth() public {
        uint256 kicksPre = lpDaiEthClip.kicks();
        wrapEth(10 * WAD, address(this));
        weth.approve(uniAddr, type(uint256).max);
        swapWethDai(10 * WAD);
        dai.approve(uniAddr, type(uint256).max);
        uint256 amount = getLpDaiEth(10 * WAD);
        joinLpDaiEth(amount);
        frobMax(amount, lpDaiEthName);
        drip(lpDaiEthName);
        uint256 auctionId = barkLpDaiEth();
        uint256 kicksPost = lpDaiEthClip.kicks();
        assertEq(auctionId, kicksPost);
        assertEq(kicksPost, kicksPre + 1);
        (
         ,, uint256 lot, address usr, uint96 tic,
         ) = lpDaiEthClip.sales(auctionId);
        assertEq(usr, aliAddr);
        assertEq(lot, amount);
        assertEq(tic, block.timestamp);
    }

    function takeLink(
        uint256 auctionId,
        uint256 amt,
        uint256 max,
        uint256 minProfit
    ) public {
        vat.hope(linkClipAddr);
        address[] memory path = new address[](3);
        path[0] = linkAddr;
        path[1] = wethAddr;
        path[2] = daiAddr;
        address[] memory pathB;
        bytes memory data = abi.encode(
            bobAddr,
            linkJoinAddr,
            minProfit,
            path,
            pathB
        );
        linkClip.take(auctionId, amt, max, bobAddr, data);
    }

    function testTakeLinkBasic() public {
        wrapEth(200 * WAD, aliAddr);
        swapEthLink(200 * WAD, 2000 * WAD);
        joinLink(2_000 * WAD);
        frobMax(2_000 * WAD, linkName);
        drip(linkName);
        uint256 auctionId = barkLink();
        hevm.warp(block.timestamp + 1 hours);
        takeLink(auctionId, 2_000 * WAD, 2_000 * RAY, 0);
    }

    function testTakeLinkNoProfit() public {
        wrapEth(200 * WAD, aliAddr);
        swapEthLink(200 * WAD, 2_000 * WAD);
        joinLink(2_000 * WAD);
        frobMax(2_000 * WAD, linkName);
        drip(linkName);
        uint256 auctionId = barkLink();
        hevm.warp(block.timestamp + 1 hours);
        uint256 daiBobPre = dai.balanceOf(bobAddr);
        uint256 linkBobPre = link.balanceOf(bobAddr);
        takeLink(auctionId, 2_000 * WAD, 2_000 * RAY, 0);
        uint256 daiBobPost = dai.balanceOf(bobAddr);
        uint256 linkBobPost = link.balanceOf(bobAddr);
        assertGe(daiBobPost, daiBobPre);
        assertEq(linkBobPre, linkBobPost);
    }

    function testTakeLinkProfit() public {
        wrapEth(200 * WAD, aliAddr);
        swapEthLink(200 * WAD, 2_000 * WAD);
        joinLink(2_000 * WAD);
        frobMax(2_000 * WAD, linkName);
        drip(linkName);
        uint256 auctionId = barkLink();
        hevm.warp(block.timestamp + 1 hours);
        uint256 daiBobPre = dai.balanceOf(bobAddr);
        uint256 linkBobPre = link.balanceOf(bobAddr);
        takeLink(auctionId, 2_000 * WAD, 2_000 * RAY, 50 * WAD);
        uint256 daiBobPost = dai.balanceOf(bobAddr);
        uint256 linkBobPost = link.balanceOf(bobAddr);
        assertGt(daiBobPost, daiBobPre + 1 * WAD);
        assertEq(linkBobPre, linkBobPost);
    }

    function testFailTakeLinkInsufficientProfit() public {
        wrapEth(20 * WAD, aliAddr);
        swapEthLink(20 * WAD, 200 * WAD);
        joinLink(200 * WAD);
        frobMax(200 * WAD, linkName);
        drip(linkName);
        uint256 auctionId = barkLink();
        hevm.warp(block.timestamp + 1 hours);
        takeLink(auctionId, 200 * WAD, 200 * RAY, 5000 * WAD);
    }

    function testFailTakeLinkTooExpensive() public {
        wrapEth(20 * WAD, aliAddr);
        swapEthLink(20 * WAD, 200 * WAD);
        joinLink(200 * WAD);
        frobMax(200 * WAD, linkName);
        drip(linkName);
        uint256 auctionId = barkLink();
        hevm.warp(block.timestamp + 30 minutes);
        takeLink(auctionId, 200 * WAD, 5 * RAY, 0);
    }

    function takeLpDaiEth(
        uint256 auctionId,
        uint256 amt,
        uint256 max,
        uint256 minProfit
    ) public {
        vat.hope(lpDaiEthClipAddr);
        address[] memory pathA;
        address[] memory pathB = new address[](2);
        pathB[0] = wethAddr;
        pathB[1] = daiAddr;
        bytes memory data
            = abi.encode(bobAddr, lpDaiEthJoinAddr, minProfit, pathA, pathB);
        lpDaiEthClip.take(auctionId, amt, max, bobAddr, data);
    }

    function testTakeLpDaiEthBasic() public {
        wrapEth(10 * WAD, address(this));
        weth.approve(uniAddr, type(uint256).max);
        swapWethDai(10 * WAD);
        dai.approve(uniAddr, type(uint256).max);
        uint256 amount = getLpDaiEth(10 * WAD);
        joinLpDaiEth(amount);
        frobMax(amount, lpDaiEthName);
        drip(lpDaiEthName);
        uint256 auctionId = barkLpDaiEth();
        hevm.warp(block.timestamp + 50 minutes);
        takeLpDaiEth(auctionId, amount, 300 * RAY, 0);
    }
}
