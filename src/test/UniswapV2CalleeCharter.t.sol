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

pragma solidity >=0.6.12;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "ds-value/value.sol";
import "ds-math/math.sol";

import {Vat}     from "dss/vat.sol";
import {Spotter} from "dss/spot.sol";
import {Vow}     from "dss/vow.sol";
import {DaiJoin} from "dss/join.sol";

import {Clipper} from "dss/clip.sol";
import "dss/abaci.sol";
import "dss/dog.sol";

import {UniswapV2CalleeDai} from "../UniswapV2Callee.sol";

import { Hevm, PipLike, TestVat, TestVow, MockUniswapRouter02, Guy } from "./UniswapV2Callee.t.sol";
import { CharterManager, CharterManagerImp } from "dss-charter/CharterManager.sol";
import { ManagedGemJoin } from "dss-gem-joins/join-managed.sol";
import { ProxyManagerClipper } from "proxy-manager-clipper/ProxyManagerClipper.sol";

contract UniswapV2CalleeDaiTest is DSTest {
    Hevm hevm;

    TestVat vat;
    Dog     dog;
    Spotter spot;
    TestVow vow;
    DSValue pip;

    DaiJoin daiA;
    ManagedGemJoin gemA;

    ProxyManagerClipper clip;
    CharterManagerImp charter;

    MockUniswapRouter02 uniRouter02;
    UniswapV2CalleeDai uniCalleeDai;

    DSToken dai;
    DSToken gov;
    DSToken gold;

    address me;

    address ali;
    address bob;

    uint256 WAD = 10 ** 18;
    uint256 RAY = 10 ** 27;
    uint256 RAD = 10 ** 45;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    bytes32 constant ilk = "gold";

    uint256 constant startTime = 604411200; // Used to avoid issues with `now`

    modifier takeSetup(
        uint256 offset            // used to create potential rounding errors
    ) {
        uint256 pos;
        uint256 tab;
        uint256 lot;
        address usr;
        uint96  tic;
        uint256 top;
        uint256 ink;
        uint256 art;

        // Configure the price curve
        StairstepExponentialDecrease calc = new StairstepExponentialDecrease();
        calc.file("cut",  RAY - ray(0.01 ether));  // 1% decrease
        calc.file("step", 1);                      // Decrease every 1 second

        clip.file("buf",  ray(1.25 ether) + offset); // 25% Initial price buffer
        clip.file("calc", address(calc));     // File price contract
        clip.file("cusp", ray(0.3 ether));    // 70% drop before reset
        clip.file("tail", 3600);              // 1 hour before reset

        // Check my vault before liquidation
        // 40 gold collateral and 100 Dai debt
        (ink, art) = vat.urns(ilk, charter.proxy(me));
        assertEq(ink, 40 ether);
        assertEq(art, 100 ether);

        // Liquidate my vault and start an auction
        assertEq(clip.kicks(), 0);
        dog.bark(ilk, charter.proxy(me), address(this));
        assertEq(clip.kicks(), 1);

        // Ensure vault has been liquidated
        (ink, art) = vat.urns(ilk, charter.proxy(me));
        assertEq(ink, 0);
        assertEq(art, 0);

        // Ensure auction has started
        (pos, tab, lot, usr, tic, top) = clip.sales(1);
        assertEq(pos, 0);
        assertEq(tab, rad(110 ether));
        assertEq(lot, 40 ether);
        assertEq(usr, charter.proxy(me));
        assertEq(uint256(tic), now);
        assertEq(top, ray(5 ether) + 4 * offset); // $4 plus 25% price cushion = $5

        // Ensure alice and bob have 0 gold and 0 Dai each
        assertEq(vat.gem(ilk, ali), 0);
        assertEq(vat.gem(ilk, bob), 0);

        _;
    }

    modifier calleeSetup(uint256 price) {
        //====== Setup Exchange and Exchange Callee
        // Starting auction price is newPrice + 25% buffer = oldPrice
        // MockUniswapRouter02 uses the price so we can trade immediately after the auction begins
        uniRouter02 = new MockUniswapRouter02(price);
        uniCalleeDai = new UniswapV2CalleeDai(address(uniRouter02), address(daiA));
        charter.getOrCreateProxy(address(uniCalleeDai));
        //======

        vat.mint(address(me), rad(1000 ether));
        assertEq(vat.dai(me), rad(1100 ether));

        daiA.exit(address(uniRouter02), 1000 ether);

        assertEq(vat.dai(me), rad(100 ether));
        assertEq(dai.balanceOf(address(uniRouter02)), 1000 ether);
        _;
    }

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 9;
    }
    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 27;
    }

    function confirm_auction_ending() internal {
        (uint256 pos, uint256 tab, uint256 lot, address usr, uint256 tic, uint256 top) = clip.sales(1);
        assertEq(pos, 0);
        assertEq(tab, 0);
        assertEq(lot, 0);
        assertEq(usr, address(0));
        assertEq(uint256(tic), 0);
        assertEq(top, 0);
    }

    function execute(
        uint256 amt,
        uint256 maxPrice,
        uint256 minProfit
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(gold);
        path[1] = address(dai);
        bytes memory flashData = abi.encode(address(ali),    // Address of User (where profits are sent)
                                            address(gemA),   // GemJoin adapter of collateral type
                                            minProfit,       // Minimum Dai profit [wad]
                                            path,            // uni path,
                                            address(charter) // CharterManager
        );

        Guy(ali).take({
            id:  1,
            amt: amt,
            max: maxPrice,
            who: address(uniCalleeDai),
            data: flashData
        });
    }

    function try_execute(
        uint256 amt,
        uint256 maxPrice,
        uint256 minProfit
    ) internal returns (bool ok)  {
        address[] memory path = new address[](2);
        path[0] = address(gold);
        path[1] = address(dai);
        bytes memory flashData = abi.encode(address(ali),    // Address of User (where profits are sent)
                                            address(gemA),   // GemJoin adapter of collateral type
                                            minProfit,       // Minimum Dai profit [wad]
                                            path,            // uni path
                                            address(charter) //CharterManager
        );

        ok = Guy(ali).try_take({
                  id:  1,
                  amt: amt,
                  max: maxPrice,
                  who: address(uniCalleeDai),
                  data: flashData
             });
    }


    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        hevm.warp(startTime);

        me = address(this);

        gov = new DSToken('GOV');
        gov.mint(100 ether);

        vat = new TestVat();

        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        vow = new TestVow(address(vat), address(0), address(0));

        dog = new Dog(address(vat));
        dog.file("vow", address(vow));
        vat.rely(address(dog));
        vow.rely(address(dog));

        gold = new DSToken("GEM");
        gold.mint(1000 ether);


        vat.init(ilk);

        dai  = new DSToken("Dai");
        daiA = new DaiJoin(address(vat), address(dai));
        vat.rely(address(daiA));
        dai.setOwner(address(daiA));

        CharterManager base = new CharterManager();
        base.setImplementation(address(new CharterManagerImp(address(vat), address(vow), address(spot))));
        charter = CharterManagerImp(address(base));
        gold.approve(address(charter));

        gemA = new ManagedGemJoin(address(vat), ilk, address(gold));
        vat.rely(address(gemA));
        gemA.rely(address(charter));
        gemA.deny(me); // Only access should be through manager
        charter.join(address(gemA), me, 1000 ether);

        pip = new DSValue();

         // $5 per gold. Spot sees $2.5 b/c of 200% LR
        uint256 oldPrice = uint256(5 ether);
        pip.poke(bytes32(oldPrice));

        spot.file(ilk, bytes32("pip"), address(pip));

         // 200% Liquidation ratio (LR) for easier test calcs
        spot.file(ilk, bytes32("mat"), ray(2 ether));
        spot.poke(ilk);

        vat.file(ilk, "line", rad(1000 ether));
        vat.file("Line",      rad(1000 ether));

        clip = new ProxyManagerClipper(address(vat), address(spot), address(dog), address(gemA), address(charter));
        clip.rely(address(dog));

        dog.file(ilk, "clip", address(clip));
        dog.file(ilk, "chop", 1.1 ether); // 10% chop
        dog.file(ilk, "hole", rad(1000 ether));
        dog.file("Hole", rad(1000 ether));
        dog.rely(address(clip));

        vat.rely(address(clip));

        gold.approve(address(vat));

        assertEq(vat.gem(ilk, charter.proxy(me)), 1000 ether);
        assertEq(vat.dai(me), 0);
        charter.frob(ilk, me, me, me, 40 ether, 100 ether);
        assertEq(vat.gem(ilk, charter.proxy(me)), 960 ether);
        assertEq(vat.dai(me), rad(100 ether));

        // $4 per gold. Spot sees $2 b/c of 200% LR
        uint256 newPrice = uint256(4 ether);
        pip.poke(bytes32(newPrice));
        spot.poke(ilk);          // Now unsafe

        ali = address(new Guy(Clipper(address(clip))));
        bob = address(new Guy(Clipper(address(clip))));

        Guy(ali).hope(address(clip));
        Guy(bob).hope(address(clip));
        vat.hope(address(daiA));
    }

    function test_flash_take_profit() public takeSetup(0) calleeSetup((uint256(6 ether))) {
        // Bid so owe (= 25 * 5 = 125 RAD) > tab (= 110 RAD), so auction will only give 22 gold

        // uniRouter02 has 1000 Dai, buying gold for $6
        // Profit opportunity of $22

        // Ali sets minimum profit to $30, but it fails
        assertTrue(!try_execute(25 ether, ray(5 ether), 30 ether));

        // Ali sets minimum profit to exact profit opporunity (now $11)
        execute(11 ether, ray(5 ether), 11 ether);

        // Ali sets minimum profit to 0 Dai
        execute(11 ether, ray(5 ether), 0 ether);

        assertEq(vat.gem(ilk, ali),   0 ether);    // Didn't take any gold
        assertEq(dai.balanceOf(ali), 22 ether);    // ($6 - $5) * 22 = 22 Dai profit
        assertEq(vat.gem(ilk, charter.proxy(me)),  978 ether);    // 960 + (40 - 22) returned to usr

        // Assert auction ends
        confirm_auction_ending();
    }
}
