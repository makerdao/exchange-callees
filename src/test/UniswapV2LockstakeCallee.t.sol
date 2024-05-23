// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.21;

import "lib/lockstake/lib/token-tests/lib/dss-test/src/DssTest.sol";

import { LockstakeClipper } from "lib/lockstake/src/LockstakeClipper.sol";
import { LockstakeEngineMock } from "lib/lockstake/test/mocks/LockstakeEngineMock.sol";
import { PipMock } from "lib/lockstake/test/mocks/PipMock.sol";

interface GemLike {
    function balanceOf(address) external view returns (uint256);
}

interface CalcFabLike {
    function newLinearDecrease(address) external returns (address);
    function newStairstepExponentialDecrease(address) external returns (address);
}

interface CalcLike {
    function file(bytes32, uint256) external;
}

contract UniswapV2LockstakeCalleeTest is DssTest {
    using stdStorage for StdStorage;

    DssInstance dss;
    address     pauseProxy;
    PipMock     pip;
    GemLike     dai;

    LockstakeEngineMock engine;
    LockstakeClipper clip;

    // Exchange exchange;

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    address ali;
    address bob;
    address che;

    bytes32 constant ilk = "LSE";
    uint256 constant price = 5 ether;

    uint256 constant startTime = 604411200; // Used to avoid issues with `block.timestamp`

    function _ink(bytes32 ilk_, address urn_) internal view returns (uint256) {
        (uint256 ink_,) = dss.vat.urns(ilk_, urn_);
        return ink_;
    }
    function _art(bytes32 ilk_, address urn_) internal view returns (uint256) {
        (,uint256 art_) = dss.vat.urns(ilk_, urn_);
        return art_;
    }

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 9;
    }

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 27;
    }

    // Copied from https://github.com/makerdao/lockstake/blob/735e1e85ca706534a77d8e1582df0d3248cbd2b6/test/LockstakeClipper.t.sol#L211-L249
    modifier takeSetup {
        address calc = CalcFabLike(dss.chainlog.getAddress("CALC_FAB")).newStairstepExponentialDecrease(address(this));
        CalcLike(calc).file("cut",  RAY - ray(0.01 ether));  // 1% decrease
        CalcLike(calc).file("step", 1);                      // Decrease every 1 second

        clip.file("buf",  ray(1.25 ether));   // 25% Initial price buffer
        clip.file("calc", address(calc));     // File price contract
        clip.file("cusp", ray(0.3 ether));    // 70% drop before reset
        clip.file("tail", 3600);              // 1 hour before reset

        (uint256 ink, uint256 art) = dss.vat.urns(ilk, address(this));
        assertEq(ink, 40 ether);
        assertEq(art, 100 ether);

        assertEq(clip.kicks(), 0);
        dss.dog.bark(ilk, address(this), address(this));
        assertEq(clip.kicks(), 1);

        (ink, art) = dss.vat.urns(ilk, address(this));
        assertEq(ink, 0);
        assertEq(art, 0);

        LockstakeClipper.Sale memory sale;
        (sale.pos, sale.tab, sale.lot, sale.tot, sale.usr, sale.tic, sale.top) = clip.sales(1);
        assertEq(sale.pos, 0);
        assertEq(sale.tab, rad(110 ether));
        assertEq(sale.lot, 40 ether);
        assertEq(sale.tot, 40 ether);
        assertEq(sale.usr, address(this));
        assertEq(sale.tic, block.timestamp);
        assertEq(sale.top, ray(5 ether)); // $4 plus 25%

        assertEq(dss.vat.gem(ilk, ali), 0);
        assertEq(dss.vat.dai(ali), rad(1000 ether));
        assertEq(dss.vat.gem(ilk, bob), 0);
        assertEq(dss.vat.dai(bob), rad(1000 ether));

        _;
    }

    // Copied from https://github.com/makerdao/lockstake/blob/735e1e85ca706534a77d8e1582df0d3248cbd2b6/test/LockstakeClipper.t.sol#L251-L317
    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.warp(startTime);

        dss = MCD.loadFromChainlog(LOG);

        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
        dai = GemLike(dss.chainlog.getAddress("MCD_DAI"));

        pip = new PipMock();
        pip.setPrice(price); // Spot = $2.5

        vm.startPrank(pauseProxy);
        dss.vat.init(ilk);

        dss.spotter.file(ilk, "pip", address(pip));
        dss.spotter.file(ilk, "mat", ray(2 ether)); // 200% liquidation ratio for easier test calcs
        dss.spotter.poke(ilk);

        dss.vat.file(ilk, "dust", rad(20 ether)); // $20 dust
        dss.vat.file(ilk, "line", rad(10000 ether));
        dss.vat.file("Line",      dss.vat.Line() + rad(10000 ether));

        dss.dog.file(ilk, "chop", 1.1 ether); // 10% chop
        dss.dog.file(ilk, "hole", rad(1000 ether));
        dss.dog.file("Hole",      dss.dog.Dirt() + rad(1000 ether));

        engine = new LockstakeEngineMock(address(dss.vat), ilk);
        dss.vat.rely(address(engine));
        vm.stopPrank();

        // dust and chop filed previously so clip.chost will be set correctly
        clip = new LockstakeClipper(address(dss.vat), address(dss.spotter), address(dss.dog), address(engine));
        clip.upchost();
        clip.rely(address(dss.dog));

        vm.startPrank(pauseProxy);
        dss.dog.file(ilk, "clip", address(clip));
        dss.dog.rely(address(clip));
        dss.vat.rely(address(clip));

        dss.vat.slip(ilk, address(this), int256(1000 ether));
        vm.stopPrank();

        assertEq(dss.vat.gem(ilk, address(this)), 1000 ether);
        assertEq(dss.vat.dai(address(this)), 0);
        dss.vat.frob(ilk, address(this), address(this), address(this), 40 ether, 100 ether);
        assertEq(dss.vat.gem(ilk, address(this)), 960 ether);
        assertEq(dss.vat.dai(address(this)), rad(100 ether));

        pip.setPrice(4 ether); // Spot = $2
        dss.spotter.poke(ilk); // Now unsafe

        ali = address(111);
        bob = address(222);
        che = address(333);

        dss.vat.hope(address(clip));
        vm.prank(ali); dss.vat.hope(address(clip));
        vm.prank(bob); dss.vat.hope(address(clip));

        vm.startPrank(pauseProxy);
        dss.vat.suck(address(0), address(this), rad(1000 ether));
        dss.vat.suck(address(0), address(ali),  rad(1000 ether));
        dss.vat.suck(address(0), address(bob),  rad(1000 ether));
        vm.stopPrank();
    }

    // Copied from https://github.com/makerdao/lockstake/blob/735e1e85ca706534a77d8e1582df0d3248cbd2b6/test/LockstakeClipper.t.sol#L828-L856
    function testTakeAtTab() public takeSetup {
        // Bid so owe (= 22 * 5 = 110 RAD) == tab (= 110 RAD)
        vm.prank(ali); clip.take({
            id:  1,
            amt: 22 ether,
            max: ray(5 ether),
            who: address(ali),
            data: ""
        });

        assertEq(dss.vat.gem(ilk, ali), 22 ether);  // Didn't take whole lot
        assertEq(dss.vat.dai(ali), rad(890 ether)); // Paid full tab (110)
        assertEq(dss.vat.gem(ilk, address(this)), 978 ether);  // 960 + (40 - 22) returned to usr

        // Assert auction ends
        LockstakeClipper.Sale memory sale;
        (sale.pos, sale.tab, sale.lot, sale.tot, sale.usr, sale.tic, sale.top) = clip.sales(1);
        assertEq(sale.pos, 0);
        assertEq(sale.tab, 0);
        assertEq(sale.lot, 0);
        assertEq(sale.tot, 0);
        assertEq(sale.usr, address(0));
        assertEq(sale.tic, 0);
        assertEq(sale.top, 0);

        assertEq(dss.dog.Dirt(), 0);
        (,,, uint256 dirt) = dss.dog.ilks(ilk);
        assertEq(dirt, 0);
    }
}
