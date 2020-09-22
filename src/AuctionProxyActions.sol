// Copyright (C) 2020 Maker Ecosystem Growth Holdings, INC.
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

pragma solidity >=0.5.12;

interface ClipperLike {
    function take(uint256, uint256, uint256, address, bytes calldata) external;
}

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// WARNING: These functions meant to be used as a a library for a DSProxy.
//          Some are unsafe if you call them directly.
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


contract AuctionProxyActions {

    function execute(
        address clipper,         // Dutch Auction Contract for particular collateral type
        address exchangeCallee,  // Exchange callee contract where the collateral is sold
        address gemJoin,         // GemJoin adapter of collateral type
        uint256 id,              // Auction ID
        uint256 collateralAmt,   // Amount of collateral to be sold  [wad]
        uint256 maxPrice,        // Maximum bid price in DAI         [ray]
        uint256 minProfit        // Minimum profit in DAI            [wad]
    ) public {

        // Construct a flashloan where the exchangeCallee contract
        // is given collateral to be sold
        bytes memory flashData = abi.encode(msg.sender,  // Address of User (where profits are sent)
                                            gemJoin,     // GemJoin adapter of collateral type
                                            minProfit    // Minimum Dai profit [wad]
        );

        // Participate in auction with flashloan
        ClipperLike(clipper).take(id,
                                  collateralAmt,
                                  maxPrice,
                                  exchangeCallee,
                                  flashData
        );

    }

}
