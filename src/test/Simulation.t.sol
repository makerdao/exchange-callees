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

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";
import { UniswapV2CalleeDai } from "../UniswapV2Callee.sol";
import { UniswapV2LpTokenCalleeDai } from "../UniswapV2LpTokenCallee.sol";

import { CropManager, CropManagerImp } from "dss-crop-join/CropManager.sol";
import { SushiJoin } from "dss-crop-join/SushiJoin.sol";

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

interface WethAbstract is GemAbstract {
    function deposit() external payable;
}

interface LpTokenAbstract is GemAbstract {
    function getReserves() external view 
    returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface CropManagerLike {
    function join(address crop, address usr, uint256 val) external;
}

contract VaultHolder {
    constructor(VatAbstract vat) public {
        vat.hope(msg.sender);
    }
}

contract SimulationTests is DSTest {

    // mainnet UniswapV2Router02 address
    address constant uniAddr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant sushiAddr = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address constant sushiTokenAddr = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    address constant masterChefAddr = 0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d;
    address constant hevmAddr = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    bytes32 constant linkName = "LINK-A";
    bytes32 constant ulpDaiEthName = "UNIV2DAIETH-A";
    bytes32 constant ulpName = "UNIV2WBTCETH-A";
    bytes32 constant slpName = "SUSHIETHALCX-A";

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
    address ulpDaiEthAddr;
    address ulpDaiEthJoinAddr;
    address ulpDaiEthClipAddr;
    address vowAddr;
    address ulpDaiEthPipAddr;
    address linkPipAddr;
    address ethPipAddr;
    address slpAddr;
    address ulpPipAddr;
    address alcxAddr;
    address slpJoinAddr;
    address sushiManagerAddr;
    address sushiManagerImpAddr;

    Hevm hevm;
    UniV2Router02Abstract uniRouter;
    UniV2Router02Abstract sushiRouter;
    WethAbstract weth;
    GemAbstract link;
    VatAbstract vat;
    DaiAbstract dai;
    GemJoinAbstract linkJoin;
    DogAbstract dog;
    JugAbstract jug;
    ClipAbstract linkClip;
    LpTokenAbstract ulpDaiEth;
    ClipAbstract ulpDaiEthClip;
    GemJoinAbstract ulpDaiEthJoin;
    LPOsmAbstract ulpDaiEthPip;
    OsmAbstract linkPip;
    OsmAbstract ethPip;
    LpTokenAbstract slp;
    LPOsmAbstract ulpPip;
    GemAbstract alcx;
    SushiJoin slpJoin;
    CropManager sushiManager;
    CropManagerImp sushiManagerImp;

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
        ulpDaiEthClipAddr = chainLog.getAddress("MCD_CLIP_UNIV2DAIETH_A");
        ulpDaiEthAddr = chainLog.getAddress("UNIV2DAIETH");
        ulpDaiEthJoinAddr = chainLog.getAddress("MCD_JOIN_UNIV2DAIETH_A");
        vowAddr = chainLog.getAddress("MCD_VOW");
        ulpDaiEthPipAddr = chainLog.getAddress("PIP_UNIV2DAIETH");
        linkPipAddr = chainLog.getAddress("PIP_LINK");
        ethPipAddr = chainLog.getAddress("PIP_ETH");
        slpAddr = 0xC3f279090a47e80990Fe3a9c30d24Cb117EF91a8;
        ulpPipAddr = chainLog.getAddress("PIP_UNIV2WBTCETH");
        alcxAddr = 0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF;
    }

    function setInterfaces() private {
        hevm = Hevm(hevmAddr);
        uniRouter = UniV2Router02Abstract(uniAddr);
        sushiRouter = UniV2Router02Abstract(sushiAddr);
        weth = WethAbstract(wethAddr);
        link = GemAbstract(linkAddr);
        vat = VatAbstract(vatAddr);
        dai = DaiAbstract(daiAddr);
        linkJoin = GemJoinAbstract(linkJoinAddr);
        dog = DogAbstract(dogAddr);
        jug = JugAbstract(jugAddr);
        linkClip = ClipAbstract(linkClipAddr);
        ulpDaiEthClip = ClipAbstract(ulpDaiEthClipAddr);
        ulpDaiEth = LpTokenAbstract(ulpDaiEthAddr);
        ulpDaiEthJoin = GemJoinAbstract(ulpDaiEthJoinAddr);
        ulpDaiEthPip = LPOsmAbstract(ulpDaiEthPipAddr);
        linkPip = OsmAbstract(linkPipAddr);
        ethPip = OsmAbstract(ethPipAddr);
        slp = LpTokenAbstract(slpAddr);
        ulpPip = LPOsmAbstract(ulpPipAddr);
        alcx = GemAbstract(alcxAddr);
    }

    function deployContracts() private {
        sushiManagerImp = new CropManagerImp(vatAddr);
        sushiManagerImpAddr = address(sushiManagerImp);
        sushiManager = new CropManager();
        sushiManagerAddr = address(sushiManager);
        sushiManager.setImplementation(sushiManagerImpAddr);
        uint256 pid = 0;
        address rewarder = 0x7519C93fC5073E15d89131fD38118D73A72370F8;
        address timelock = 0x19B3Eb3Af5D93b77a5619b047De0EED7115A19e7;
        slpJoin = new SushiJoin(
            vatAddr,
            slpName,
            slpAddr,
            sushiTokenAddr,
            masterChefAddr,
            pid,
            address(0),
            rewarder,
            timelock
        );
        slpJoinAddr = address(slpJoin);
        slpJoin.rely(sushiManagerAddr);
        vat.rely(slpJoinAddr);
        vat.init(slpName);
    }

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
            ulpDaiEthPipAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        ulpDaiEthPip.kiss(address(this));
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
        hevm.store(
            ulpPipAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        ulpPip.kiss(address(this));
    }

    VaultHolder ali;
    address aliAddr;
    UniswapV2CalleeDai bob;
    address bobAddr;
    UniswapV2LpTokenCalleeDai che;
    address cheAddr;
    UniswapV2LpTokenCalleeDai dan;
    address danAddr;

    function setUp() public {
        setAddresses();
        setInterfaces();
        ali = new VaultHolder(vat);
        aliAddr = address(ali);
        bob = new UniswapV2CalleeDai(uniAddr, daiJoinAddr);
        bobAddr = address(bob);
        che = new UniswapV2LpTokenCalleeDai(uniAddr, daiJoinAddr);
        cheAddr = address(che);
        dan = new UniswapV2LpTokenCalleeDai(sushiAddr, daiJoinAddr);
        danAddr = address(dan);
        getPermissions();
        deployContracts();
    }

    function getLinkPrice() private returns (uint256 val) {
        val = uint256(linkPip.read());
    }

    function testGetLinkPrice() public {
        uint256 price = getLinkPrice();
        assertGt(price, 0);
        log_named_uint("LINK price", price / WAD);
    }

    function getEthPrice() private returns (uint256 val) {
        val = uint256(ethPip.read());
    }

    function testGetEthPrice() public {
        uint256 price = getEthPrice();
        assertGt(price, 0);
        log_named_uint("ETH price", price / WAD);
    }

    function getLpDaiEthPrice() private returns (uint256 val) {
        val = uint256(ulpDaiEthPip.read());
    }

    function testGetLpDaiEthPrice() public {
        uint256 price = getLpDaiEthPrice();
        assertGt(price, 0);
        log_named_uint("LP DAI ETH price", price / WAD);
    }

    function getSlpPrice() private returns (uint256 val) {
        val = uint256(ulpPip.read());
    }

    function testGetSlpPrice() public {
        uint256 price = getSlpPrice();
        assertGt(price, 0);
        log_named_uint("SLP price", price / WAD);
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
        (uint112 reserveDai, uint112 reserveWeth, ) = ulpDaiEth.getReserves();
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

    function getAlcx(uint256 amountAlcx) private {
        (uint112 reserveAlcx, uint112 reserveWeth, ) = slp.getReserves();
        uint256 amountWeth = sushiRouter.getAmountIn(amountAlcx, reserveWeth, reserveAlcx);
        getWeth(amountWeth);
        weth.approve(sushiAddr, amountWeth);
        address[] memory path = new address[](2);
        path[0] = wethAddr;
        path[1] = alcxAddr;
        sushiRouter.swapExactTokensForTokens({
            amountIn: amountWeth,
            amountOutMin: 0,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });
    }

    function testGetAlcx() public {
        uint256 amountAlcx = 30 * WAD;
        uint256 alcxPre = alcx.balanceOf(address(this));
        getAlcx(amountAlcx);
        uint256 alcxPost = alcx.balanceOf(address(this));
        assertGe(alcxPost, alcxPre + amountAlcx);
    }

    function getLpDaiEth(uint256 amountLp) private {
        uint256 totalSupply = ulpDaiEth.totalSupply();
        (uint112 reserveDai, uint112 reserveWeth,) = ulpDaiEth.getReserves();
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
        assertEq(ulpDaiEth.balanceOf(address(this)), 0);
        uint256 expected = 1000 * WAD;
        getLpDaiEth(expected);
        uint256 actual = ulpDaiEth.balanceOf(address(this));
        assertGt(actual, expected);
        assertLt(actual - expected, actual / 10);
    }

    function getSlp(uint256 amountLp) private {
        uint256 totalSupply = slp.totalSupply();
        (uint112 reserveWeth, uint112 reserveAlcx,) = slp.getReserves();
        uint256 amountAlcx = amountLp * reserveAlcx / totalSupply * 11 / 10;
        uint256 amountEth = amountLp * reserveWeth / totalSupply * 11 / 10;
        getAlcx(amountAlcx);
        alcx.approve(sushiAddr, amountAlcx);
        sushiRouter.addLiquidityETH{value: amountEth}({
            token: alcxAddr,
            amountTokenDesired: amountAlcx,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
    }

    function testGetSlp() public {
        assertEq(slp.balanceOf(address(this)), 0);
        uint256 expected = 30 * WAD;
        getSlp(expected);
        uint256 actual = slp.balanceOf(address(this));
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
        assertGt(ulpDaiEth.balanceOf(address(this)), amount);
        assertLt(dai.balanceOf(address(this)), 1 * WAD);
        assertEq(weth.balanceOf(address(this)), 0);
        ulpDaiEth.approve(uniAddr, amount);
        burnLpDaiEth(amount);
        assertLt(ulpDaiEth.balanceOf(address(this)), amount / 10);
        assertGt(dai.balanceOf(address(this)), 1 * WAD);
        assertGt(dai.balanceOf(address(this)), 1 * WAD);
    }

    function burnSlp(uint256 amount) private {
        sushiRouter.removeLiquidity({
            tokenA: alcxAddr,
            tokenB: wethAddr,
            liquidity: amount,
            amountAMin: 0,
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
    }

    function testBurnSlp() public {
        uint256 amount = 100 * WAD;
        getSlp(amount);
        uint256 alcxPre = alcx.balanceOf(address(this));
        assertGe(slp.balanceOf(address(this)), amount);
        assertEq(weth.balanceOf(address(this)), 0);
        slp.approve(sushiAddr, amount);
        burnSlp(amount);
        assertLt(slp.balanceOf(address(this)), amount / 10);
        assertGt(alcx.balanceOf(address(this)), alcxPre);
        assertGt(weth.balanceOf(address(this)), 1 * WAD);
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
        ulpDaiEth.approve(ulpDaiEthJoinAddr, amount);
        ulpDaiEthJoin.join(aliAddr, amount);
    }

    function testJoinLpDaiEth() public {
        uint256 amount = 10 * WAD;
        getLpDaiEth(amount);
        uint256 gemPre = vat.gem(ulpDaiEthName, aliAddr);
        joinLpDaiEth(amount);
        uint256 gemPost = vat.gem(ulpDaiEthName, aliAddr);
        assertEq(gemPost, gemPre + amount);
    }

    function joinSlp(uint256 amount) private {
        slp.approve(sushiManagerAddr, amount);
        CropManagerLike(sushiManagerAddr).join(slpJoinAddr, aliAddr, amount);
    }

    function testJoinSlp() public {
        uint256 amount = 30 * WAD;
        getSlp(amount);
        uint256 gemPre = vat.gem(slpName, sushiManager.proxy(aliAddr));
        joinSlp(amount);
        uint256 gemPost = vat.gem(slpName, sushiManager.proxy(aliAddr));
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
        dog.bark(ulpDaiEthName, aliAddr, aliAddr);
        auctionId = ulpDaiEthClip.kicks();
    }

    function testBarkLpDaiEth() public {
        uint256 amount = 100 * WAD;
        uint256 kicksPre = ulpDaiEthClip.kicks();
        getLpDaiEth(amount);
        joinLpDaiEth(amount);
        frobMax(amount, ulpDaiEthName);
        drip(ulpDaiEthName);
        uint256 auctionId = barkLpDaiEth();
        uint256 kicksPost = ulpDaiEthClip.kicks();
        assertEq(auctionId, kicksPost);
        assertEq(kicksPost, kicksPre + 1);
        (
         ,, uint256 lot, address usr, uint96 tic,
         ) = ulpDaiEthClip.sales(auctionId);
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
        bytes memory data = abi.encode(
            bobAddr,
            linkJoinAddr,
            minProfit,
            path
        );
        linkClip.take(auctionId, amt, max, bobAddr, data);
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
        vat.hope(ulpDaiEthClipAddr);
        address[] memory pathA;
        address[] memory pathB = new address[](2);
        pathB[0] = wethAddr;
        pathB[1] = daiAddr;
        bytes memory data
            = abi.encode(bobAddr, ulpDaiEthJoinAddr, minProfit, pathA, pathB);
        ulpDaiEthClip.take(auctionId, amt, max, cheAddr, data);
    }

    function testTakeLpDaiEthNoProfit() public {
        (,,,, uint256 dustRad) = vat.ilks(ulpDaiEthName);
        uint256 amount = dustRad / RAY;
        getLpDaiEth(amount);
        joinLpDaiEth(amount);
        frobMax(amount, ulpDaiEthName);
        drip(ulpDaiEthName);
        uint256 auctionId = barkLpDaiEth();
        (, uint256 auctionPrice,,) = ulpDaiEthClip.getStatus(auctionId);
        uint256 ulpDaiEthPrice = getLpDaiEthPrice();
        while (auctionPrice / uint256(1e9) * 11 / 10 > ulpDaiEthPrice) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = ulpDaiEthClip.getStatus(auctionId);
        }
        assertEq(dai.balanceOf(bobAddr), 0);
        takeLpDaiEth(auctionId, amount, auctionPrice, 0);
        assertLt(dai.balanceOf(bobAddr), amount * auctionPrice / RAY / 5);
    }

    function testTakeLpDaiEthProfit() public {
        uint256 minProfitPct = 30;
        (,,,, uint256 dustRad) = vat.ilks(ulpDaiEthName);
        uint256 amount = dustRad / RAY;
        getLpDaiEth(amount);
        joinLpDaiEth(amount);
        frobMax(amount, ulpDaiEthName);
        drip(ulpDaiEthName);
        uint256 auctionId = barkLpDaiEth();
        (, uint256 auctionPrice,,) = ulpDaiEthClip.getStatus(auctionId);
        uint256 ulpDaiEthPrice = getLpDaiEthPrice();
        while (
            auctionPrice / uint256(1e9) * 11 / 10 * (100 + minProfitPct) / 100
            > ulpDaiEthPrice
        ) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = ulpDaiEthClip.getStatus(auctionId);
        }
        uint256 minProfit = amount * auctionPrice / RAY 
            * minProfitPct / 100;
        assertEq(dai.balanceOf(bobAddr), 0);
        takeLpDaiEth(auctionId, amount, auctionPrice, minProfit);
        assertGe(dai.balanceOf(bobAddr), minProfit);
    }
}
