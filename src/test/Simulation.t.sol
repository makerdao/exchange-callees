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
import { UniswapV3Callee } from "../UniswapV3Callee.sol";
import { CurveLpTokenUniv3Callee, CurvePoolLike } from "../CurveLpTokenUniv3Callee.sol";

import { CropManager, CropManagerImp } from "dss-crop-join/CropManager.sol";
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

interface CropManagerAbstract {
    function join(address crop, address usr, uint256 val) external;
    function frob(address crop, address u, address v, address w, int256 dink, int256 dart) external;
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
    bytes32 constant lpDaiEthName = "UNIV2DAIETH-A";
    bytes32 constant steCRVName = "CURVESTETHETH-A";
    address constant curvePoolAddr = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant lidoTokenAddr = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address constant lidoStakingRewardsAddr = 0x99ac10631F69C753DDb595D074422a0922D9056B;
    address constant steCRVAddr = 0x06325440D014e39736583c165C2963BA99fAf14E;
    address constant steCRVPoolAddr = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

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
    address steCRVJoinAddr;
    address cropManagerAddr;
    address cropManagerImpAddr;
    address steCRVClipAddr;
    address steCRVPipAddr;
    address steCRVCalcAddr;

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
    GemAbstract steCRV;
    CropJoin steCRVJoin;
    SynthetixJoinImp steCRVJoinImp;
    CropManager cropManager;
    CropManagerImp cropManagerImp;
    ProxyManagerClipper steCRVClip;
    SpotAbstract spotter;
    DSValue steCRVPip;
    StairstepExponentialDecrease steCRVCalc;
    CurvePoolLike steCRVPool;

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
        steCRV = GemAbstract(steCRVAddr);
        spotter = SpotAbstract(spotterAddr);
    }

    function deployContracts() private {
        cropManagerImp = new CropManagerImp(vatAddr);
        cropManagerImpAddr = address(cropManagerImp);
        cropManager = new CropManager();
        cropManagerAddr = address(cropManager);
        cropManager.setImplementation(cropManagerImpAddr);
        CropManagerAbstract(cropManagerAddr).getOrCreateProxy(edAddr);
        steCRVJoinImp = new SynthetixJoinImp(
            vatAddr,
            steCRVName,
            steCRVAddr,
            lidoTokenAddr,
            lidoStakingRewardsAddr
        );
        steCRVJoin = new CropJoin();
        steCRVJoin.setImplementation(address(steCRVJoinImp));
        steCRVJoinAddr = address(steCRVJoin);
        steCRVJoin.rely(cropManagerAddr);
        SynthetixJoinImp(address(steCRVJoin)).init();
        vat.rely(steCRVJoinAddr);
        vat.init(steCRVName);
        vat.file(steCRVName, "spot", 100 * RAY);
        vat.file(steCRVName, "line", 1_000_000 * RAD);
        jug.init(steCRVName);
        jug.file(steCRVName, "duty", 1000000001847694957439350562);
        hevm.warp(block.timestamp + 600);
        dog.file(steCRVName, "hole", 10_000 * RAD);
        dog.file(steCRVName, "chop", 113 * WAD / 100);
        steCRVClip = new ProxyManagerClipper(
            vatAddr,
            spotterAddr,
            dogAddr,
            steCRVJoinAddr,
            cropManagerAddr
        );
        steCRVClip.file("tail", 2 hours);
        steCRVClipAddr = address(steCRVClip);
        steCRVCalc = new StairstepExponentialDecrease();
        steCRVCalc.file("step", 90);
        steCRVCalc.file("cut", 99 * RAY / 100);
        steCRVCalcAddr = address(steCRVCalc);
        steCRVClip.file("calc", steCRVCalcAddr);
        dog.file(steCRVName, "clip", steCRVClipAddr);
        steCRVClip.rely(dogAddr);
        dog.rely(steCRVClipAddr);
        steCRVPip = new DSValue();
        steCRVPip.poke(bytes32(100 * WAD));
        steCRVPipAddr = address(steCRVPip);
        spotter.file(steCRVName, "pip", steCRVPipAddr);
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
        ed = new CurveLpTokenUniv3Callee(curvePoolAddr, uniV3Addr, daiJoinAddr, wethAddr);
        edAddr = address(ed);
        getPermissions();
        deployContracts();
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

    function joinSteCRV(uint256 amount) private {
        steCRV.approve(cropManagerAddr, amount);
        CropManagerAbstract(cropManagerAddr).join(steCRVJoinAddr, address(this), amount);
    }

    function testJoinSteCRV() public {
        uint256 amount = 30 * WAD;
        getSteCRV(amount);
        uint256 gemPre = vat.gem(
            steCRVName,
            CropManagerAbstract(cropManagerAddr).proxy(address(this))
        );
        joinSteCRV(amount);
        uint256 gemPost = vat.gem(
            steCRVName,
            CropManagerAbstract(cropManagerAddr).proxy(address(this))
        );
        assertEq(gemPost, gemPre + amount);
    }

    function testExitSteCRV() public {
        uint256 amount = 30 * WAD;
        getSteCRV(amount);
        joinSteCRV(amount);
        CropManagerAbstract(cropManagerAddr).exit(steCRVJoinAddr, address(this), amount);
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

    function frobMaxSteCRV(uint256 ink) private {
        (, uint256 rate, uint256 spot, ,) = vat.ilks(steCRVName);
        uint256 art = ink * spot / rate;
        CropManagerAbstract(cropManagerAddr).frob(steCRVJoinAddr, address(this), address(this), address(this), int256(ink), int256(art));
    }

    function testFrobMaxSteCRV() public {
        uint256 amountSteCRV = 100 * WAD;
        getSteCRV(amountSteCRV);
        joinSteCRV(amountSteCRV);
        frobMaxSteCRV(amountSteCRV);
        try CropManagerAbstract(cropManagerAddr).frob(steCRVJoinAddr, address(this), address(this), address(this), 0, 1) {
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

    function barkSteCRV() private returns (uint256 auctionId) {
        dog.bark(
            steCRVName,
            CropManagerAbstract(cropManagerAddr).proxy(address(this)),
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
        assertEq(usr, CropManagerAbstract(cropManagerAddr).proxy(address(this)));
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
        takeLinkV2(auctionId, amountLink, auctionPrice, 0);
        assertLt(dai.balanceOf(bobAddr), amountLink * auctionPrice / RAY / 5);
    }

    function testTakeLinkV2Profit() public {
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
        uint balancePre = dai.balanceOf(danAddr);
        takeLinkV3(auctionId, amountLink, auctionPrice, 0);
        uint256 balancePost = dai.balanceOf(danAddr);
        log_named_uint("dai profit", (balancePost - balancePre) / WAD);
    }

    function testTakeLinkV3Profit() public {
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
        assertEq(dai.balanceOf(danAddr), 0);
        takeLinkV3(auctionId, amountLink, auctionPrice, minProfit);
        assertGe(dai.balanceOf(danAddr), minProfit);
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

    function takeSteCRV(
        uint256 auctionId,
        uint256 amt,
        uint256 max,
        uint256 minProfit
    ) private {
        vat.hope(steCRVClipAddr);

        uint24 poolFee = 3000;
        bytes memory path = abi.encodePacked(wethAddr, poolFee, daiAddr);
        bytes memory data = abi.encode(
            edAddr,         // to
            steCRVJoinAddr, // gemJoin
            minProfit,      // minProfit
            0,              // coinIndex (0 - eth)
            path,           // path
            cropManagerAddr // manager
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
        takeSteCRV(auctionId, amount, 100 * RAY, 0);
        uint256 balancePost = dai.balanceOf(edAddr);
        assertGt(balancePost, balancePre);
    }

    function testTakeSteCRVProfit() public {
        uint256 amount = 30 * WAD;
        uint256 minProfit = 30_000 * WAD;
        getSteCRV(amount);
        joinSteCRV(amount);
        frobMaxSteCRV(amount);
        drip(steCRVName);
        uint256 auctionId = barkSteCRV();
        hevm.warp(block.timestamp + 1 hours);
        uint256 balancePre = dai.balanceOf(edAddr);
        takeSteCRV(auctionId, amount, 100 * RAY, minProfit);
        uint256 balancePost = dai.balanceOf(edAddr);
        assertGt(balancePost, balancePre + minProfit);
    }
}
