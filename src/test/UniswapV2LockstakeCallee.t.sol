// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.21;

import "lib/lockstake/lib/token-tests/lib/dss-test/src/DssTest.sol";
import "dss-interfaces/Interfaces.sol";

import { LockstakeDeploy } from "lib/lockstake/deploy/LockstakeDeploy.sol";
import { LockstakeInit, LockstakeConfig, LockstakeInstance } from "lib/lockstake/deploy/LockstakeInit.sol";
import { LockstakeMkr } from "lib/lockstake/src/LockstakeMkr.sol";
import { LockstakeEngine } from "lib/lockstake/src/LockstakeEngine.sol";
import { LockstakeClipper } from "lib/lockstake/src/LockstakeClipper.sol";
import { LockstakeUrn } from "lib/lockstake/src/LockstakeUrn.sol";
import { VoteDelegateFactoryMock, VoteDelegateMock } from "lib/lockstake/test/mocks/VoteDelegateMock.sol";
import { GemMock } from "lib/lockstake/test/mocks/GemMock.sol";
import { NstMock } from "lib/lockstake/test/mocks/NstMock.sol";
import { NstJoinMock } from "lib/lockstake/test/mocks/NstJoinMock.sol";
import { StakingRewardsMock } from "lib/lockstake/test/mocks/StakingRewardsMock.sol";
import { MkrNgtMock } from "lib/lockstake/test/mocks/MkrNgtMock.sol";
import { UniswapV2LockstakeCallee, TokenLike } from "src/UniswapV2LockstakeCallee.sol";

interface MkrAuthorityLike {
    function rely(address) external;
}

contract MockUniswapRouter02 is DssTest {
    uint256 fixedPrice;

    constructor(uint256 price_) {
        fixedPrice = price_;
    }

    // Hardcoded to simulate fixed price Uniswap
    /* uniRouter02.swapExactTokensForTokens(gemAmt, daiToJoin + minProfit, path, address(this), block.timestamp); */
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts) {
        to; deadline; // silence warning
        uint buyAmt = amountIn * fixedPrice;
        require(amountOutMin <= buyAmt, "Minimum Fill not reached");

        uint256 initialInBalance = DSTokenAbstract(path[0]).balanceOf(address(this));
        DSTokenAbstract(path[0]).transferFrom(msg.sender, address(this), amountIn);
        assertEq(DSTokenAbstract(path[0]).balanceOf(address(this)), initialInBalance + amountIn);

        uint256 initialOutBalance = DSTokenAbstract(path[path.length - 1]).balanceOf(msg.sender);
        GodMode.setBalance(path[path.length - 1], msg.sender, initialOutBalance + buyAmt);
        assertEq(DSTokenAbstract(path[path.length - 1]).balanceOf(msg.sender), initialOutBalance + buyAmt);

        amounts = new uint[](2);
        amounts[0] = amountIn;
        amounts[1] = buyAmt;
    }

}

contract UniswapV2LockstakeCalleeTest is DssTest {
    using stdStorage for StdStorage;

    DssInstance             dss;
    address                 pauseProxy;
    DSTokenAbstract         dai;
    DSTokenAbstract         mkr;
    LockstakeMkr            lsmkr;
    LockstakeEngine         engine;
    LockstakeClipper        clip;
    address                 calc;
    MedianAbstract          pip;
    VoteDelegateFactoryMock voteDelegateFactory;
    NstMock                 nst;
    NstJoinMock             nstJoin;
    GemMock                 rTok;
    StakingRewardsMock      farm;
    StakingRewardsMock      farm2;
    MkrNgtMock              mkrNgt;
    GemMock                 ngt;
    bytes32                 ilk = "LSE";
    address                 voter;
    address                 voteDelegate;

    LockstakeConfig     cfg;

    uint256             prevLine;
    
    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    MockUniswapRouter02      uniRouter02;
    uint256                  uniV2Price = 1;
    address[]                uniV2Path = new address[](2);
    UniswapV2LockstakeCallee callee;

    event OnKick(address indexed urn, uint256 wad);
    event OnTake(address indexed urn, address indexed who, uint256 wad);
    event OnRemove(address indexed urn, uint256 sold, uint256 burn, uint256 refund);

    // Match https://github.com/makerdao/lockstake/blob/735e1e85ca706534a77d8e1582df0d3248cbd2b6/test/LockstakeEngine.t.sol#L87-L177
    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss = MCD.loadFromChainlog(LOG);

        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
        pip = MedianAbstract(dss.chainlog.getAddress("PIP_MKR"));
        dai = DSTokenAbstract(dss.chainlog.getAddress("MCD_DAI"));
        mkr = DSTokenAbstract(dss.chainlog.getAddress("MCD_GOV"));
        nst = new NstMock();
        nstJoin = new NstJoinMock(address(dss.vat), address(nst));
        rTok = new GemMock(0);
        ngt = new GemMock(0);
        mkrNgt = new MkrNgtMock(address(mkr), address(ngt), 24_000);
        vm.startPrank(pauseProxy);
        MkrAuthorityLike(mkr.authority()).rely(address(mkrNgt));
        vm.stopPrank();

        voteDelegateFactory = new VoteDelegateFactoryMock(address(mkr));
        voter = address(123);
        vm.prank(voter); voteDelegate = voteDelegateFactory.create();

        vm.prank(pauseProxy); pip.kiss(address(this));
        vm.store(address(pip), bytes32(uint256(1)), bytes32(uint256(1_500 * 10**18)));

        LockstakeInstance memory instance = LockstakeDeploy.deployLockstake(
            address(this),
            pauseProxy,
            address(voteDelegateFactory),
            address(nstJoin),
            ilk,
            15 * WAD / 100,
            address(mkrNgt),
            bytes4(abi.encodeWithSignature("newLinearDecrease(address)"))
        );

        engine = LockstakeEngine(instance.engine);
        clip = LockstakeClipper(instance.clipper);
        calc = instance.clipperCalc;
        lsmkr = LockstakeMkr(instance.lsmkr);
        farm = new StakingRewardsMock(address(rTok), address(lsmkr));
        farm2 = new StakingRewardsMock(address(rTok), address(lsmkr));

        address[] memory farms = new address[](2);
        farms[0] = address(farm);
        farms[1] = address(farm2);

        cfg = LockstakeConfig({
            ilk: ilk,
            voteDelegateFactory: address(voteDelegateFactory),
            nstJoin: address(nstJoin),
            nst: address(nstJoin.nst()),
            mkr: address(mkr),
            mkrNgt: address(mkrNgt),
            ngt: address(ngt),
            farms: farms,
            fee: 15 * WAD / 100,
            maxLine: 10_000_000 * 10**45,
            gap: 1_000_000 * 10**45,
            ttl: 1 days,
            dust: 50,
            duty: 100000001 * 10**27 / 100000000,
            mat: 3 * 10**27,
            buf: 1.25 * 10**27, // 25% Initial price buffer
            tail: 3600, // 1 hour before reset
            cusp: 0.2 * 10**27, // 80% drop before reset
            chip: 2 * WAD / 100,
            tip: 3,
            stopped: 0,
            chop: 1 ether,
            hole: 10_000 * 10**45,
            tau: 100,
            cut: 0,
            step: 0,
            lineMom: true,
            tolerance: 0.5 * 10**27,
            name: "LOCKSTAKE",
            symbol: "LMKR"
        });

        prevLine = dss.vat.Line();

        vm.startPrank(pauseProxy);
        LockstakeInit.initLockstake(dss, instance, cfg);
        vm.stopPrank();

        deal(address(mkr), address(this), 100_000 * 10**18, true);
        deal(address(ngt), address(this), 100_000 * 24_000 * 10**18, true);

        // Add some existing DAI assigned to nstJoin to avoid a particular error
        stdstore.target(address(dss.vat)).sig("dai(address)").with_key(address(nstJoin)).depth(0).checked_write(100_000 * RAD);
    }

    function setUpCallee(address join) internal {
        // Setup mock of the uniswap router
        uniRouter02 = new MockUniswapRouter02(uniV2Price);

        // Deploy callee contract
        callee = new UniswapV2LockstakeCallee(address(uniRouter02), join, address(mkrNgt));
    }

    function _ink(bytes32 ilk_, address urn) internal view returns (uint256 ink) {
        (ink,) = dss.vat.urns(ilk_, urn);
    }

    function _art(bytes32 ilk_, address urn) internal view returns (uint256 art) {
        (, art) = dss.vat.urns(ilk_, urn);
    }

    // Match https://github.com/makerdao/lockstake/blob/735e1e85ca706534a77d8e1582df0d3248cbd2b6/test/LockstakeEngine.t.sol#L962-L991
    function _urnSetUp(bool withDelegate, bool withStaking) internal returns (address urn) {
        urn = engine.open(0);
        if (withDelegate) {
            engine.selectVoteDelegate(urn, voteDelegate);
        }
        if (withStaking) {
            engine.selectFarm(urn, address(farm), 0);
        }
        mkr.approve(address(engine), 100_000 * 10**18);
        engine.lock(urn, 100_000 * 10**18, 5);
        engine.draw(urn, address(this), 2_000 * 10**18);
        assertEq(_ink(ilk, urn), 100_000 * 10**18);
        assertEq(_art(ilk, urn), 2_000 * 10**18);

        if (withDelegate) {
            assertEq(engine.urnVoteDelegates(urn), voteDelegate);
            assertEq(mkr.balanceOf(voteDelegate), 100_000 * 10**18);
            assertEq(mkr.balanceOf(address(engine)), 0);
        } else {
            assertEq(engine.urnVoteDelegates(urn), address(0));
            assertEq(mkr.balanceOf(address(engine)), 100_000 * 10**18);
        }
        if (withStaking) {
            assertEq(lsmkr.balanceOf(address(urn)), 0);
            assertEq(lsmkr.balanceOf(address(farm)), 100_000 * 10**18);
            assertEq(farm.balanceOf(address(urn)), 100_000 * 10**18);
        } else {
            assertEq(lsmkr.balanceOf(address(urn)), 100_000 * 10**18);
        }
    }

    // Match https://github.com/makerdao/lockstake/blob/735e1e85ca706534a77d8e1582df0d3248cbd2b6/test/LockstakeEngine.t.sol#L993-L1005
    function _forceLiquidation(address urn) internal returns (uint256 id) {
        vm.store(address(pip), bytes32(uint256(1)), bytes32(uint256(0.05 * 10**18))); // Force liquidation
        dss.spotter.poke(ilk);
        assertEq(clip.kicks(), 0);
        assertEq(engine.urnAuctions(urn), 0);
        (,, uint256 hole,) = dss.dog.ilks(ilk);
        uint256 kicked = hole < 2_000 * 10**45 ? 100_000 * 10**18 * hole / (2_000 * 10**45) : 100_000 * 10**18;
        vm.expectEmit(true, true, true, true);
        emit OnKick(urn, kicked);
        id = dss.dog.bark(ilk, address(urn), address(this));
        assertEq(clip.kicks(), 1);
        assertEq(engine.urnAuctions(urn), 1);
    }

    // Based on the `_testOnTake` https://github.com/makerdao/lockstake/blob/735e1e85ca706534a77d8e1582df0d3248cbd2b6/test/LockstakeEngine.t.sol#L1104-L1202
    function _testCalleeTake(bool withDelegate, bool withStaking, address[] memory path, uint256 exchangeRate) internal {
        // Setup urn and force its liquidation
        address urn = _urnSetUp(withDelegate, withStaking);
        uint256 id = _forceLiquidation(urn);

        // Determine destination token
        TokenLike dst = TokenLike(path[path.length - 1]);

        // Setup buyer
        address buyer1 = address(111);
        vm.prank(buyer1); dss.vat.hope(address(clip));
        assertEq(mkr.balanceOf(buyer1), 0, 'unexpected-initial-buyer1-mkr-balance');
        assertEq(dst.balanceOf(buyer1), 0, 'unexpected-initial-buyer1-dst-balance');

        // Partial profit
        uint256 expectedProfit = (20_000 * 10**18) * exchangeRate - 20_000 * pip.read() * clip.buf() / RAY;

        // Expect revert if minimumDaiProfit set too high
        bytes memory flashData = abi.encode(
            address(buyer1),    // Address of the user (where profits are sent)
            expectedProfit + 1, // Minimum DAI/NST profit [wad]
            path                // Uniswap v2 path
        );
        vm.expectRevert("Minimum Fill not reached");
        vm.prank(buyer1); clip.take(
            id,                 // Auction id
            20_000 * 10**18,    // Upper limit on amount of collateral to buy  [wad]
            type(uint256).max,  // Maximum acceptable price (DAI / collateral) [ray]
            address(callee),    // Receiver of collateral and external call address
            flashData           // Data to pass in external call; if length 0, no call is done
        );

        // Partially take auction with callee
        flashData = abi.encode(
            address(buyer1),   // Address of the user (where profits are sent)
            expectedProfit,    // Minimum DAI/NST profit [wad]
            path               // Uniswap v2 path
        );
        vm.prank(buyer1); clip.take(
            id,                // Auction id
            20_000 * 10**18,   // Upper limit on amount of collateral to buy  [wad]
            type(uint256).max, // Maximum acceptable price (DAI / collateral) [ray]
            address(callee),   // Receiver of collateral and external call address
            flashData          // Data to pass in external call; if length 0, no call is done
        );
        assertEq(mkr.balanceOf(address(callee)), 0, "invalid-callee-mkr-balance");
        assertEq(dst.balanceOf(address(callee)), 0, "invalid-callee-dst-balance");
        assertEq(mkr.balanceOf(buyer1), 0, "invalid-final-buyer2-mkr-balance");
        assertEq(dst.balanceOf(buyer1), expectedProfit, "invalid-final-buyer2-dst-balance");

        // Setup different buyer to take the rest of the auction
        address buyer2 = address(222);
        vm.prank(buyer2); dss.vat.hope(address(clip));
        assertEq(mkr.balanceOf(buyer2), 0, "unexpected-initial-buyer1-mkr-balance");
        assertEq(dst.balanceOf(buyer2), 0, "unexpected-initial-buyer1-dst-balance");
        address profitAddress = address(333);

        // Take the rest of the auction with callee
        expectedProfit = (12_000 * 10**18) * exchangeRate - 12_000 * pip.read() * clip.buf() / RAY;
        flashData = abi.encode(
            address(profitAddress), // Address of the user (where profits are sent)
            expectedProfit,      // Minimum dai profit [wad]
            path                    // Uniswap v2 path
        );
        vm.prank(buyer2); clip.take(
            id,                // Auction id
            type(uint256).max, // Upper limit on amount of collateral to buy  [wad]
            type(uint256).max, // Maximum acceptable price (DAI / collateral) [ray]
            address(callee),   // Receiver of collateral and external call address
            flashData          // Data to pass in external call; if length 0, no call is done
        );
        assertEq(mkr.balanceOf(address(callee)), 0, "invalid-callee-mkr-balance");
        assertEq(dst.balanceOf(address(callee)), 0, "invalid-callee-dst-balance");
        assertEq(mkr.balanceOf(buyer2), 0, "invalid-final-buyer2-mkr-balance");
        assertEq(dst.balanceOf(profitAddress), expectedProfit, "invalid-final-profit");
    }

    // --- Callee tests using MKR/DAI path ---

    function testCalleeTakeNoWithStakingNoDelegateMkrDai() public {
        setUpCallee(dss.chainlog.getAddress("MCD_JOIN_DAI"));
        uniV2Path[0] = address(mkr);
        uniV2Path[1] = address(dai);
        _testCalleeTake(false, false, uniV2Path, uniV2Price);
    }

    function testCalleeTakeNoWithStakingWithDelegateMkrDai() public {
        setUpCallee(dss.chainlog.getAddress("MCD_JOIN_DAI"));
        uniV2Path[0] = address(mkr);
        uniV2Path[1] = address(dai);
        _testCalleeTake(true, false, uniV2Path, uniV2Price);
    }

    function testCalleeTakeWithStakingNoDelegateMkrDai() public {
        setUpCallee(dss.chainlog.getAddress("MCD_JOIN_DAI"));
        uniV2Path[0] = address(mkr);
        uniV2Path[1] = address(dai);
        _testCalleeTake(false, true, uniV2Path, uniV2Price);
    }

    function testCalleeTakeWithStakingWithDelegateMkrDai() public {
        setUpCallee(dss.chainlog.getAddress("MCD_JOIN_DAI"));
        uniV2Path[0] = address(mkr);
        uniV2Path[1] = address(dai);
        _testCalleeTake(true, true, uniV2Path, uniV2Price);
    }

    // --- Callee tests using MKR/NST path ---

    function testCalleeTakeNoWithStakingNoDelegateMkrNst() public {
        setUpCallee(address(nstJoin));
        uniV2Path[0] = address(mkr);
        uniV2Path[1] = address(nst);
        _testCalleeTake(false, false, uniV2Path, uniV2Price);
    }

    function testCalleeTakeNoWithStakingWithDelegateMkrNst() public {
        setUpCallee(address(nstJoin));
        uniV2Path[0] = address(mkr);
        uniV2Path[1] = address(nst);
        _testCalleeTake(true, false, uniV2Path, uniV2Price);
    }

    function testCalleeTakeWithStakingNoDelegateMkrNst() public {
        setUpCallee(address(nstJoin));
        uniV2Path[0] = address(mkr);
        uniV2Path[1] = address(nst);
        _testCalleeTake(false, true, uniV2Path, uniV2Price);
    }

    function testCalleeTakeWithStakingWithDelegateMkrNst() public {
        setUpCallee(address(nstJoin));
        uniV2Path[0] = address(mkr);
        uniV2Path[1] = address(nst);
        _testCalleeTake(true, true, uniV2Path, uniV2Price);
    }

    // --- Callee tests using NGT/NST path ---

    function testCalleeTakeNoWithStakingNoDelegateNgtDai() public {
        setUpCallee(address(nstJoin));
        uniV2Path[0] = address(ngt);
        uniV2Path[1] = address(nst);
        _testCalleeTake(false, false, uniV2Path, uniV2Price * mkrNgt.rate());
    }

    function testCalleeTakeNoWithStakingWithDelegateNgtDai() public {
        setUpCallee(address(nstJoin));
        uniV2Path[0] = address(ngt);
        uniV2Path[1] = address(nst);
        _testCalleeTake(true, false, uniV2Path, uniV2Price * mkrNgt.rate());
    }

    function testCalleeTakeWithStakingNoDelegateNgtDai() public {
        setUpCallee(address(nstJoin));
        uniV2Path[0] = address(ngt);
        uniV2Path[1] = address(nst);
        _testCalleeTake(false, true, uniV2Path, uniV2Price * mkrNgt.rate());
    }

    function testCalleeTakeWithStakingWithDelegateNgtDai() public {
        setUpCallee(address(nstJoin));
        uniV2Path[0] = address(ngt);
        uniV2Path[1] = address(nst);
        _testCalleeTake(true, true, uniV2Path, uniV2Price * mkrNgt.rate());
    }
}
