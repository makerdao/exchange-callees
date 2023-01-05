// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2023 Dai Foundation
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

interface IAggregationExecutor {
    function callBytes(address msgSender, bytes calldata data) external payable;
}

interface OneinchRouter {
    struct SwapDescription {
        TokenLike srcToken;
        TokenLike dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    function swap(
        IAggregationExecutor executor,
        SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 spentAmount);
}

contract OneinchCallee {
    DaiJoinLike public daiJoin;
    TokenLike public dai;
    uint256 public constant RAY = 10**27;

    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _add(x, _sub(y, 1)) / y;
    }

    constructor(address daiJoinAddress) public {
        daiJoin = DaiJoinLike(daiJoinAddress);
        dai = daiJoin.dai();
        dai.approve(daiJoinAddress, 2**256 - 1);
    }

    function _fromWad(address gemJoin, uint256 wad) internal view returns (uint256 amt) {
        amt = wad / 10**(_sub(18, GemJoinLike(gemJoin).dec()));
    }

    function clipperCall(
        address sender, // Clipper caller, pays back the loan
        uint256 owe, // Dai amount to pay back          [rad]
        uint256 slice, // Gem amount received           [wad]
        bytes calldata data // Extra data, see below
    ) external {
        (
            address to, // address to send remaining DAI to
            address gemJoinAddress, // gemJoin adapter address
            uint256 minProfit, // minimum profit in DAI to make [wad]
            address router, // tx.to address received from the 1inch API
            bytes memory oneinchData // reencoded 1inch parameters
        ) = abi.decode(data, (address, address, uint256, address, bytes));

        // Convert slice to token precision
        slice = _fromWad(gemJoinAddress, slice);

        // Exit gem to token
        GemJoinLike(gemJoinAddress).exit(address(this), slice);

        // Approve 1inch to take gem
        TokenLike gem = GemJoinLike(gemJoinAddress).gem();
        gem.approve(router, slice);
        require(gem.balanceOf(address(this)) >= slice, 'gem-balance-too-low');

        // Calculate amount of DAI to Join (as erc20 WAD value)
        owe = _divup(owe, RAY);

        uint256 oweWithProfit = _add(owe, minProfit);

        OneinchRouter.SwapDescription memory swapDescription;
        { // Build initial swapDescription
            swapDescription.srcToken = gem;
            swapDescription.dstToken = dai;
            swapDescription.dstReceiver = address(this);
            swapDescription.amount = slice;
            swapDescription.minReturnAmount = oweWithProfit;
        }

        { // Execute 1inch swap
            (
                IAggregationExecutor executor,
                address srcReceiver,
                uint256 flags,
                bytes memory permit,
                bytes memory tradeData
            ) = abi.decode(oneinchData, (IAggregationExecutor, address, uint256, bytes, bytes));

            // Add missing swapDescription parameters
            swapDescription.srcReceiver = srcReceiver;
            swapDescription.flags = flags;

            // Execute
            OneinchRouter(router).swap(executor, swapDescription, permit, tradeData);
            
            // Check actual amount of dai returned
            require(dai.balanceOf(address(this)) >= oweWithProfit, '1inch-returned-too-litle-dai');
        }

        // Although 1inch will accept all gems, this check is a sanity check, just in case
        if (gem.balanceOf(address(this)) > 0) {
            // Transfer any lingering gem to specified address
            gem.transfer(to, gem.balanceOf(address(this)));
        }

        // Convert DAI bought to internal vat value of the msg.sender of Clipper.take
        daiJoin.join(sender, owe);

        // Transfer remaining DAI to specified address
        dai.transfer(to, dai.balanceOf(address(this)));
    }
}
