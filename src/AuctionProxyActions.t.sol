pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./AuctionProxyActions.sol";

contract AuctionProxyActionsTest is DSTest {
    AuctionProxyActions actions;

    function setUp() public {
        actions = new AuctionProxyActions();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
