pragma solidity >=0.5.12;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "ds-value/value.sol";
import "ds-math/math.sol";

import {Vat}     from "dss/vat.sol";
import {Spotter} from "dss/spot.sol";
import {Vow}     from "dss/vow.sol";
import {GemJoin, DaiJoin} from "dss/join.sol";

import {Clipper} from "dss/clip.sol";
import "dss/abaci.sol";
import "dss/dog.sol";

import {CalleeMakerOtcDai} from "./OasisDexCallee.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}
interface PipLike {
    function peek() external returns (bytes32, bool);
    function poke(bytes32) external;
}

contract TestVat is Vat {
    function mint(address usr, uint256 rad) public {
        dai[usr] += rad;
    }
}

contract TestVow is Vow {
    constructor(address vat, address flapper, address flopper)
        public Vow(vat, flapper, flopper) {}
    // Total deficit
    function Awe() public view returns (uint256) {
        return vat.sin(address(this));
    }
    // Total surplus
    function Joy() public view returns (uint256) {
        return vat.dai(address(this));
    }
    // Unqueued, pre-auction debt
    function Woe() public view returns (uint256) {
        return sub(sub(Awe(), Sin), Ash);
    }
}

contract MockOtc is DSMath {
    function getPayAmount(address payGem, address buyGem, uint buyAmt) public pure returns (uint payAmt) {
        payGem;
        buyGem;

        // Harcoded to simulate 300 payGem (gold = DSToken("GEM")) = 1 buyGem
        payAmt = wmul(buyAmt, 300 ether); // Harcoded to simulate 300 payGem gold = 1 buyGem
    }

    function buyAllAmount(address buyGem, uint buyAmt, address payGem, uint maxPayAmt) public {
        uint payAmt = wmul(buyAmt, 300 ether);
        require(maxPayAmt >= payAmt, "");
        DSToken(payGem).transferFrom(msg.sender, address(this), payAmt);
        DSToken(buyGem).transfer(msg.sender, buyAmt);
    }

    // WIP
    function sellAllAmount(address payGem, uint payAmt, address buyGem, uint minFillAmt) public {
        uint buyAmt = wmul(payAmt, 300 ether);
        require(minFillAmt >= buyAmt, "");
        DSToken(payGem).transferFrom(msg.sender, address(this), buyAmt);
        DSToken(buyGem).transfer(msg.sender, payAmt);
    }



}

contract Guy {
    Clipper clip;

    constructor(Clipper clip_) public {
        clip = clip_;
    }

    function hope(address usr) public {
        Vat(address(clip.vat())).hope(usr);
    }

    function take(
        uint256 id,
        uint256 amt,
        uint256 pay,
        address who,
        bytes calldata data
    )
        external
    {
        clip.take({
            id: id,
            amt: amt,
            pay: pay,
            who: who,
            data: data
        });
    }
}

contract DutchClipperTest is DSTest {
    Hevm hevm;

    TestVat vat;
    Dog     dog;
    Spotter spot;
    TestVow vow;
    DSValue pip;

    DaiJoin daiA;
    GemJoin gemA;

    Clipper clip;

    MockOtc otc;
    CalleeMakerOtcDai calleeOtcDai;

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

    modifier takeSetup {
        uint256 pos;
        uint256 tab;
        uint256 lot;
        address usr;
        uint96  tic;
        uint256 top;
        uint256 ink;
        uint256 art;

        StairstepExponentialDecrease calc = new StairstepExponentialDecrease();
        calc.file(bytes32("cut"),  ray(0.01 ether)); // 1% decrease
        calc.file(bytes32("step"), 1);               // Decrease every 1 second

        clip.file(bytes32("buf"),  ray(1.25 ether)); // 25% Initial price buffer
        clip.file(bytes32("dust"), rad(20   ether)); // $20 dust
        clip.file(bytes32("calc"), address(calc));   // File price contract
        clip.file(bytes32("cusp"), ray(0.3 ether));  // 70% drop before reset
        clip.file(bytes32("tail"), 3600);            // 1 hour before reset

        (ink, art) = vat.urns(ilk, me);
        assertEq(ink, 40 ether);
        assertEq(art, 100 ether);

        assertEq(clip.kicks(), 0);
        dog.bark(ilk, me);
        assertEq(clip.kicks(), 1);

        (ink, art) = vat.urns(ilk, me);
        assertEq(ink, 0);
        assertEq(art, 0);

        (pos, tab, lot, usr, tic, top) = clip.sales(1);
        assertEq(pos, 0);
        assertEq(tab, rad(110 ether));
        assertEq(lot, 40 ether);
        assertEq(usr, me);
        assertEq(uint256(tic), now);
        assertEq(top, ray(5 ether)); // $4 plus 25%

        assertEq(vat.gem(ilk, ali), 0);
        assertEq(vat.dai(ali), rad(1000 ether));
        assertEq(vat.gem(ilk, bob), 0);
        assertEq(vat.dai(bob), rad(1000 ether));

        _;
    }

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 9;
    }
    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        hevm.warp(startTime);

        me = address(this);

        gov = new DSToken('GOV');
        gov.mint(100 ether);

        vat = new TestVat();
        vat = vat;

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

        gemA = new GemJoin(address(vat), ilk, address(gold));
        vat.rely(address(gemA));
        gold.approve(address(gemA));
        gemA.join(me, 1000 ether);

        pip = new DSValue();
        pip.poke(bytes32(uint256(5 ether))); // Spot = $2.5

        spot.file(ilk, bytes32("pip"), address(pip));
        spot.file(ilk, bytes32("mat"), ray(2 ether)); // 100% liquidation ratio for easier test calcs
        spot.poke(ilk);

        vat.file(ilk, "line", rad(1000 ether));
        vat.file("Line",         rad(1000 ether));

        clip = new Clipper(address(vat), address(spot), address(dog), ilk);
        clip.rely(address(dog));

        dog.file(ilk, "clip", address(clip));
        dog.file(ilk, "chop", 1.1 ether); // 10% chop
        dog.file("hole", rad(1000 ether));
        dog.rely(address(clip));

        vat.rely(address(clip));

        gold.approve(address(vat));

        assertEq(vat.gem(ilk, me), 1000 ether);
        assertEq(vat.dai(me), 0);
        vat.frob(ilk, me, me, me, 40 ether, 100 ether);
        assertEq(vat.gem(ilk, me), 960 ether);
        assertEq(vat.dai(me), rad(100 ether));

        pip.poke(bytes32(uint256(4 ether))); // Spot = $2
        spot.poke(ilk);          // Now unsafe

        ali = address(new Guy(clip));
        bob = address(new Guy(clip));

        Guy(ali).hope(address(clip));
        Guy(bob).hope(address(clip));

        //====== Setup Exchange and Exchange Callee
        otc = new MockOtc();
        calleeOtcDai = new CalleeMakerOtcDai(address(otc), address(clip), address(daiA));

        //======


        vat.mint(address(ali), rad(1000 ether));
        vat.mint(address(bob), rad(1000 ether));
        vat.mint(address(me), rad(1000 ether));

        daiA.exit(address(otc), 1000 ether);
        assertEq(dai.balanceOf(address(otc)), 1000 ether);
    }

    function test_flashTake_at_tab() public takeSetup {
        // Bid so owe (= 25 * 5 = 125 RAD) > tab (= 110 RAD)
        // Readjusts slice to be tab/top = 25


        Guy(ali).take({
            id:  1,
            amt: 25 ether,
            pay: ray(5 ether),
            who: address(ali),
            data: ''
        });

        assertEq(vat.gem(ilk, ali), 22 ether);  // Didn't take whole lot
        assertEq(vat.dai(ali), rad(890 ether)); // Didn't pay more than tab (110)
        assertEq(vat.gem(ilk, me),  978 ether); // 960 + (40 - 22) returned to usr

        // Assert auction ends
        (uint256 pos, uint256 tab, uint256 lot, address usr, uint256 tic, uint256 top) = clip.sales(1);
        assertEq(pos, 0);
        assertEq(tab, 0);
        assertEq(lot, 0);
        assertEq(usr, address(0));
        assertEq(uint256(tic), 0);
        assertEq(top, 0);
    }

    function test_take_at_tab() public takeSetup {
        // Bid so owe (= 22 * 5 = 110 RAD) == tab (= 110 RAD)
        Guy(ali).take({
            id:  1,
            amt: 22 ether,
            pay: ray(5 ether),
            who: address(ali),
            data: ''
        });

        assertEq(vat.gem(ilk, ali), 22 ether);  // Didn't take whole lot
        assertEq(vat.dai(ali), rad(890 ether)); // Paid full tab (110)
        assertEq(vat.gem(ilk, me), 978 ether);  // 960 + (40 - 22) returned to usr

        // Assert auction ends
        (uint256 pos, uint256 tab, uint256 lot, address usr, uint256 tic, uint256 top) = clip.sales(1);
        assertEq(pos, 0);
        assertEq(tab, 0);
        assertEq(lot, 0);
        assertEq(usr, address(0));
        assertEq(uint256(tic), 0);
        assertEq(top, 0);
    }

    function test_take_under_tab() public takeSetup {
        // Bid so owe (= 11 * 5 = 55 RAD) < tab (= 110 RAD)
        Guy(ali).take({
            id:  1,
            amt: 11 ether,     // Half of tab at $110
            pay: ray(5 ether),
            who: address(ali),
            data: ''
        });

        assertEq(vat.gem(ilk, ali), 11 ether);  // Didn't take whole lot
        assertEq(vat.dai(ali), rad(945 ether)); // Paid half tab (55)
        assertEq(vat.gem(ilk, me), 960 ether);  // Collateral not returned (yet)

        // Assert auction DOES NOT end
        (uint256 pos, uint256 tab, uint256 lot, address usr, uint256 tic, uint256 top) = clip.sales(1);
        assertEq(pos, 0);
        assertEq(tab, rad(55 ether));  // 110 - 5 * 11
        assertEq(lot, 29 ether);       // 40 - 11
        assertEq(usr, me);
        assertEq(uint256(tic), now);
        assertEq(top, ray(5 ether));
    }

    function testFail_take_bid_too_low() public takeSetup {
        // Bid so max (= 4) < price (= top = 5) (fails with "Clipper/too-expensive")
        Guy(ali).take({
            id:  1,
            amt: 22 ether,
            pay: ray(4 ether),
            who: address(ali),
            data: ''
        });
    }

    function testFail_take_bid_creates_dust() public takeSetup {
        // Bid so owe (= (22 - 1wei) * 5 = 110 RAD - 1) < tab (= 110 RAD) (fails with "Clipper/dust")
        Guy(ali).take({
            id:  1,
            amt: 22 ether - 1,
            pay: ray(5 ether),
            who: address(ali),
            data: ''
        });
    }

    function test_take_multiple_bids_different_prices() public takeSetup {
        uint256 pos;
        uint256 tab;
        uint256 lot;
        address usr;
        uint96  tic;
        uint256 top;

        // Bid so owe (= 10 * 5 = 50 RAD) < tab (= 110 RAD)
        Guy(ali).take({
            id:  1,
            amt: 10 ether,
            pay: ray(5 ether),
            who: address(ali),
            data: ''
        });

        assertEq(vat.gem(ilk, ali), 10 ether);  // Didn't take whole lot
        assertEq(vat.dai(ali), rad(950 ether)); // Paid some tab (50)
        assertEq(vat.gem(ilk, me), 960 ether);  // Collateral not returned (yet)

        // Assert auction DOES NOT end
        (pos, tab, lot, usr, tic, top) = clip.sales(1);
        assertEq(pos, 0);
        assertEq(tab, rad(60 ether));  // 110 - 5 * 10
        assertEq(lot, 30 ether);       // 40 - 10
        assertEq(usr, me);
        assertEq(uint256(tic), now);
        assertEq(top, ray(5 ether));

        hevm.warp(now + 30);

        Guy(bob).take({
            id:  1,
            amt: 30 ether,     // Buy the rest of the lot
            pay: ray(4 ether), // 5 * 0.99 ** 30 = 3.698501866941401 RAY => max > pay
            who: address(bob),
            data: ''
        });

        // Assert auction is over
        (pos, tab, lot, usr, tic, top) = clip.sales(1);
        assertEq(pos, 0);
        assertEq(tab, 0);
        assertEq(lot, 0 * WAD);
        assertEq(usr, address(0));
        assertEq(uint256(tic), 0);
        assertEq(top, 0);

        assertEq(vat.gem(ilk, bob), 15 ether);  // Didn't take whole lot
        assertEq(vat.dai(bob), rad(940 ether)); // Paid rest of tab (60)

        uint256 lotReturn = 30 ether - (rad(60 ether) / ray(4 ether));       // lot - loaf.tab / max = 15
        assertEq(vat.gem(ilk, me), 960 ether + lotReturn);                   // Collateral returned (10 WAD)
    }
}

