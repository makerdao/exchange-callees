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
import { PSMCallee } from "../PSMCallee.sol";

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

contract PSMCalleeTest is DSTest {

    address constant hevm     = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    address constant chainlog = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    uint256 constant WAD      = 1e18;

    address clipper;
    PSMCallee callee;
    uint256 tail;
    address vat;
    address usdp;
    address dai;
    address psm;

    function setUp() public {
        clipper = Chainlog(chainlog).getAddress("MCD_CLIP_PAXUSD_A");
        address daiJoin = Chainlog(chainlog).getAddress("MCD_JOIN_DAI");
        usdp = Chainlog(chainlog).getAddress("PAXUSD");
        dai = Chainlog(chainlog).getAddress("MCD_DAI");
        callee = new PSMCallee(daiJoin);
        vat = Chainlog(chainlog).getAddress("MCD_VAT");
        Vat(vat).hope(clipper);
        tail = Clipper(clipper).tail();
        psm = Chainlog(chainlog).getAddress("MCD_PSM_PAX_A");
    }

    // Disabled as this test is directed for a specific offboarding operation.
    // It should be modified and used once such operation is planned again.
    function test_take() private { // Make public to enable
        uint256 amt = 20_000 * WAD;

        address vault = 0x816F1dD29c428427A36799358a5f2e1CEa5E770c; // 14459
        address dog = Chainlog(chainlog).getAddress("MCD_DOG");
        uint256 id = Dog(dog).bark("PAXUSD-A", vault, address(this));
        address gemJoin = Chainlog(chainlog).getAddress("MCD_JOIN_PAXUSD_A");

        bytes memory data = abi.encode(
            address(123),
            address(gemJoin),
            uint256(0),
            psm
        );
        Hevm(hevm).warp(block.timestamp + 2 * tail / 3);

        assertEq(Token(dai).balanceOf(address(123)), 0);
        Clipper(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });
        assertEq(Token(dai).balanceOf(address(this)), 0);
        assertEq(Token(usdp).balanceOf(address(this)), 0);
        assert(Token(dai).balanceOf(address(123)) > 0);
    }
}
