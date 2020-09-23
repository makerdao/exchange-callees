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
    // Overrides Vat.frob(), so we can mint Dai directly to accounts and without
    // restriction from the debt ceilings
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

contract MockOtc is DSMath, DSTest {
    uint256 fixedPrice;

    constructor(uint256 price_) public {
        fixedPrice = price_;
    }

    // Hardcoded to simulate fixed price Maker Otc
    function sellAllAmount(address payGem, uint payAmt, address buyGem, uint minFillAmt) public returns (uint buyAmt) {
        buyAmt = wmul(payAmt, fixedPrice);
        require(minFillAmt <= buyAmt, "Minimum Fill not reached");

        DSToken(payGem).transferFrom(msg.sender, address(this), payAmt);
        assertEq(DSToken(payGem).balanceOf(address(this)), payAmt);

        DSToken(buyGem).transfer(msg.sender, buyAmt);
        assertEq(DSToken(buyGem).balanceOf(msg.sender), buyAmt);

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

contract CalleeOtcDaiTest is DSTest {
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

    modifier takeSetup() {
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
        calc.file(bytes32("cut"),  ray(0.01 ether)); // 1% decrease
        calc.file(bytes32("step"), 1);               // Decrease every 1 second

        clip.file(bytes32("buf"),  ray(1.25 ether)); // 25% Initial price buffer
        clip.file(bytes32("dust"), rad(20   ether)); // $20 dust
        clip.file(bytes32("calc"), address(calc));   // File price contract
        clip.file(bytes32("cusp"), ray(0.3 ether));  // 70% drop before reset
        clip.file(bytes32("tail"), 3600);            // 1 hour before reset

        // Check my vault before liquidation
        // 40 gold collateral and 100 Dai debt
        (ink, art) = vat.urns(ilk, me);
        assertEq(ink, 40 ether);
        assertEq(art, 100 ether);

        // Liquidate my vault and start an auction
        assertEq(clip.kicks(), 0);
        dog.bark(ilk, me);
        assertEq(clip.kicks(), 1);

        // Ensure vault has been liquidated
        (ink, art) = vat.urns(ilk, me);
        assertEq(ink, 0);
        assertEq(art, 0);

        // Ensure auction has started
        (pos, tab, lot, usr, tic, top) = clip.sales(1);
        assertEq(pos, 0);
        assertEq(tab, rad(110 ether));
        assertEq(lot, 40 ether);
        assertEq(usr, me);
        assertEq(uint256(tic), now);
        assertEq(top, ray(5 ether)); // $4 plus 25% price cushion = $5

        // Ensure alice and bob have 0 gold and 0 Dai each
        assertEq(vat.gem(ilk, ali), 0);
        assertEq(vat.gem(ilk, bob), 0);

        _;
    }

    modifier calleeSetup(uint256 price) {
        //====== Setup Exchange and Exchange Callee
        // Starting auction price is newPrice + 25% buffer = oldPrice
        // MockOtc uses the oldPrice, so we can trade immediately after the auction begins
        otc = new MockOtc(price);
        calleeOtcDai = new CalleeMakerOtcDai(address(otc), address(clip), address(daiA));
        //======

        vat.mint(address(me), rad(1000 ether));
        assertEq(vat.dai(me), rad(1100 ether));

        daiA.exit(address(otc), 1000 ether);

        assertEq(vat.dai(me), rad(100 ether));
        assertEq(dai.balanceOf(address(otc)), 1000 ether);
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

        gemA = new GemJoin(address(vat), ilk, address(gold));
        vat.rely(address(gemA));
        gold.approve(address(gemA));
        gemA.join(me, 1000 ether);

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

        clip = new Clipper(address(vat), address(spot), address(dog), ilk);
        clip.rely(address(dog));

        dog.file(ilk, "clip", address(clip));
        dog.file(ilk, "chop", 1.1 ether);    // 10% Liquidation Penalty
        dog.file("hole", rad(1000 ether));
        dog.rely(address(clip));

        vat.rely(address(clip));

        gold.approve(address(vat));

        assertEq(vat.gem(ilk, me), 1000 ether);
        assertEq(vat.dai(me), 0);
        vat.frob(ilk, me, me, me, 40 ether, 100 ether);
        assertEq(vat.gem(ilk, me), 960 ether);
        assertEq(vat.dai(me), rad(100 ether));

        // $4 per gold. Spot sees $2 b/c of 200% LR
        uint256 newPrice = uint256(4 ether);
        pip.poke(bytes32(newPrice));
        spot.poke(ilk);          // Now unsafe

        ali = address(new Guy(clip));
        bob = address(new Guy(clip));

        Guy(ali).hope(address(clip));
        Guy(bob).hope(address(clip));
        vat.hope(address(daiA));


    }

    function test_flash_take_no_profit() public takeSetup calleeSetup((uint256(5 ether))) {
        // Bid so owe (= 25 * 5 = 125 RAD) > tab (= 110 RAD), so auction Will only give 22 gold

        // Maker otc has 1000 Dai and willing to buy gold at $5
        // Ali will use calleeOtcDai to flashloan with Maker Otc and pay back Clipper
        // Ali will not take any profit, as there is no profit opportunity

        bytes memory flashData = abi.encode(address(ali),      // Address of User (where profits are sent)
                                            address(gemA),     // GemJoin adapter of collateral type
                                            uint256(0 ether)   // Minimum Dai profit [wad]
        );

        Guy(ali).take({
            id:  1,
            amt: 25 ether,      // Wants to buy 25 gold
            pay: ray(5 ether),  // Willing to pay $5 per gold
            who: address(calleeOtcDai),
            data: flashData
        });

        assertEq(vat.gem(ilk, ali),   0 ether);    // Didn't take any gold
        assertEq(vat.dai(ali),   rad(0 ether));    // Didn't pay any Dai
        assertEq(vat.gem(ilk, me),  978 ether);    // 960 + (40 - 22) returned to usr

        // Assert auction ends
        confirm_auction_ending();

    }

    function test_flash_take_exact_profit() public takeSetup calleeSetup((uint256(6 ether))) {
        // Bid so owe (= 25 * 5 = 125 RAD) > tab (= 110 RAD), so auction Will only give 22 gold

        // Maker otc has 1000 Dai and willing to buy gold at $6
        // Ali will use calleeOtcDai to flashloan with Maker Otc and pay back Clipper
        // Ali will set minimum profit to maximum that she can get with Maker Otc

        bytes memory flashData = abi.encode(address(ali),      // Address of User (where profits are sent)
                                            address(gemA),     // GemJoin adapter of collateral type
                                            uint256(22 ether)  // Minimum Dai profit [wad]
        );


        // Ali sets the pay = price, so she can get the most amount of collateral to sell for $6
        Guy(ali).take({
            id:  1,
            amt: 25 ether,      // Wants to buy 25 gold
            pay: ray(5 ether),  // Willing to pay $5 per gold
            who: address(calleeOtcDai),
            data: flashData
        });

        assertEq(vat.gem(ilk, ali),   0 ether);    // Didn't take any gold
        assertEq(dai.balanceOf(ali), 22 ether);    // ($6 - $5) * 22 = 22 Dai profit
        assertEq(vat.gem(ilk, me),  978 ether);    // 960 + (40 - 22) returned to usr

        // Assert auction ends
        confirm_auction_ending();
    }

    function test_flash_take_under_profit() public takeSetup calleeSetup((uint256(6 ether))) {
        // Bid so owe (= 25 * 5 = 125 RAD) > tab (= 110 RAD), so auction will only give 22 gold

        // Maker otc has 1000 Dai and willing to buy gold at $6
        // Ali will use calleeOtcDai to flashloan with Maker Otc and pay back Clipper
        // Ali will accept less than maximum profit

        bytes memory flashData = abi.encode(address(ali),      // Address of User (where profits are sent)
                                            address(gemA),     // GemJoin adapter of collateral type
                                            uint256(10 ether)  // Minimum Dai profit [wad]
        );


        // Ali sets the pay = price, so she can get the most amount of collateral to sell for $6
        Guy(ali).take({
            id:  1,
            amt: 25 ether,      // Wants to buy 25 gold
            pay: ray(5 ether),  // Willing to pay $5 per gold
            who: address(calleeOtcDai),
            data: flashData
        });

        assertEq(vat.gem(ilk, ali),   0 ether);    // Didn't take any gold
        assertEq(dai.balanceOf(ali), 22 ether);    // ($6 - $5) * 22 = 22 Dai profit
        assertEq(vat.gem(ilk, me),  978 ether);    // 960 + (40 - 22) returned to usr

        // Assert auction ends
        confirm_auction_ending();

    }
 /*
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
    } */
}

