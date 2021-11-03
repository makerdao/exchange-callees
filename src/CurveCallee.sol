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
    function gem() external view returns (TokenLike);
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
}

interface CharterManagerLike {
    function exit(address crop, address usr, uint256 val) external;
}

interface WstEthLike {
    function unwrap(uint256 _wstEthAmount) returns (uint256);
}

interface CurveLike {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy)
        external returns (uint256 dy);
}

interface UniV3Like {
    
    struct Params {
        bytes   path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(UniV3Like.Params calldata params)
        external payable returns (uint256 amountOut);
}

contract UniV3Callee {
    WstEthLike              public wstEth;
    CurveLike               public curve;
    UniV3Like               public uniV3;
    DaiJoinLike             public daiJoin;
    TokenLike               public dai;

    uint256                 public constant RAY = 10 ** 27;

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(x, sub(y, 1)) / y;
    }

    constructor(
        address wstEthAddr_,
        address curveAddr_,
        address uniV3Addr_,
        address daiJoin_
    ) public {
        wstEth = WstEth(wstEthAddr_
        uniV3 = UniV3Like(uniV3Addr_);
        daiJoin = DaiJoinLike(daiJoin_);
        dai = daiJoin.dai();

        dai.approve(daiJoin_, uint256(-1));
    }

    function _fromWad(address gemJoin, uint256 wad) internal view returns (uint256 amt) {
        amt = wad / 10 ** (sub(18, GemJoinLike(gemJoin).dec()));
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
            uint256 minProfit,     // minimum profit in DAI to make [wad]
            bytes memory path,     // packed encoding of (address, fee, address [, fee, address…])
            address charterManager // pass address(0) if no manager
        ) = abi.decode(data, (address, address, uint256, bytes, address));

        // Convert slice to token precision
        slice = _fromWad(gemJoin, slice);

        // Exit gem to token
        if(charterManager != address(0)) {
            CharterManagerLike(charterManager).exit(gemJoin, address(this), slice);
        } else {
            GemJoinLike(gemJoin).exit(address(this), slice);
        }

        // Approve uniV3 to take gem
        TokenLike gem = GemJoinLike(gemJoin).gem();
        gem.approve(address(uniV3), slice);

        // Calculate amount of DAI to Join (as erc20 WAD value)
        uint256 daiToJoin = divup(owe, RAY);

        // Do operation and get dai amount bought (checking the profit is achieved)
        UniV3Like.Params memory params = UniV3Like.Params({
            path:             path,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         slice,
            amountOutMinimum: add(daiToJoin, minProfit)
        });
        uniV3.exactInput(params);

        // Although Uniswap will accept all gems, this check is a sanity check, just in case
        // Transfer any lingering gem to specified address
        if (gem.balanceOf(address(this)) > 0) {
            gem.transfer(to, gem.balanceOf(address(this)));
        }

        // Convert DAI bought to internal vat value of the msg.sender of Clipper.take
        daiJoin.join(sender, daiToJoin);

        // Transfer remaining DAI to specified address
        dai.transfer(to, dai.balanceOf(address(this)));
    }
}

