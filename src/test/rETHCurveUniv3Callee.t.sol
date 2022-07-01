// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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

pragma solidity ^0.6.12;

import "ds-test/test.sol";
import { rETHCurveUniv3Callee } from "../rETHCurveUniv3Callee.sol";

// FIXME: remove these imports once rETH has been onboarded
import { Clipper } from "dss/clip.sol";
import { GemJoin } from "dss/join.sol";
import { StairstepExponentialDecrease } from "dss/abaci.sol";

interface Hevm {
    function store(address c, bytes32 loc, bytes32 val) external;
    function warp(uint256) external;
}

interface Chainlog {
    function getAddress(bytes32) external view returns (address);
}

interface Token {
    function approve(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
}

interface Join {
    function join(address, uint256) external;
}

interface Vat {
    function ilks(bytes32)
        external view returns (uint256, uint256, uint256, uint256, uint256);
    function file(bytes32, bytes32, uint256) external;
    function frob(
        bytes32 i,
        address u,
        address v,
        address w,
        int dink,
        int dart
    ) external;
    function hope(address) external;
}

interface Jug {
    function drip(bytes32) external;
}

interface Dog {
    function bark(bytes32, address, address) external returns (uint256);
}

interface ClipperLike {
    function tail() external view returns (uint256);
    function take(
        uint256 id,
        uint256 amt,
        uint256 max,
        address who,
        bytes calldata data
    ) external;
}

interface Osm {
    function read() external view returns (bytes32);
    function kiss(address) external;
}

// FIXME: delete these interfaces once rETH has been onboarded
interface ChainlogTemp {
    function setAddress(bytes32, address) external;
}
interface VatTemp {
    function rely(address) external;
    function init(bytes32) external;
}
interface JugTemp {
    function init(bytes32) external;
    function ilks(bytes32) external view returns (uint256,uint256);
}
interface SpotterTemp {
    function poke(bytes32) external;
}
interface PipTemp {
    function kiss(address) external;
}
interface Fileable {
    function file(bytes32, bytes32, address) external;
    function file(bytes32, bytes32, uint256) external;
}

contract CurveCalleeTest is DSTest {

    address constant hevm     = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    address constant rETH     = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant chainlog = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant curve    = 0xF9440930043eb3997fc70e1339dBb11F341de7A8;
    address constant uniV3    = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    uint256 constant WAD = 1e18;
    uint256 constant RAY = 1e27;

    address gemJoin;
    uint256 id;
    address clipper;
    rETHCurveUniv3Callee callee;
    uint256 tail;
    address vat;
    address weth;
    address dai;
    address usdc;

    // FIXME: delete this function once rETH has been onboarded
    function onboardRETH() private {
        vat = Chainlog(chainlog).getAddress("MCD_VAT");
        address spotter = Chainlog(chainlog).getAddress("MCD_SPOT");
        address dog = Chainlog(chainlog).getAddress("MCD_DOG");
        address jug = Chainlog(chainlog).getAddress("MCD_JUG");
        address pipEth = Chainlog(chainlog).getAddress("PIP_ETH");
        bytes32 ilk = "RETH-A";
        Clipper rETHClipper = new Clipper(vat, spotter, dog, ilk);
        GemJoin rETHJoin = new GemJoin(vat, ilk, rETH);
        Hevm(hevm).store({
            c:   vat,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(uint256(1))
        });
        Hevm(hevm).store({
            c:    jug,
            loc:  keccak256(abi.encode(address(this), uint256(0))),
            val:  bytes32(uint256(1))
        });
        Hevm(hevm).store({
            c:    spotter,
            loc:  keccak256(abi.encode(address(this), uint256(0))),
            val:  bytes32(uint256(1))
        });
        Hevm(hevm).store({
            c:    dog,
            loc:  keccak256(abi.encode(address(this), uint256(0))),
            val:  bytes32(uint256(1))
        });
        Hevm(hevm).store({
            c:    pipEth,
            loc:  keccak256(abi.encode(address(this), uint256(0))),
            val:  bytes32(uint256(1))
        });
        Hevm(hevm).store({
            c:    chainlog,
            loc:  keccak256(abi.encode(address(this), uint256(0))),
            val:  bytes32(uint256(1))
        });
        VatTemp(vat).rely(address(rETHJoin));
        VatTemp(vat).init(ilk);
        JugTemp(jug).init(ilk);
        Fileable(jug).file(ilk, "duty", 1000000000705562181084137268);
        Hevm(hevm).warp(block.timestamp + 1);
        Fileable(spotter).file(ilk, "pip", pipEth);
        Fileable(spotter).file(ilk, "mat", 1450000000000000000000000000);
        SpotterTemp(spotter).poke(ilk);
        Fileable(dog).file(ilk, "hole", type(uint256).max);
        Fileable(dog).file(ilk, "chop", 11 * WAD / 10);
        Fileable(dog).file(ilk, "clip", address(rETHClipper));
        rETHClipper.rely(dog);
        PipTemp(pipEth).kiss(address(rETHClipper));
        StairstepExponentialDecrease rETHCalc = new StairstepExponentialDecrease();
        rETHCalc.file("cut", 99 * RAY / 100);
        rETHCalc.file("step", 90);
        rETHClipper.file("calc", address(rETHCalc));
        ChainlogTemp(chainlog).setAddress("MCD_CLIP_RETH_A", address(rETHClipper));
        ChainlogTemp(chainlog).setAddress("MCD_JOIN_RETH_A", address(rETHJoin));
    }

    function setUp() public {
        onboardRETH(); // FIXME: delete this line once rETH has been onboarded
        clipper = Chainlog(chainlog).getAddress("MCD_CLIP_RETH_A");
        address daiJoin = Chainlog(chainlog).getAddress("MCD_JOIN_DAI");
        weth = Chainlog(chainlog).getAddress("ETH");
        dai = Chainlog(chainlog).getAddress("MCD_DAI");
        usdc = Chainlog(chainlog).getAddress("USDC");
        callee = new rETHCurveUniv3Callee(curve, uniV3, daiJoin, weth);
        vat = Chainlog(chainlog).getAddress("MCD_VAT");
        Vat(vat).hope(clipper);
        tail = ClipperLike(clipper).tail();
    }

    function newAuction(uint256 amt) internal {
        // rETH._balances[address(this)] = amt;
        Hevm(hevm).store({
            c:   rETH,
            loc: keccak256(abi.encode(address(this), uint256(1))),
            val: bytes32(amt)
        });
        gemJoin = Chainlog(chainlog).getAddress("MCD_JOIN_RETH_A");
        Token(rETH).approve(gemJoin, amt);
        Join(gemJoin).join(address(this), amt);
        (, uint256 rate, uint256 spot,,) = Vat(vat).ilks("RETH-A");
        uint256 maxArt = amt * spot / rate;
        // vat.wards[address(this)] = 1;
        Hevm(hevm).store({
            c:   vat,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(uint256(1))
        });
        Vat(vat).file("RETH-A", "line", type(uint256).max);
        Vat(vat).frob({
            i:    "RETH-A",
            u:    address(this),
            v:    address(this),
            w:    address(this),
            dink: int(amt),
            dart: int(maxArt)
        });
        address jug = Chainlog(chainlog).getAddress("MCD_JUG");
        Jug(jug).drip("RETH-A");
        address dog = Chainlog(chainlog).getAddress("MCD_DOG");
        id = Dog(dog).bark("RETH-A", address(this), address(this));
    }

    function test_baseline() public {
        uint256 amt = 50 * WAD;
        newAuction(amt);
        uint24 poolFee = 3000;
        bytes memory data = abi.encode(
            address(123),
            address(gemJoin),
            uint256(0),
            abi.encodePacked(weth, poolFee, dai),
            address(0)
        );
        Hevm(hevm).warp(block.timestamp + tail / 2);
        ClipperLike(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });
        assertEq(Token(dai).balanceOf(address(this)), 0);
        assertEq(Token(rETH).balanceOf(address(this)), 0);
    }

    function test_bigAmtWithComplexPath() public {
        uint256 amt = 3000 * WAD;
        newAuction(amt);
        uint24 poolAFee = 500;
        uint24 poolBFee = 100;
        bytes memory data = abi.encode(
            address(this),
            address(gemJoin),
            uint256(0),
            abi.encodePacked(weth, poolAFee, usdc, poolBFee, dai),
            address(0)
        );
        Hevm(hevm).warp(block.timestamp + tail / 2);
        ClipperLike(clipper).take({
        id:   id,
        amt:  amt,
        max:  type(uint256).max,
        who:  address(callee),
        data: data
        });
    }

    function test_profit() public {
        uint256 minProfit = 10_000 * WAD;
        uint256 amt = 50 * WAD;
        newAuction(amt);
        uint24 poolFee = 3000;
        bytes memory data = abi.encode(
            address(123),
            address(gemJoin),
            uint256(minProfit),
            abi.encodePacked(weth, poolFee, dai),
            address(0)
        );
        Hevm(hevm).warp(block.timestamp + tail / 2);
        ClipperLike(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });
        assertGe(Token(dai).balanceOf(address(123)), minProfit);
    }

    function test_poolFee() public {
        uint24 poolFee = 500;
        uint256 amt = 50 * WAD;
        newAuction(amt);
        bytes memory data = abi.encode(
            address(this),
            address(gemJoin),
            uint256(0),
            abi.encodePacked(weth, poolFee, dai),
            address(0)
        );
        Hevm(hevm).warp(block.timestamp + tail / 2);
        ClipperLike(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });
    }

    function testFail_badPoolFee() public {
        uint24 poolFee = 5000;
        uint256 amt = 50 * WAD;
        newAuction(amt);
        bytes memory data = abi.encode(
            address(this),
            address(gemJoin),
            uint256(0),
            abi.encodePacked(weth, poolFee, dai),
            address(0)
        );
        Hevm(hevm).warp(block.timestamp + tail / 2);
        ClipperLike(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });
    }

    function test_maxPrice() public {
        uint256 amt = 50 * WAD;
        newAuction(amt);
        uint24 poolFee = 3000;
        bytes memory data = abi.encode(
            address(this),
            address(gemJoin),
            uint256(0),
            abi.encodePacked(weth, poolFee, dai),
            address(0)
        );
        Hevm(hevm).warp(block.timestamp + tail / 2);
        address osm = Chainlog(chainlog).getAddress("PIP_WSTETH");
        Hevm(hevm).store({
            c:   osm,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(uint256(1))
        });
        Osm(osm).kiss(address(this));
        uint256 max = uint256(Osm(osm).read()) * 1e9; // WAD * 1e9 = RAY
        ClipperLike(clipper).take({
            id:   id,
            amt:  amt,
            max:  max,
            who:  address(callee),
            data: data
        });
    }

    function testFail_maxPrice() public {
        uint256 amt = 50 * WAD;
        newAuction(amt);
        uint24 poolFee = 3000;
        bytes memory data = abi.encode(
            address(this),
            address(gemJoin),
            uint256(0),
            abi.encodePacked(weth, poolFee, dai),
            address(0)
        );
        Hevm(hevm).warp(block.timestamp + tail / 5);
        address osm = Chainlog(chainlog).getAddress("PIP_WSTETH");
        Hevm(hevm).store({
            c:   osm,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(uint256(1))
        });
        Osm(osm).kiss(address(this));
        uint256 max = uint256(Osm(osm).read()) * 1e9; // WAD * 1e9 = RAY
        ClipperLike(clipper).take({
            id:   id,
            amt:  amt,
            max:  max,
            who:  address(callee),
            data: data
        });
    }
}
