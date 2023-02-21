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
import { UniswapV3Callee } from "../UniswapV3Callee.sol";
import { CurveLpTokenUniv3Callee, CurvePoolLike} from "../CurveLpTokenUniv3Callee.sol";

import { Cropper, CropperImp } from "dss-crop-join/Cropper.sol";
import { CropJoin } from "dss-crop-join/CropJoin.sol";
import { SynthetixJoinImp } from "dss-crop-join/SynthetixJoin.sol";
import { ProxyManagerClipper } from "proxy-manager-clipper/ProxyManagerClipper.sol";
import { DSValue } from "ds-value/value.sol";

import "dss/clip.sol";
import "dss/abaci.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address c, bytes32 loc, bytes32 val) external;
    function load(address,bytes32) external returns (bytes32);
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

interface CropperAbstract {
    function join(address crop, address usr, uint256 val) external;
    function frob(bytes32 ilk, address u, address v, address w, int256 dink, int256 dart) external;
    function getOrCreateProxy(address usr) external returns (address urp);
    function exit(address crop, address usr, uint256 val) external;
    function proxy(address) external view returns (address);
}

contract VaultHolder {
    constructor(VatAbstract vat) public {
        vat.hope(msg.sender);
    }
}

contract SimulationTests is DSTest {

    // mainnet UniswapV2Router02 address
    address constant uniAddr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant uniV3Addr = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant hevmAddr = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    bytes32 constant linkName = "LINK-A";
    bytes32 constant lpUsdcEthName = "UNIV2USDCETH-A";
    bytes32 constant steCRVName = "CRVV1ETHSTETH-A";
    address constant curvePoolAddr = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant lidoTokenAddr = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address constant lidoStakingRewardsAddr = 0x99ac10631F69C753DDb595D074422a0922D9056B;

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

    function giveTokens(address token, uint256 amount) public {
        // Edge case - balance is already set for some reason
        if (GemAbstract(token).balanceOf(address(this)) == amount) return;

        // Solidity-style
        for (uint256 i = 0; i < 20; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                token,
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                token,
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (GemAbstract(token).balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    token,
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // Vyper-style
        for (uint256 i = 0; i < 20; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                token,
                keccak256(abi.encode(uint256(i), address(this)))
            );
            hevm.store(
                token,
                keccak256(abi.encode(uint256(i), address(this))),
                bytes32(amount)
            );
            if (GemAbstract(token).balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    token,
                    keccak256(abi.encode(uint256(i), address(this))),
                    prevValue
                );
            }
        }
    }

    address wethAddr;
    address linkAddr;
    address usdcAddr;
    address steCRVAddr;
    address daiAddr;
    address vatAddr;
    address linkJoinAddr;
    address spotterAddr;
    address daiJoinAddr;
    address dogAddr;
    address jugAddr;
    address linkClipAddr;
    address lpUsdcEthAddr;
    address lpUsdcEthJoinAddr;
    address lpUsdcEthClipAddr;
    address vowAddr;
    address lpUsdcEthPipAddr;
    address linkPipAddr;
    address ethPipAddr;
    address steCRVJoinAddr;
    address cropManagerAddr;
    address steCRVClipAddr;
    address steCRVPipAddr;

    Hevm hevm;
    UniV2Router02Abstract uniRouter;
    WethAbstract weth;
    GemAbstract link;
    GemAbstract usdc;
    VatAbstract vat;
    DaiAbstract dai;
    GemJoinAbstract linkJoin;
    DogAbstract dog;
    JugAbstract jug;
    ClipAbstract linkClip;
    LpTokenAbstract lpUsdcEth;
    ClipAbstract lpUsdcEthClip;
    GemJoinAbstract lpUsdcEthJoin;
    LPOsmAbstract lpUsdcEthPip;
    OsmAbstract linkPip;
    OsmAbstract ethPip;
    GemAbstract steCRV;
    CropJoin steCRVJoin;
    Cropper cropManager;
    ProxyManagerClipper steCRVClip;
    OsmAbstract steCRVPip;
    SpotAbstract spotter;

    function setAddresses() private {
        ChainlogHelper helper = new ChainlogHelper();
        ChainlogAbstract chainLog = helper.ABSTRACT();
        wethAddr = chainLog.getAddress("ETH");
        linkAddr = chainLog.getAddress("LINK");
        usdcAddr = chainLog.getAddress("USDC");
        steCRVAddr = chainLog.getAddress("CRVV1ETHSTETH");
        vatAddr = chainLog.getAddress("MCD_VAT");
        daiAddr = chainLog.getAddress("MCD_DAI");
        linkJoinAddr = chainLog.getAddress("MCD_JOIN_LINK_A");
        spotterAddr = chainLog.getAddress("MCD_SPOT");
        daiJoinAddr = chainLog.getAddress("MCD_JOIN_DAI");
        dogAddr = chainLog.getAddress("MCD_DOG");
        jugAddr = chainLog.getAddress("MCD_JUG");
        linkClipAddr = chainLog.getAddress("MCD_CLIP_LINK_A");
        lpUsdcEthClipAddr = chainLog.getAddress("MCD_CLIP_UNIV2USDCETH_A");
        lpUsdcEthAddr = chainLog.getAddress("UNIV2USDCETH");
        lpUsdcEthJoinAddr = chainLog.getAddress("MCD_JOIN_UNIV2USDCETH_A");
        vowAddr = chainLog.getAddress("MCD_VOW");
        lpUsdcEthPipAddr = chainLog.getAddress("PIP_UNIV2USDCETH");
        linkPipAddr = chainLog.getAddress("PIP_LINK");
        ethPipAddr = chainLog.getAddress("PIP_ETH");
        steCRVJoinAddr = chainLog.getAddress("MCD_JOIN_CRVV1ETHSTETH_A");
        cropManagerAddr = chainLog.getAddress("MCD_CROPPER");
        steCRVClipAddr = chainLog.getAddress("MCD_CLIP_CRVV1ETHSTETH_A");
        steCRVPipAddr = chainLog.getAddress("PIP_CRVV1ETHSTETH");
    }

    function setInterfaces() private {
        hevm = Hevm(hevmAddr);
        uniRouter = UniV2Router02Abstract(uniAddr);
        weth = WethAbstract(wethAddr);
        link = GemAbstract(linkAddr);
        usdc = GemAbstract(usdcAddr);
        steCRV = GemAbstract(steCRVAddr);
        vat = VatAbstract(vatAddr);
        dai = DaiAbstract(daiAddr);
        linkJoin = GemJoinAbstract(linkJoinAddr);
        dog = DogAbstract(dogAddr);
        jug = JugAbstract(jugAddr);
        linkClip = ClipAbstract(linkClipAddr);
        lpUsdcEthClip = ClipAbstract(lpUsdcEthClipAddr);
        lpUsdcEth = LpTokenAbstract(lpUsdcEthAddr);
        lpUsdcEthJoin = GemJoinAbstract(lpUsdcEthJoinAddr);
        lpUsdcEthPip = LPOsmAbstract(lpUsdcEthPipAddr);
        linkPip = OsmAbstract(linkPipAddr);
        ethPip = OsmAbstract(ethPipAddr);
        steCRVPip = OsmAbstract(steCRVPipAddr);
        steCRVClip = ProxyManagerClipper(steCRVClipAddr);
        spotter = SpotAbstract(spotterAddr);
    }

    VaultHolder ali;
    address aliAddr;
    UniswapV2CalleeDai bob;
    address bobAddr;
    UniswapV2LpTokenCalleeDai che;
    address cheAddr;
    UniswapV3Callee dan;
    address danAddr;
    CurveLpTokenUniv3Callee ed;
    address edAddr;

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
            lpUsdcEthPipAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        lpUsdcEthPip.kiss(address(this));
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
            steCRVPipAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        steCRVPip.kiss(address(this));
        hevm.store(
            jugAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        hevm.store(
            spotterAddr,
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
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
        dan = new UniswapV3Callee(uniV3Addr, daiJoinAddr);
        danAddr = address(dan);
        ed = new CurveLpTokenUniv3Callee(uniV3Addr, daiJoinAddr, wethAddr);
        edAddr = address(ed);
        CropperAbstract(cropManagerAddr).getOrCreateProxy(edAddr);
        getPermissions();
    }

    function getLinkPrice() private view returns (uint256 val) {
        val = uint256(linkPip.read());
    }

    function getLinkPriceRay() private view returns (uint256) {
        return getLinkPrice() * 10 ** 9;
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

    function getLpUsdcEthPrice() private view returns (uint256 val) {
        val = uint256(lpUsdcEthPip.read());
    }

    function getLpUsdcEthPriceRay() private view returns (uint256) {
        return getLpUsdcEthPrice() * 10 ** 9;
    }

    function testGetLpUsdcEthPrice() public {
        uint256 price = getLpUsdcEthPrice();
        assertGt(price, 0);
        log_named_uint("LP USDC ETH price", price / WAD);
    }

    function getSteCRVPrice() private view returns (uint256 val) {
        val = uint256(steCRVPip.read());
    }

    function testGetSteCRVPrice() public {
        uint256 price = getSteCRVPrice();
        assertGt(price, 0);
        log_named_uint("SteCRV price", price / WAD);
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

    function getUsdc(uint256 amountUsdc) private {
        (uint112 reserveUsdc, uint112 reserveWeth, ) = lpUsdcEth.getReserves();
        uint256 amountWeth = uniRouter.getAmountIn(amountUsdc, reserveWeth, reserveUsdc);
        getWeth(amountWeth);
        weth.approve(uniAddr, amountWeth);
        address[] memory path = new address[](2);
        path[0] = wethAddr;
        path[1] = usdcAddr;
        uniRouter.swapExactTokensForTokens({
            amountIn: amountWeth,
            amountOutMin: 0,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });
    }

    function testGetUsdc() public {
        uint256 amountUsdc = (10 * 10 ** 6);
        uint256 usdcPre = usdc.balanceOf(address(this));
        getUsdc(amountUsdc);
        uint256 usdcPost = usdc.balanceOf(address(this));
        assertEq(usdcPost, usdcPre + amountUsdc);
    }

    function getLpUsdcEth(uint256 amountLp) private {
        uint256 totalSupply = lpUsdcEth.totalSupply();
        (uint112 reserveUsdc, uint112 reserveWeth,) = lpUsdcEth.getReserves();
        uint256 amountUsdc = (amountLp * reserveUsdc / totalSupply * 11 / 10); // why?
        uint256 amountEth = amountLp * reserveWeth / totalSupply * 11 / 10;
        getUsdc(amountUsdc);
        usdc.approve(uniAddr, amountUsdc);
        uniRouter.addLiquidityETH{value: amountEth}({
            token: usdcAddr,
            amountTokenDesired: amountUsdc,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
    }

    receive() external payable {}

    function testGetLpUsdcEth() public {
        assertEq(lpUsdcEth.balanceOf(address(this)), 0);
        uint256 expected =  WAD / 1000;
        getLpUsdcEth(expected);
        uint256 actual = lpUsdcEth.balanceOf(address(this));
        assertGt(actual, expected);
        assertLt(actual - expected, actual / 10);
    }

    function getSteCRV(uint256 amountLp) private {
        giveTokens(steCRVAddr, amountLp);
    }

    function testGetSteCRV() public {
        assertEq(steCRV.balanceOf(address(this)), 0);
        uint256 expected = 30 * WAD;
        getSteCRV(expected);
        uint256 actual = steCRV.balanceOf(address(this));
        assertEq(actual, expected);
    }

    function burnLpUsdcEth(uint256 amount) private {
        uniRouter.removeLiquidity({
            tokenA: usdcAddr,
            tokenB: wethAddr,
            liquidity: amount,
            amountAMin: 0,
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
    }

    function testBurnLpUsdcEth() public {
        uint256 amount = 30 * WAD / 1000;
        getLpUsdcEth(amount);
        assertGt(lpUsdcEth.balanceOf(address(this)), amount);
        lpUsdcEth.approve(uniAddr, amount);
        burnLpUsdcEth(amount);
        assertLt(lpUsdcEth.balanceOf(address(this)), amount / 10);
    }

    function getLink(uint256 amountLink) private {
        uint256 linkPrice = getLinkPrice();
        uint256 ethPrice = getEthPrice();
        uint256 amountWeth = amountLink * linkPrice / ethPrice * 13 / 10;
        getWeth(amountWeth);
        weth.approve(uniAddr, amountWeth);
        address[] memory path = new address[](2);
        path[0] = wethAddr;
        path[1] = linkAddr;
        uniRouter.swapExactTokensForTokens({
            amountIn: amountWeth,
            amountOutMin: amountLink,
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

    function joinLpUsdcEth(uint256 amount) private {
        lpUsdcEth.approve(lpUsdcEthJoinAddr, amount);
        lpUsdcEthJoin.join(aliAddr, amount);
    }

    function testJoinLpUsdcEth() public {
        uint256 amount = 10 * WAD / 1000;
        getLpUsdcEth(amount);
        uint256 gemPre = vat.gem(lpUsdcEthName, aliAddr);
        joinLpUsdcEth(amount);
        uint256 gemPost = vat.gem(lpUsdcEthName, aliAddr);
        assertEq(gemPost, gemPre + amount);
    }

    function joinSteCRV(uint256 amount) private {
        steCRV.approve(cropManagerAddr, amount);
        CropperAbstract(cropManagerAddr).join(steCRVJoinAddr, address(this), amount);
    }

    function testJoinSteCRV() public {
        uint256 amount = 30 * WAD;
        getSteCRV(amount);
        uint256 gemPre = vat.gem(
            steCRVName,
            CropperAbstract(cropManagerAddr).proxy(address(this))
        );
        joinSteCRV(amount);
        uint256 gemPost = vat.gem(
            steCRVName,
            CropperAbstract(cropManagerAddr).proxy(address(this))
        );
        assertEq(gemPost, gemPre + amount);
    }

    function testExitSteCRV() public {
        uint256 amount = 30 * WAD;
        getSteCRV(amount);
        joinSteCRV(amount);
        CropperAbstract(cropManagerAddr).exit(steCRVJoinAddr, address(this), amount);
    }

    function frobMax(uint256 gem, bytes32 ilkName) private {
        uint256 ink = gem;
        (, uint256 rate, uint256 spot, ,) = vat.ilks(ilkName);
        uint256 art = ink * spot / rate;
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

    function frobMaxSteCRV(uint256 ink) private {
        (, uint256 rate, uint256 spot, ,) = vat.ilks(steCRVName);
        uint256 art = ink * spot / rate;
        CropperAbstract(cropManagerAddr).frob(steCRVName, address(this), address(this), address(this), int256(ink), int256(art));
    }

    function testFrobMaxSteCRV() public {
        uint256 amountSteCRV = 100 * WAD;
        getSteCRV(amountSteCRV);
        joinSteCRV(amountSteCRV);
        frobMaxSteCRV(amountSteCRV);
        try CropperAbstract(cropManagerAddr).frob(steCRVName, address(this), address(this), address(this), 0, 1) {
            log("not at max frob");
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

    function testDripSteCRV() public {
        (, uint256 ratePre, , , ) = vat.ilks(steCRVName);
        drip(steCRVName);
        (, uint256 ratePost, , , ) = vat.ilks(steCRVName);
        assertGt(ratePost, ratePre);
    }

    function barkLink() private returns (uint256 auctionId) {
        dog.bark(linkName, aliAddr, aliAddr);
        auctionId = linkClip.kicks();
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

    function barkLpUsdcEth() private returns (uint256 auctionId) {
        dog.bark(lpUsdcEthName, aliAddr, aliAddr);
        auctionId = lpUsdcEthClip.kicks();
    }

    function testBarkLpUsdcEth() public {
        (,,,, uint256 dustRad) = vat.ilks(lpUsdcEthName);
        uint256 amount = (dustRad / getLpUsdcEthPriceRay()) * 2;
        uint256 kicksPre = lpUsdcEthClip.kicks();
        getLpUsdcEth(amount);
        joinLpUsdcEth(amount);
        frobMax(amount, lpUsdcEthName);
        drip(lpUsdcEthName);
        uint256 auctionId = barkLpUsdcEth();
        uint256 kicksPost = lpUsdcEthClip.kicks();
        assertEq(auctionId, kicksPost);
        assertEq(kicksPost, kicksPre + 1);
        (
         ,, uint256 lot, address usr, uint96 tic,
         ) = lpUsdcEthClip.sales(auctionId);
        assertEq(usr, aliAddr);
        assertEq(lot, amount);
        assertEq(tic, block.timestamp);
    }

    function barkSteCRV() private returns (uint256 auctionId) {
        dog.bark(
            steCRVName,
            CropperAbstract(cropManagerAddr).proxy(address(this)),
            address(this)
        );
        auctionId = steCRVClip.kicks();
    }

    function testBarkSteCRV() public {
        uint256 amount = 30 * WAD;
        getSteCRV(amount);
        joinSteCRV(amount);
        frobMaxSteCRV(amount);
        drip(steCRVName);
        uint256 auctionId = barkSteCRV();
        (
        ,, uint256 lot, address usr, uint96 tic,
        ) = steCRVClip.sales(auctionId);
        assertEq(usr, CropperAbstract(cropManagerAddr).proxy(address(this)));
        assertEq(lot, amount);
        assertEq(tic, block.timestamp);
    }

    function takeLinkV2(
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
            path,
            address(0)
        );
        linkClip.take(auctionId, amt, max, bobAddr, data);
    }

    function testTakeLinkV2NoProfit() public {
        (,,,, uint256 dustRad) = vat.ilks(linkName);
        uint256 amountLink = (dustRad / getLinkPriceRay()) * 2;
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
        takeLinkV2(auctionId, amountLink, auctionPrice, 0);
        assertLt(dai.balanceOf(bobAddr), amountLink * auctionPrice / RAY / 5);
    }

    function testTakeLinkV2Profit() public {
        uint256 minProfitPct = 30;
        (,,,, uint256 dustRad) = vat.ilks(linkName);
        uint256 amountLink = (dustRad / getLinkPriceRay()) * 2;
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
        takeLinkV2(auctionId, amountLink, auctionPrice, minProfit);
        assertGe(dai.balanceOf(bobAddr), minProfit);
    }

    function takeLinkV3(
        uint256 auctionId,
        uint256 amt,
        uint256 max,
        uint256 minProfit
    ) public {
        vat.hope(linkClipAddr);
        link.approve(uniV3Addr, amt);
        uint24 poolFee = 3000;
        bytes memory path = abi.encodePacked(linkAddr, poolFee, wethAddr, poolFee, daiAddr);
        bytes memory data = abi.encode(
            danAddr,
            linkJoinAddr,
            minProfit,
            path,
            address(0)
        );
        linkClip.take(auctionId, amt, max, danAddr, data);
    }

    function testTakeLinkV3NoProfit() public {
        (,,,, uint256 dustRad) = vat.ilks(linkName);
        uint256 amountLink = (dustRad / getLinkPriceRay()) * 2;
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
        uint balancePre = dai.balanceOf(danAddr);
        takeLinkV3(auctionId, amountLink, auctionPrice, 0);
        uint256 balancePost = dai.balanceOf(danAddr);
        log_named_uint("dai profit", (balancePost - balancePre) / WAD);
    }

    function testTakeLinkV3Profit() public {
        uint256 minProfitPct = 30;
        (,,,, uint256 dustRad) = vat.ilks(linkName);
        uint256 amountLink = (dustRad / getLinkPriceRay()) * 2;
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
        assertEq(dai.balanceOf(danAddr), 0);
        takeLinkV3(auctionId, amountLink, auctionPrice, minProfit);
        assertGe(dai.balanceOf(danAddr), minProfit);
    }

    function takeLpUsdcEth(
        uint256 auctionId,
        uint256 amt,
        uint256 max,
        uint256 minProfit
    ) public {
        vat.hope(lpUsdcEthClipAddr);
        address[] memory pathA = new address[](2);
        pathA[0] = usdcAddr;
        pathA[1] = daiAddr;
        address[] memory pathB = new address[](2);
        pathB[0] = wethAddr;
        pathB[1] = daiAddr;
        bytes memory data
            = abi.encode(bobAddr, lpUsdcEthJoinAddr, minProfit, pathA, pathB);
        lpUsdcEthClip.take(auctionId, amt, max, cheAddr, data);
    }

    function testTakeLpUsdcEthNoProfit() public {
        (,,,, uint256 dustRad) = vat.ilks(lpUsdcEthName);
        uint256 amount = (dustRad / getLpUsdcEthPriceRay()) * 2;
        getLpUsdcEth(amount);
        joinLpUsdcEth(amount);
        frobMax(amount, lpUsdcEthName);
        drip(lpUsdcEthName);
        uint256 auctionId = barkLpUsdcEth();
        (, uint256 auctionPrice,,) = lpUsdcEthClip.getStatus(auctionId);
        uint256 lpUsdcEthPrice = getLpUsdcEthPrice();
        while (auctionPrice / uint256(1e9) * 11 / 10 > lpUsdcEthPrice) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = lpUsdcEthClip.getStatus(auctionId);
        }
        assertEq(dai.balanceOf(bobAddr), 0);
        takeLpUsdcEth(auctionId, amount, auctionPrice, 0);
        assertLt(dai.balanceOf(bobAddr), amount * auctionPrice / RAY / 5);
    }

    function testTakeLpUsdcEthProfit() public {
        uint256 minProfitPct = 30;
        (,,,, uint256 dustRad) = vat.ilks(lpUsdcEthName);
        uint256 amount = (dustRad / getLpUsdcEthPriceRay()) * 2;
        getLpUsdcEth(amount);
        joinLpUsdcEth(amount);
        frobMax(amount, lpUsdcEthName);
        drip(lpUsdcEthName);
        uint256 auctionId = barkLpUsdcEth();
        (, uint256 auctionPrice,,) = lpUsdcEthClip.getStatus(auctionId);
        uint256 lpUsdcEthPrice = getLpUsdcEthPrice();
        while (
            auctionPrice / uint256(1e9) * 11 / 10 * (100 + minProfitPct) / 100
            > lpUsdcEthPrice
        ) {
            hevm.warp(block.timestamp + 10 seconds);
            (, auctionPrice,,) = lpUsdcEthClip.getStatus(auctionId);
        }
        uint256 minProfit = amount * auctionPrice / RAY 
            * minProfitPct / 100;
        assertEq(dai.balanceOf(bobAddr), 0);
        takeLpUsdcEth(auctionId, amount, auctionPrice, minProfit);
        assertGe(dai.balanceOf(bobAddr), minProfit);
    }

    function takeSteCRV(
        uint256 auctionId,
        uint256 amt,
        uint256 max,
        uint256 minProfit
    ) private {
        vat.hope(steCRVClipAddr);

        uint24 poolFee = 3000;
        bytes memory path = abi.encodePacked(wethAddr, poolFee, daiAddr);
        CurveLpTokenUniv3Callee.CurveData memory curveData = CurveLpTokenUniv3Callee.CurveData(curvePoolAddr, 0);
        bytes memory data = abi.encode(
            edAddr,          // to
            steCRVJoinAddr,  // gemJoin
            minProfit,       // minProfit
            path,            // path
            cropManagerAddr, // manager
            curveData        // curveData
        );

        steCRVClip.take(auctionId, amt, max, edAddr, data);
    }

    function testTakeSteCRVNoProfit() public {
        uint256 amount = 30 * WAD;
        getSteCRV(amount);
        joinSteCRV(amount);
        frobMaxSteCRV(amount);
        drip(steCRVName);
        uint256 auctionId = barkSteCRV();
        hevm.warp(block.timestamp + 1 hours);
        uint256 balancePre = dai.balanceOf(edAddr);
        uint256 countBefore = steCRVClip.count();
        takeSteCRV(auctionId, amount, 5000 * RAY, 0);
        assertEq(steCRVClip.count(), countBefore - 1);
        uint256 balancePost = dai.balanceOf(edAddr);
        assertGt(balancePost, balancePre);
    }

    function testTakeSteCRVProfit() public {
        uint256 amount = 30 * WAD;
        uint256 minProfit = 1000 * WAD;
        getSteCRV(amount);
        joinSteCRV(amount);
        frobMaxSteCRV(amount);
        drip(steCRVName);
        uint256 auctionId = barkSteCRV();
        hevm.warp(block.timestamp + 1 hours);
        uint256 balancePre = dai.balanceOf(edAddr);
        uint256 countBefore = steCRVClip.count();
        takeSteCRV(auctionId, amount, 5000 * RAY, minProfit);
        assertEq(steCRVClip.count(), countBefore - 1);
        uint256 balancePost = dai.balanceOf(edAddr);
        assertGt(balancePost, balancePre + minProfit);
    }
}
