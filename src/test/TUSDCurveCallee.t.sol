// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2022 Dai Foundation
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

pragma solidity 0.6.12;

import "ds-test/test.sol";
import { TUSDCurveCallee } from "../TUSDCurveCallee.sol";
import { LinearDecrease } from "dss/abaci.sol";

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
    function setImplementation(address, uint256) external;
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

interface Dog {
    function bark(bytes32, address, address) external returns (uint256);
    function file(bytes32, bytes32, uint256) external;
}

interface Spot {
    function file(bytes32, bytes32, uint256) external;
    function poke(bytes32) external;
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
    function file(bytes32 what, address data) external;
    function getStatus(uint256 id) external returns (bool, uint256, uint256, uint256);
    function count() external returns (uint256);
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
    uint256 constant RAY      = 1e27;
    uint256 constant RAD      = 1e45;

    address gemJoin;
    uint256 id;
    address clipper;
    TUSDCurveCallee callee;
    uint256 tail;
    address vat;
    address dog;
    address dai;
    address spotter;
    address osm;
    address daiJoin;
    LinearDecrease calc;

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
        daiJoin = Chainlog(chainlog).getAddress("MCD_JOIN_DAI");
        vat =     Chainlog(chainlog).getAddress("MCD_VAT");
        dog =     Chainlog(chainlog).getAddress("MCD_DOG");
        dai =     Chainlog(chainlog).getAddress("MCD_DAI");
        gemJoin = Chainlog(chainlog).getAddress("MCD_JOIN_TUSD_A");
        spotter = Chainlog(chainlog).getAddress("MCD_SPOT");
        osm =     Chainlog(chainlog).getAddress("PIP_TUSD");

        callee = new TUSDCurveCallee(curve, daiJoin);
        calc = new LinearDecrease();

        // TODO: remove once new implementation is set on mainnet
        takeOwnership(gemJoin);
        Join(gemJoin).setImplementation(address(0xd8D59c59Ab40B880b54C969920E8d9172182Ad7b), 1);
        renounceOwnership(gemJoin);

        Vat(vat).hope(clipper);

        takeOwnership(dog);
        takeOwnership(clipper);

        // Note: parameters taken from https://forum.makerdao.com/t/proposed-parameters-for-offboarding-tusd-a/13506

        // Enable liquidations
        Clipper(clipper).file("stopped", 0);

        // Use Abacus/LinearDecrease – tau [seconds]
        Clipper(clipper).file("calc", address(calc));

        // Set liquidation penalty (chop) to 0
        Dog(dog).file("TUSD-A", "chop", 1.0 * WAD);

        // Set LR to 150%
        // This is simulated in newAuction() after opening a new auction

        // Set buff to 1
        Clipper(clipper).file("buf", 1.0 * RAY); // 0% Initial price buffer

        // Set tau to 21,600,000 second (est. 10bps drop per 6 hours = 250 days till 0)
        calc.file(bytes32("tau"), 21_600_000);

        // Cusp not relevant, stays the same (tail will stop the auction)
        // (Currently 90% decrease)

        // Set tail to 432,000 second (5 days, implies minimum price of 0.98)
        Clipper(clipper).file("tail", 432_000);
        tail = Clipper(clipper).tail();

        // Set hole on 5m
        Dog(dog).file("TUSD-A", "hole", 5_000_000 * RAD);

        // Set chip to 0 (no need to be fast)
        Clipper(clipper).file("chip", 0);

        // Set tip to 500 (bit higher value so that we guarantee kicking all vaults)
        Clipper(clipper).file("tip", 500 * RAD);

        renounceOwnership(clipper);
        renounceOwnership(dog);
    }

    function newAuction(uint256 amt) internal {
        giveTokens(tusd, amt);

        Token(tusd).approve(gemJoin, amt);
        Join(gemJoin).join(address(this), amt);
        (, uint256 rate, uint256 spot,,) = Vat(vat).ilks("TUSD-A");
        uint256 maxArt = amt * spot / rate;

        // Support creating more positions (for testing only)
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

        // Set LR to 150%
        takeOwnership(spotter);
        Spot(spotter).file("TUSD-A", bytes32("mat"), 150 * RAY / 100);
        renounceOwnership(spotter);
        Spot(spotter).poke("TUSD-A");

        id = Dog(dog).bark("TUSD-A", address(this), address(this));

        // Set LR back to 101%
        takeOwnership(spotter);
        Spot(spotter).file("TUSD-A", bytes32("mat"), 101 * RAY / 100);
        renounceOwnership(spotter);
        Spot(spotter).poke("TUSD-A");
    }

    function test_baseline() public {
        uint256 amt = 20_000 * WAD;
        newAuction(amt);
        bytes memory data = abi.encode(
            address(123),
            address(gemJoin),
            uint256(0)
        );
        Hevm(hevm).warp(block.timestamp + tail / 2);
        uint256 countBefore = Clipper(clipper).count();
        Clipper(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });

        assertEq(Clipper(clipper).count(), countBefore - 1);
        assertEq(Token(dai).balanceOf(address(this)), 0);
        assertEq(Token(tusd).balanceOf(address(this)), 0);
    }

    function test_profit() public {
        uint256 minProfit = 1000 * WAD;
        uint256 amt = 1_000_000 * WAD;
        newAuction(amt);
        bytes memory data = abi.encode(
            address(123),
            address(gemJoin),
            uint256(minProfit)
        );
        Hevm(hevm).warp(block.timestamp + tail / 2);
        uint256 countBefore = Clipper(clipper).count();
        Clipper(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });
        assertEq(Clipper(clipper).count(), countBefore - 1);
        assertGe(Token(dai).balanceOf(address(123)), minProfit);
    }

    function test_profitBigAmt() public {
        uint256 minProfit = 1000 * WAD;
        uint256 amt = 6_000_000 * WAD;
        newAuction(amt);
        bytes memory data = abi.encode(
            address(123),
            address(gemJoin),
            uint256(minProfit)
        );
        Hevm(hevm).warp(block.timestamp + tail / 2);
        uint256 countBefore = Clipper(clipper).count();
        Clipper(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });
        assertEq(Clipper(clipper).count(), countBefore - 1);
        assertGe(Token(dai).balanceOf(address(123)), minProfit);
    }

    function test_profitAllCollateral() public {
        uint256 minProfit = 1000 * WAD;
        uint256 amt = 26_000_000 * WAD;
        newAuction(amt);
        bytes memory data = abi.encode(
            address(123),
            address(gemJoin),
            uint256(minProfit)
        );

        // Jump ahead to when price goes down enough to make up for the slippage
        Hevm(hevm).warp(block.timestamp + tail * 9 / 10);
        uint256 countBefore = Clipper(clipper).count();
        Clipper(clipper).take({
            id:   id,
            amt:  amt,
            max:  type(uint256).max,
            who:  address(callee),
            data: data
        });
        assertEq(Clipper(clipper).count(), countBefore - 1);
        assertGe(Token(dai).balanceOf(address(123)), minProfit);
    }

    function test_maxPrice() public {
        uint256 amt = 20_000 * WAD;
        newAuction(amt);
        bytes memory data = abi.encode(
            address(this),
            address(gemJoin),
            uint256(0)
        );

        // Make sure price goes down enough to make up for the Curve slippage
        Hevm(hevm).warp(block.timestamp + tail / 5);
        Hevm(hevm).store({
            c:   osm,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(uint256(1))
        });
        uint256 max = uint256(Osm(osm).read()) * 1e9; // WAD * 1e9 = RAY
        uint256 countBefore = Clipper(clipper).count();
        Clipper(clipper).take({
            id:   id,
            amt:  amt,
            max:  max,
            who:  address(callee),
            data: data
        });
        assertEq(Clipper(clipper).count(), countBefore - 1);
    }

    function test_tailPrice() public {
        uint256 amt = 20_000 * WAD;
        newAuction(amt);

        (bool needsRedo, uint256 priceBark,,) = Clipper(clipper).getStatus(id);
        assertTrue(!needsRedo);

        Hevm(hevm).warp(block.timestamp + tail);

        uint256 priceTail;
        (needsRedo, priceTail,,) = Clipper(clipper).getStatus(id);
        assertTrue(!needsRedo);

        // Make sure 2% decrease is reached at tail
        assertEq(priceTail * WAD / priceBark, 98 * WAD / 100);

        Hevm(hevm).warp(block.timestamp + 1);
        (needsRedo,,,) = Clipper(clipper).getStatus(id);
        assertTrue(needsRedo);
    }
}
