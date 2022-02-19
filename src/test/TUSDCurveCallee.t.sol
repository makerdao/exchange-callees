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
import { TUSDCurveCallee } from "../TUSDCurveCallee.sol";

interface Hevm {
    function store(address c, bytes32 loc, bytes32 val) external;
    function warp(uint256) external;
    function load(address,bytes32) external returns (bytes32);
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
    function urns(bytes32, address)
        external view returns (uint256, uint256);
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
    function file(bytes32, bytes32, uint256) external;
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
    function file(bytes32 what, uint256 data) external;
}

interface Osm {
    function read() external view returns (bytes32);
    function kiss(address) external;
}

contract CurveCalleeTest is DSTest {

    address constant hevm     = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    address constant tusd     = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address constant chainlog = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant curve    = 0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1;
    uint256 constant WAD      = 1e18;

    address gemJoin;
    uint256 id;
    address clipper;
    TUSDCurveCallee callee;
    uint256 tail;
    address vat;

    function giveTokens(address token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (Token(token).balanceOf(address(this)) == amount) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = Hevm(hevm).load(
                address(token),
                keccak256(abi.encode(address(this), uint256(i)))
            );
            Hevm(hevm).store(
                address(token),
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (Token(token).balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                Hevm(hevm).store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function takeOwnership(address target) internal {
        Hevm(hevm).store({
            c:   target,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(uint256(1))
        });
    }

    function renounceOwnership(address target) internal {
        Hevm(hevm).store({
            c:   target,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(uint256(0))
        });
    }

    function setUp() public {
        clipper = Chainlog(chainlog).getAddress("MCD_CLIP_TUSD_A");
        address daiJoin = Chainlog(chainlog).getAddress("MCD_JOIN_DAI");
        callee = new TUSDCurveCallee(curve, daiJoin);
        vat = Chainlog(chainlog).getAddress("MCD_VAT");
        Vat(vat).hope(clipper);
        tail = Clipper(clipper).tail();

        // Turn on liquidations

        // Take control of dog
        address dog = Chainlog(chainlog).getAddress("MCD_DOG");
        takeOwnership(dog);
        Dog(dog).file("TUSD-A", "hole", type(uint256).max);

        renounceOwnership(dog);

        // Take control of clipper
        takeOwnership(clipper);
        Clipper(clipper).file("stopped", 0);
        renounceOwnership(clipper);
    }

    function newAuction(uint256 amt) internal {
        // tusd._balances[address(this)] = amt;
        giveTokens(tusd, amt);

        gemJoin = Chainlog(chainlog).getAddress("MCD_JOIN_TUSD_A");
        Token(tusd).approve(gemJoin, amt);
        Join(gemJoin).join(address(this), amt);
        (, uint256 rate, uint256 spot,,) = Vat(vat).ilks("TUSD-A");
        uint256 maxArt = amt * spot / rate;

        takeOwnership(vat);
        Vat(vat).file("TUSD-A", "line", type(uint256).max);
        renounceOwnership(vat);

        Vat(vat).frob({
            i:    "TUSD-A",
            u:    address(this),
            v:    address(this),
            w:    address(this),
            dink: int(amt),
            dart: int(maxArt)
        });

        takeOwnership(vat);
        Vat(vat).file("TUSD-A", "spot", spot * 99 / 100); // Simulate reducing liquidation ratio
        renounceOwnership(vat);

        address dog = Chainlog(chainlog).getAddress("MCD_DOG");
        id = Dog(dog).bark("TUSD-A", address(this), address(this));
    }

    function test_baseline() public {
        uint256 amt = 20000 * WAD;
        newAuction(amt);
        bytes memory data = abi.encode(
            address(123),
            address(gemJoin),
            uint256(0),
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

        address dai = Chainlog(chainlog).getAddress("MCD_DAI");
        assertEq(Token(dai).balanceOf(address(this)), 0);
        assertEq(Token(tusd).balanceOf(address(this)), 0);
    }

    function test_bigAmt() public {
        uint256 amt = 10_000_000 * WAD;
        newAuction(amt);
        bytes memory data = abi.encode(
            address(this),
            address(gemJoin),
            uint256(0),
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
        bytes memory data = abi.encode(
            address(123),
            address(gemJoin),
            uint256(minProfit),
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
        address dai = Chainlog(chainlog).getAddress("MCD_DAI");
        assertGe(Token(dai).balanceOf(address(123)), minProfit);
    }

    function test_maxPrice() public {
        uint256 amt = 50 * WAD;
        newAuction(amt);
        bytes memory data = abi.encode(
            address(this),
            address(gemJoin),
            uint256(0),
            address(0)
        );
        Hevm(hevm).warp(block.timestamp + tail / 2);
        address osm = Chainlog(chainlog).getAddress("PIP_TUSD");
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
        bytes memory data = abi.encode(
            address(this),
            address(gemJoin),
            uint256(0),
            address(0)
        );
        Hevm(hevm).warp(block.timestamp + tail / 5);
        address osm = Chainlog(chainlog).getAddress("PIP_TUSD");
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