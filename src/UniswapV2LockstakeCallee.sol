// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2020 Maker Ecosystem Growth Holdings, INC.
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

pragma solidity ^0.8.21;

interface daiJoinLike {
    function dai() external view returns (TokenLike);
    function join(address, uint256) external;
}

interface TokenLike {
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint256);
}

interface UniswapV2Router02Like {
    function swapExactTokensForTokens(uint256, uint256, address[] calldata, address, uint256) external returns (uint[] memory);
}

// Simple Callee Example to interact with MatchingMarket
// This Callee contract exists as a standalone contract
contract UniswapV2Callee {
    UniswapV2Router02Like   public uniRouter02;
    daiJoinLike             public daiJoin;
    TokenLike               public dai;
    TokenLike               public mkr;

    uint256                 public constant RAY = 10 ** 27;

    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x != 0 ? ((x - 1) / y) + 1 : 0;
    }

    function setUp(address uniRouter02_, address daiJoin_, address mkr_) internal {
        uniRouter02 = UniswapV2Router02Like(uniRouter02_);
        daiJoin = daiJoinLike(daiJoin_);
        dai = daiJoin.dai();
        mkr = TokenLike(mkr_);

        dai.approve(daiJoin_, type(uint256).max);
    }

    function _fromWad(uint256 wad) internal view returns (uint256 amt) {
        amt = wad / 10 ** (18 - mkr.decimals());
    }
}

contract UniswapV2LockstakeCallee is UniswapV2Callee {
    constructor(address uniRouter02_, address daiJoin_, address mkr_) {
        setUp(uniRouter02_, daiJoin_, mkr_);
    }

    function clipperCall(
        address sender,         // Clipper Caller and Dai deliveryaddress
        uint256 daiAmt,         // Dai amount to payback[rad]
        uint256 gemAmt,         // Gem amount received [wad]
        bytes calldata data     // Extra data needed (gemJoin)
    ) external {
        (
            address to,            // address to send remaining DAI to
            uint256 minProfit,     // minimum profit in DAI to make [wad]
            address[] memory path  // Uniswap pool path
        ) = abi.decode(data, (address, uint256, address[]));

        // Convert gem amount to token precision
        gemAmt = _fromWad(gemAmt);

        // Approve uniRouter02 to take gem
        mkr.approve(address(uniRouter02), gemAmt);

        // Calculate amount of DAI to Join (as erc20 WAD value)
        uint256 daiToJoin = divup(daiAmt, RAY);

        // Do operation and get dai amount bought (checking the profit is achieved)
        uniRouter02.swapExactTokensForTokens(
            gemAmt,
            daiToJoin + minProfit,
            path,
            address(this),
            block.timestamp
        );

        // Although Uniswap will accept all gems, this check is a sanity check, just in case
        // Transfer any lingering gem to specified address
        if (mkr.balanceOf(address(this)) > 0) {
            mkr.transfer(to, mkr.balanceOf(address(this)));
        }

        // Convert DAI bought to internal vat value of the msg.sender of Clipper.take
        daiJoin.join(sender, daiToJoin);

        // Transfer remaining DAI to specified address
        dai.transfer(to, dai.balanceOf(address(this)));
    }
}

