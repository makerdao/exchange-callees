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
pragma experimental ABIEncoderV2;

interface GemJoinLike {
    function dec() external view returns (uint256);
    function gem() external view returns (address);
    function exit(address, uint256) external;
}

interface DaiJoinLike {
    function dai() external view returns (TokenLike);
    function join(address, uint256) external;
}

interface TokenLike {
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
    function symbol() external view returns (string memory);
}

interface CurvePoolLike {
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy)
        external returns (uint256 dy);
}

contract TUSDCurveCallee {
    CurvePoolLike   public immutable curvePool;
    DaiJoinLike     public immutable daiJoin;
    TokenLike       public immutable dai;

    uint256         public constant RAY = 10 ** 27;

    function _add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function _sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _add(x, _sub(y, 1)) / y;
    }

    constructor(
        address curvePool_,
        address daiJoin_
    ) public {
        curvePool      = CurvePoolLike(curvePool_);
        daiJoin        = DaiJoinLike(daiJoin_);
        TokenLike dai_ = DaiJoinLike(daiJoin_).dai();
        dai            = dai_;

        dai_.approve(daiJoin_, type(uint256).max);
    }

    receive() external payable {}

    function _fromWad(address gemJoin, uint256 wad) internal view returns (uint256 amt) {
        amt = wad / 10 ** (_sub(18, GemJoinLike(gemJoin).dec()));
    }

    function clipperCall(
        address sender,            // Clipper caller, pays back the loan
        uint256 owe,               // Dai amount to pay back        [rad]
        uint256 slice,             // Gem amount received           [wad]
        bytes calldata data        // Extra data, see below
    ) external {
        (
            address to,            // address to send remaining DAI to
            address gemJoin,       // gemJoin adapter address
            uint256 minProfit      // minimum profit in DAI to make [wad]
        ) = abi.decode(data, (address, address, uint256));

        address gem = GemJoinLike(gemJoin).gem();

        // Convert slice to token precision
        slice = _fromWad(gemJoin, slice);

        // Exit gem to token
        GemJoinLike(gemJoin).exit(address(this), slice);

        // Calculate amount of DAI to Join (as erc20 WAD value)
        uint256 daiToJoin = _divup(owe, RAY);

        TokenLike(gem).approve(address(curvePool), slice);
        slice = curvePool.exchange_underlying({
            i:      0,     // send token id (TUSD)
            j:      1,     // receive token id (DAI)
            dx:     slice, // send `slice` amount of TUSD
            min_dy: _add(daiToJoin, minProfit)
        });

        // Although Curve will accept all gems, this check is a sanity check, just in case
        // Transfer any lingering gem to specified address
        if (TokenLike(gem).balanceOf(address(this)) > 0) {
            TokenLike(gem).transfer(to, TokenLike(gem).balanceOf(address(this)));
        }

        // Convert DAI bought to internal vat value of the msg.sender of Clipper.take
        daiJoin.join(sender, daiToJoin);

        // Transfer remaining DAI to specified address
        dai.transfer(to, dai.balanceOf(address(this)));
    }
}

