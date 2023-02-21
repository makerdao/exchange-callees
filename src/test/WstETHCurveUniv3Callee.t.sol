// SPDX-License-Identifier: AGPL-3.0-or-later
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

pragma solidity ^0.6.12;

import "ds-test/test.sol";
import { WstETHCurveUniv3Callee } from "../WstETHCurveUniv3Callee.sol";

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

interface Clipper {
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

contract CurveCalleeTest is DSTest {

    address constant hevm     = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    address constant wstEth   = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant chainlog = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant curve    = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant uniV3    = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint256 constant WAD      = 1e18;

    address gemJoin;
    uint256 id;
    address clipper;
    WstETHCurveUniv3Callee callee;
    uint256 tail;
    address vat;
    address weth;
    address dai;
    address usdc;
    
    function setUp() public {
        clipper = Chainlog(chainlog).getAddress("MCD_CLIP_WSTETH_A");
        address daiJoin = Chainlog(chainlog).getAddress("MCD_JOIN_DAI");
        weth = Chainlog(chainlog).getAddress("ETH");
        dai = Chainlog(chainlog).getAddress("MCD_DAI");
        usdc = Chainlog(chainlog).getAddress("USDC");
        callee = new WstETHCurveUniv3Callee(curve, uniV3, daiJoin, weth);
        vat = Chainlog(chainlog).getAddress("MCD_VAT");
        Vat(vat).hope(clipper);
        tail = Clipper(clipper).tail();
    }

    function newAuction(uint256 amt) internal {
        // wstEth._balances[address(this)] = amt;
        Hevm(hevm).store({
            c:   wstEth,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(amt)
        });
        gemJoin = Chainlog(chainlog).getAddress("MCD_JOIN_WSTETH_A");
        Token(wstEth).approve(gemJoin, amt);
        Join(gemJoin).join(address(this), amt);
        (, uint256 rate, uint256 spot,,) = Vat(vat).ilks("WSTETH-A");
        uint256 maxArt = amt * spot / rate;
        // vat.wards[address(this)] = 1;
        Hevm(hevm).store({
            c:   vat,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(uint256(1))
        });
        Vat(vat).file("WSTETH-A", "line", type(uint256).max);
        Vat(vat).frob({
            i:    "WSTETH-A",
            u:    address(this),
            v:    address(this),
            w:    address(this),
            dink: int(amt),
            dart: int(maxArt)
        });
        address jug = Chainlog(chainlog).getAddress("MCD_JUG");
        Jug(jug).drip("WSTETH-A");
        address dog = Chainlog(chainlog).getAddress("MCD_DOG");
        id = Dog(dog).bark("WSTETH-A", address(this), address(this));
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
        Clipper(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });
        assertEq(Token(dai).balanceOf(address(this)), 0);
        assertEq(Token(wstEth).balanceOf(address(this)), 0);
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
        Clipper(clipper).take({
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
        Clipper(clipper).take({
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
        Clipper(clipper).take({
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
        Clipper(clipper).take({
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
        Clipper(clipper).take({
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
        Hevm(hevm).warp(block.timestamp + tail / 10);
        address osm = Chainlog(chainlog).getAddress("PIP_WSTETH");
        Hevm(hevm).store({
            c:   osm,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(uint256(1))
        });
        Osm(osm).kiss(address(this));
        uint256 max = uint256(Osm(osm).read()) * 1e9; // WAD * 1e9 = RAY
        Clipper(clipper).take({
            id:   id,
            amt:  amt,
            max:  max,
            who:  address(callee),
            data: data
        });
    }
}
