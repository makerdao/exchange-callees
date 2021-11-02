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

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";
import { UniswapV2CalleeDai } from "../UniswapV2Callee.sol";
import { UniswapV2LpTokenCalleeDai } from "../UniswapV2LpTokenCallee.sol";
import { UniV3Callee } from "../UniV3Callee.sol";

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

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) 
        external pure returns (uint amountIn);
}

interface UniV3Like {

    struct Params {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(Params calldata params)
        external returns (uint256 amountOut);

}

interface WethAbstract is GemAbstract {
    function deposit() external payable;
}

interface LpTokenAbstract is GemAbstract {
    function getReserves() external view 
    returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract VaultHolder {
    constructor(VatAbstract vat) public {
        vat.hope(msg.sender);
    }
}

contract SimulationTests is DSTest {

    // mainnet UniswapV2Router02 address
    address constant uniAddr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    // mainnet UniV3 SwapRouter address
    address constant swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address constant hevmAddr = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    bytes32 constant linkName = "LINK-A";
    bytes32 constant lpDaiEthName = "UNIV2DAIETH-A";

    uint256 constant WAD = 1E18;
    uint256 constant RAY = 1E27;
    uint256 constant RAD = 1E45;

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y / WAD;
    }

    function sqrt (uint256 _x) internal pure returns (uint128) {
        if (_x == 0) return 0;
        else {
            uint256 xx = _x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
            if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
            if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
            if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
            if (xx >= 0x100) { xx >>= 8; r <<= 4; }
            if (xx >= 0x10) { xx >>= 4; r <<= 2; }
            if (xx >= 0x8) { r <<= 1; }
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1; // Seven iterations should be enough
            uint256 r1 = _x / r;
            return uint128 (r < r1 ? r : r1);
        }
    }

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
    address lpDaiEthPipAddr;
    address linkPipAddr;
    address ethPipAddr;

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
    ClipAbstract lpDaiEthClip;
    GemJoinAbstract lpDaiEthJoin;
    LPOsmAbstract lpDaiEthPip;
    OsmAbstract linkPip;
    OsmAbstract ethPip;

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
        lpDaiEthClipAddr = chainLog.getAddress("MCD_CLIP_UNIV2DAIETH_A");
        lpDaiEthAddr = chainLog.getAddress("UNIV2DAIETH");
        lpDaiEthJoinAddr = chainLog.getAddress("MCD_JOIN_UNIV2DAIETH_A");
        vowAddr = chainLog.getAddress("MCD_VOW");
        lpDaiEthPipAddr = chainLog.getAddress("PIP_UNIV2DAIETH");
        linkPipAddr = chainLog.getAddress("PIP_LINK");
        ethPipAddr = chainLog.getAddress("PIP_ETH");
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
        lpDaiEthClip = ClipAbstract(lpDaiEthClipAddr);
        lpDaiEth = LpTokenAbstract(lpDaiEthAddr);
        lpDaiEthJoin = GemJoinAbstract(lpDaiEthJoinAddr);
        lpDaiEthPip = LPOsmAbstract(lpDaiEthPipAddr);
        linkPip = OsmAbstract(linkPipAddr);
        ethPip = OsmAbstract(ethPipAddr);
    }

    VaultHolder ali;
    address aliAddr;
    UniswapV2CalleeDai bob;
    address bobAddr;
    UniswapV2LpTokenCalleeDai che;
    address cheAddr;
    UniV3Callee dan;
    address danAddr;

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
        lpDaiEthPip.kiss(address(this));
        hevm.store(
            linkPipAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        linkPip.kiss(address(this));
        hevm.store(
            ethPipAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        ethPip.kiss(address(this));
    }

    function setUp() public {
        setAddresses();
        setInterfaces();
        ali = new VaultHolder(vat);
        aliAddr = address(ali);
        bob = new UniswapV2CalleeDai(uniAddr, daiJoinAddr);
        bobAddr = address(bob);
        che = new UniswapV2LpTokenCalleeDai(uniAddr, daiJoinAddr);
        cheAddr = address(che);
        dan = new UniV3Callee(uniAddr, daiJoinAddr);
        danAddr = address(dan);
        getPermissions();
    }

    function getLinkPrice() private view returns (uint256 val) {
        val = uint256(linkPip.read());
    }

    function testGetLinkPrice() public {
        uint256 price = getLinkPrice();
        assertGt(price, 0);
        log_named_uint("LINK price", price / WAD);
    }

    function getEthPrice() private view returns (uint256 val) {
        val = uint256(ethPip.read());
    }

    function testGetEthPrice() public {
        uint256 price = getEthPrice();
        assertGt(price, 0);
        log_named_uint("ETH price", price / WAD);
    }

    function getLpDaiEthPrice() private view returns (uint256 val) {
        val = uint256(lpDaiEthPip.read());
    }

    function testGetLpDaiEthPrice() public {
        uint256 price = getLpDaiEthPrice();
        assertGt(price, 0);
        log_named_uint("LP DAI ETH price", price / WAD);
    }

    function getWeth(uint256 amount) private {
        weth.deposit{ value: amount }();
    }

    function testGetWeth() public {
        uint256 amount = 15 * WAD;
        assertEq(weth.balanceOf(address(this)), 0);
        getWeth(amount);
        assertEq(weth.balanceOf(address(this)), amount);
    }

    function getDai(uint256 amountDai) private {
        (uint112 reserveDai, uint112 reserveWeth, ) = lpDaiEth.getReserves();
        uint256 amountWeth = uniRouter.getAmountIn(amountDai, reserveWeth, reserveDai);
        getWeth(amountWeth);
        weth.approve(uniAddr, amountWeth);
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
    }

    function testGetDai() public {
        uint256 amountDai = 10 * WAD;
        uint256 daiPre = dai.balanceOf(address(this));
        getDai(amountDai);
        uint256 daiPost = dai.balanceOf(address(this));
        assertGt(daiPost, daiPre + amountDai);
        assertEq(daiPost / 10_000, (daiPre + amountDai) / 10_000);
    }

    function getLpDaiEth(uint256 amountLp) private {
        uint256 totalSupply = lpDaiEth.totalSupply();
        (uint112 reserveDai, uint112 reserveWeth,) = lpDaiEth.getReserves();
        uint256 amountDai = amountLp * reserveDai / totalSupply * 11 / 10;
        uint256 amountEth = amountLp * reserveWeth / totalSupply * 11 / 10;
        getDai(amountDai);
        dai.approve(uniAddr, amountDai);
        uniRouter.addLiquidityETH{value: amountEth}({
            token: daiAddr,
            amountTokenDesired: amountDai,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
    }

    receive() external payable {}

    function testGetLpDaiEth() public {
        assertEq(lpDaiEth.balanceOf(address(this)), 0);
        uint256 expected = 1000 * WAD;
        getLpDaiEth(expected);
        uint256 actual = lpDaiEth.balanceOf(address(this));
        assertGt(actual, expected);
        assertLt(actual - expected, actual / 10);
    }

    function burnLpDaiEth(uint256 amount) private {
        uniRouter.removeLiquidity({
            tokenA: daiAddr,
            tokenB: wethAddr,
            liquidity: amount,
            amountAMin: 0,
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
    }

    function testBurnLpDaiEth() public {
        uint256 amount = 30 * WAD;
        getLpDaiEth(amount);
        assertGt(lpDaiEth.balanceOf(address(this)), amount);
        assertLt(dai.balanceOf(address(this)), 1 * WAD);
        assertEq(weth.balanceOf(address(this)), 0);
        lpDaiEth.approve(uniAddr, amount);
        burnLpDaiEth(amount);
        assertLt(lpDaiEth.balanceOf(address(this)), amount / 10);
        assertGt(dai.balanceOf(address(this)), 1 * WAD);
        assertGt(dai.balanceOf(address(this)), 1 * WAD);
    }

    function getLink(uint256 amountLink) private {
        uint256 linkPrice = getLinkPrice();
        uint256 ethPrice = getEthPrice();
        uint256 amountWeth = amountLink * linkPrice / ethPrice * 11 / 10;
        getWeth(amountWeth);
        weth.approve(uniAddr, amountWeth);
        address[] memory path = new address[](2);
        path[0] = wethAddr;
        path[1] = linkAddr;
        uniRouter.swapExactTokensForTokens({
            amountIn: amountWeth,
            amountOutMin: 0,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });
    }

    function testGetLink() public {
        uint256 amount = 10 * WAD;
        assertEq(link.balanceOf(address(this)), 0);
        getLink(amount);
        assertGt(link.balanceOf(address(this)), amount);
        assertLt(
            link.balanceOf(address(this)) - amount,
            link.balanceOf(address(this)) / 5
        );
    }

    function swapLinkDai(uint256 amountLink) private {
        link.approve(uniAddr, amountLink);
        address[] memory path = new address[](3);
        path[0] = linkAddr;
        path[1] = wethAddr;
        path[2] = daiAddr;
        uniRouter.swapExactTokensForTokens({
            amountIn: amountLink,
            amountOutMin: 0,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });
    }

    function testSwapLinkDai() public {
        uint256 amountLink = 100 * WAD;
        getLink(amountLink);
        assertEq(dai.balanceOf(address(this)), 0);
        swapLinkDai(amountLink);
        uint256 linkPrice = getLinkPrice();
        uint256 expected = amountLink * linkPrice / WAD;
        uint256 actual = dai.balanceOf(address(this));
        uint256 diff = expected > actual ? 
        expected - actual : actual - expected;
        assertLt(diff, expected / 10);
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

    function joinLpDaiEth(uint256 amount) private {
        lpDaiEth.approve(lpDaiEthJoinAddr, amount);
        lpDaiEthJoin.join(aliAddr, amount);
    }

    function testJoinLpDaiEth() public {
        uint256 amount = 10 * WAD;
        getLpDaiEth(amount);
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
        uint256 amountLink = 2_000 * WAD;
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
        uint256 amountLink = 2_000 * WAD;
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

    function barkLpDaiEth() private returns (uint256 auctionId) {
        dog.bark(lpDaiEthName, aliAddr, aliAddr);
        auctionId = lpDaiEthClip.kicks();
    }

    function testBarkLpDaiEth() public {
        uint256 amount = 100 * WAD;
        uint256 kicksPre = lpDaiEthClip.kicks();
        getLpDaiEth(amount);
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
        uint24 fee = 3000;
        bytes memory data = abi.encode(
            danAddr,
            linkJoinAddr,
            minProfit,
            abi.encodePacked(linkAddr, fee, wethAddr, fee, daiAddr),
            address(0)
        );
        linkClip.take(auctionId, amt, max, danAddr, data);
    }

    function testTakeLinkNoProfit() public {
        (,,,, uint256 dustRad) = vat.ilks(linkName);
        uint256 amountLink = dustRad / RAY;
        getLink(amountLink);
        joinLink(amountLink);
        frobMax(amountLink, linkName);
        drip(linkName);
        uint256 auctionId = barkLink();
        (, uint256 auctionPrice,,) = linkClip.getStatus(auctionId);
        uint256 linkPrice = getLinkPrice();
        while (auctionPrice / uint256(1e9) * 11 / 10 > linkPrice) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = linkClip.getStatus(auctionId);
        }
        assertEq(dai.balanceOf(bobAddr), 0);
        takeLink(auctionId, amountLink, auctionPrice, 0);
        assertLt(dai.balanceOf(bobAddr), amountLink * auctionPrice / RAY / 5);
    }

    function testTakeLinkProfit() public {
        uint256 minProfitPct = 30;
        (,,,, uint256 dustRad) = vat.ilks(linkName);
        uint256 amountLink = dustRad / RAY;
        getLink(amountLink);
        joinLink(amountLink);
        frobMax(amountLink, linkName);
        drip(linkName);
        uint256 auctionId = barkLink();
        (, uint256 auctionPrice,,) = linkClip.getStatus(auctionId);
        uint256 linkPrice = getLinkPrice();
        while (
            auctionPrice / uint256(1e9) * 11 / 10 * (100 + minProfitPct) / 100
            > linkPrice
        ) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = linkClip.getStatus(auctionId);
        }
        uint256 minProfit = amountLink * auctionPrice / RAY 
            * minProfitPct / 100;
        assertEq(dai.balanceOf(bobAddr), 0);
        takeLink(auctionId, amountLink, auctionPrice, minProfit);
        assertGe(dai.balanceOf(bobAddr), minProfit);
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
        lpDaiEthClip.take(auctionId, amt, max, cheAddr, data);
    }

    function testTakeLpDaiEthNoProfit() public {
        (,,,, uint256 dustRad) = vat.ilks(lpDaiEthName);
        uint256 amount = dustRad / RAY;
        getLpDaiEth(amount);
        joinLpDaiEth(amount);
        frobMax(amount, lpDaiEthName);
        drip(lpDaiEthName);
        uint256 auctionId = barkLpDaiEth();
        (, uint256 auctionPrice,,) = lpDaiEthClip.getStatus(auctionId);
        uint256 lpDaiEthPrice = getLpDaiEthPrice();
        while (auctionPrice / uint256(1e9) * 11 / 10 > lpDaiEthPrice) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = lpDaiEthClip.getStatus(auctionId);
        }
        assertEq(dai.balanceOf(bobAddr), 0);
        takeLpDaiEth(auctionId, amount, auctionPrice, 0);
        assertLt(dai.balanceOf(bobAddr), amount * auctionPrice / RAY / 5);
    }

    function testTakeLpDaiEthProfit() public {
        uint256 minProfitPct = 30;
        (,,,, uint256 dustRad) = vat.ilks(lpDaiEthName);
        uint256 amount = dustRad / RAY;
        getLpDaiEth(amount);
        joinLpDaiEth(amount);
        frobMax(amount, lpDaiEthName);
        drip(lpDaiEthName);
        uint256 auctionId = barkLpDaiEth();
        (, uint256 auctionPrice,,) = lpDaiEthClip.getStatus(auctionId);
        uint256 lpDaiEthPrice = getLpDaiEthPrice();
        while (
            auctionPrice / uint256(1e9) * 11 / 10 * (100 + minProfitPct) / 100
            > lpDaiEthPrice
        ) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = lpDaiEthClip.getStatus(auctionId);
        }
        uint256 minProfit = amount * auctionPrice / RAY 
            * minProfitPct / 100;
        assertEq(dai.balanceOf(bobAddr), 0);
        takeLpDaiEth(auctionId, amount, auctionPrice, minProfit);
        assertGe(dai.balanceOf(bobAddr), minProfit);
    }
}
