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

interface CharterManagerLike {
    function exit(address crop, address usr, uint256 val) external;
}
interface CurvePoolLike {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy)
        external returns (uint256 dy);
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount)
        external;
}

interface UniV3RouterLike {
    
    struct ExactInputParams {
        bytes   path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(UniV3RouterLike.ExactInputParams calldata params)
        external payable returns (uint256 amountOut);
}

contract TUSDCurveUniv3Callee {
    CurvePoolLike   public immutable curvePool;
    UniV3RouterLike public immutable uniV3Router;
    DaiJoinLike     public immutable daiJoin;
    TokenLike       public immutable dai;
    address         public immutable weth; // TODO: remove

    address public constant usdcJoin = address(0xA191e578a6736167326d05c119CE0c90849E84B7); // TODO: remove

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
        address uniV3Router_,
        address daiJoin_,
        address weth_ // TODO: remove
    ) public {
        curvePool      = CurvePoolLike(curvePool_);
        uniV3Router    = UniV3RouterLike(uniV3Router_);
        daiJoin        = DaiJoinLike(daiJoin_);
        TokenLike dai_ = DaiJoinLike(daiJoin_).dai();
        dai            = dai_;
        weth           = weth_;

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
            uint256 minProfit,     // minimum profit in DAI to make [wad]
            uint24  poolFee,       // uniswap V3 WETH-DAI pool fee
            address charterManager // pass address(0) if no manager
        ) = abi.decode(data, (address, address, uint256, uint24, address));

        address gem = GemJoinLike(gemJoin).gem();

        // Convert slice to token precision
        slice = _fromWad(gemJoin, slice);

        // Exit gem to token
        if(charterManager != address(0)) {
            CharterManagerLike(charterManager).exit(gemJoin, address(this), slice);
        } else {
            GemJoinLike(gemJoin).exit(address(this), slice);
        }

        TokenLike(gem).approve(address(curvePool), slice);
        slice = curvePool.exchange({
            i:      0,     // send token id (TUSD)
            j:      1,     // receive token id (3CRV)
            dx:     slice, // send `slice` amount of 3CRV
            min_dy: 0      // accept any amount of 3CRV (`minProfit` is checked below)
        });

        gem = address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
        CurvePoolLike curvePool2 = CurvePoolLike(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

        TokenLike(gem).approve(address(curvePool2), slice);
        curvePool2.remove_liquidity_one_coin({ //TODO: no need for slice
            _token_amount: slice,
            i:             0, // DAI
            _min_amount:   0 // TODO change to _add(daiToJoin, minProfit)
        });
        // TODO: change name! also no need for uniswapv3

        // Calculate amount of DAI to Join (as erc20 WAD value)
        uint256 daiToJoin = _divup(owe, RAY);

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

