pragma solidity 0.5.12;

import "ds-math/math.sol";

contract OtcLike {
    function sellAllAmount(address, uint, address, uint) public returns (uint);
    function buyAllAmount(address, uint, address, uint) public returns (uint);
    function getPayAmount(address, address, uint) public view returns (uint);
}

contract TokenLike {
    function balanceOf(address) public returns (uint);
    function allowance(address, address) public returns (uint);
    function approve(address, uint) public;
    function transfer(address,uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
    function deposit() public payable;
    function withdraw(uint) public;
}

contract OasisDirectProxy is DSMath {
    function withdrawAndSend(
        address wethToken,
        uint wethAmt
    ) internal {
        TokenLike(wethToken).withdraw(wethAmt);
        (bool ok,) = msg.sender.call.value(wethAmt)("");
        require(ok, "");
    }

    function sellAllAmount(
        address otc,
        address payToken,
        uint payAmt,
        address buyToken,
        uint minBuyAmt
    ) public returns (uint buyAmt) {
        require(TokenLike(payToken).transferFrom(msg.sender, address(this), payAmt), "");
        if (TokenLike(payToken).allowance(address(this), otc) < payAmt) {
            TokenLike(payToken).approve(otc, uint(-1));
        }
        buyAmt = OtcLike(otc).sellAllAmount(payToken, payAmt, buyToken, minBuyAmt);
        require(TokenLike(buyToken).transfer(msg.sender, buyAmt), "");
    }

    function sellAllAmountPayEth(
        address otc,
        address wethToken,
        address buyToken,
        uint minBuyAmt
    ) public payable returns (uint buyAmt) {
        TokenLike(wethToken).deposit.value(msg.value)();
        if (TokenLike(wethToken).allowance(address(this), otc) < msg.value) {
            TokenLike(wethToken).approve(otc, uint(-1));
        }
        buyAmt = OtcLike(otc).sellAllAmount(wethToken, msg.value, buyToken, minBuyAmt);
        require(TokenLike(buyToken).transfer(msg.sender, buyAmt), "");
    }

    function sellAllAmountBuyEth(
        address otc,
        address payToken,
        uint payAmt,
        address wethToken,
        uint minBuyAmt
    ) public returns (uint wethAmt) {
        require(TokenLike(payToken).transferFrom(msg.sender, address(this), payAmt), "");
        if (TokenLike(payToken).allowance(address(this), otc) < payAmt) {
            TokenLike(payToken).approve(otc, uint(-1));
        }
        wethAmt = OtcLike(otc).sellAllAmount(payToken, payAmt, wethToken, minBuyAmt);
        withdrawAndSend(wethToken, wethAmt);
    }

    function buyAllAmount(
        address otc,
        address buyToken,
        uint buyAmt,
        address payToken,
        uint maxPayAmt
    ) public returns (uint payAmt) {
        uint payAmtNow = OtcLike(otc).getPayAmount(payToken, buyToken, buyAmt);
        require(payAmtNow <= maxPayAmt, "");
        require(TokenLike(payToken).transferFrom(msg.sender, address(this), payAmtNow), "");
        if (TokenLike(payToken).allowance(address(this), otc) < payAmtNow) {
            TokenLike(payToken).approve(otc, uint(-1));
        }
        payAmt = OtcLike(otc).buyAllAmount(buyToken, buyAmt, payToken, payAmtNow);
        // To avoid rounding issues we check the minimum value:
        require(TokenLike(buyToken).transfer(msg.sender, min(buyAmt, TokenLike(buyToken).balanceOf(address(this)))), "");
    }

    function buyAllAmountPayEth(
        address otc,
        address buyToken,
        uint buyAmt,
        address wethToken
    ) public payable returns (uint wethAmt) {
        // In this case user needs to send more ETH than a estimated value, then contract will send back the rest
        TokenLike(wethToken).deposit.value(msg.value)();
        if (TokenLike(wethToken).allowance(address(this), otc) < msg.value) {
            TokenLike(wethToken).approve(otc, uint(-1));
        }
        wethAmt = OtcLike(otc).buyAllAmount(buyToken, buyAmt, wethToken, msg.value);
        // To avoid rounding issues we check the minimum value:
        require(TokenLike(buyToken).transfer(msg.sender, min(buyAmt, TokenLike(buyToken).balanceOf(address(this)))), "");
        withdrawAndSend(wethToken, sub(msg.value, wethAmt));
    }

    function buyAllAmountBuyEth(
        address otc,
        address wethToken,
        uint wethAmt,
        address payToken,
        uint maxPayAmt
    ) public returns (uint payAmt) {
        uint payAmtNow = OtcLike(otc).getPayAmount(payToken, wethToken, wethAmt);
        require(payAmtNow <= maxPayAmt, "");
        require(TokenLike(payToken).transferFrom(msg.sender, address(this), payAmtNow), "");
        if (TokenLike(payToken).allowance(address(this), otc) < payAmtNow) {
            TokenLike(payToken).approve(otc, uint(-1));
        }
        payAmt = OtcLike(otc).buyAllAmount(wethToken, wethAmt, payToken, payAmtNow);
        withdrawAndSend(wethToken, wethAmt);
    }

    function() external payable {}
}
