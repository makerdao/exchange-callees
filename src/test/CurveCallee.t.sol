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
import { CurveCallee } from "../CurveCallee.sol";

interface Hevm {
    function store(address c, bytes32 loc, bytes32 val) external;
}

interface Chainlog {
    function getAddress(bytes32) external returns (address);
}

interface Token {
    function approve(address, uint256) external;
}

interface Join {
    function join(address, uint256) external;
}

interface Vat {
    function ilks(bytes32)
        external returns (uint256, uint256, uint256, uint256, uint256);
    function file(bytes32, bytes32, uint256) external;
    function frob(
        bytes32 i,
        address u,
        address v,
        address w,
        int dink,
        int dart
    ) external;
}

interface Jug {
    function drip(bytes32) external;
}

interface Dog {
    function bark(bytes32, address, address) external returns (uint256);
}

interface Clipper {
    function take(
        uint256 id,
        uint256 amt,
        uint256 max,
        address who,
        bytes calldata data
    ) external;
}

contract CurveCalleeTest is DSTest {

    address constant hevm     = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    address constant wstEth   = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant chainlog = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    uint256 constant amt      = 50e18;
    address constant curve    = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant uniV3    = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address gemJoin;
    uint256 id;
    address clipper;
    CurveCallee callee;
    
    function setUp() public {
        // wstEth._balances[address(this)] = amt;
        Hevm(hevm).store({
            c:   wstEth,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(amt)
        });
        gemJoin = Chainlog(chainlog).getAddress("MCD_JOIN_WSTETH_A");
        Token(wstEth).approve(gemJoin, amt);
        Join(gemJoin).join(address(this), amt);
        address vat = Chainlog(chainlog).getAddress("MCD_VAT");
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
        clipper = Chainlog(chainlog).getAddress("MCD_CLIP_WSTETH_A");
        address daiJoin = Chainlog(chainlog).getAddress("MCD_JOIN_DAI");
        callee = new CurveCallee(curve, uniV3, daiJoin);
    }

    function test() public {
        bytes memory data = abi.encode(
            address(this),
            address(gemJoin),
            uint256(0),
            uint24(3000),
            address(0)
        );
        Clipper(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });
    }

}
