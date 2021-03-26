// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Maker Ecosystem Growth Holdings, INC.
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

import "ds-test/test.sol";

interface UniV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint[] memory amounts);
}

interface Weth {
    function deposit() external payable;
    function transfer(address guy, uint256 wad) external;
    function approve(address guy, uint256 wad) external;
    function balanceOf(address guy) external returns (uint256);
}

interface Dai {
    function balanceOf(address guy) external returns (uint256);
}

contract Constants {
    uint256 WAD = 1E18;
    address uniV2Router02Address = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address daiAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
}

contract Guy is Constants {
    UniV2Router02 uniRouter;
    Weth weth;
    constructor () public {
        uniRouter = UniV2Router02(uniV2Router02Address);
        weth = Weth(wethAddress);
        weth.approve(address(uniRouter), type(uint256).max);
    }
    function swapExactTokensForTokens (
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        uniRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }
}

contract SimulationTests is DSTest, Constants {
    Guy ali;
    Weth weth;
    Dai dai;
    function setUp() public {
        ali = new Guy();
        weth = Weth(wethAddress);
        weth.deposit{value: 2 * WAD}();
        weth.transfer(address(ali), 2 * WAD);
        dai = Dai(daiAddress);
    }

    function testSwap() public {
        uint256 amountIn = 1 * WAD;
        uint256 amountOutMin = 1500 * WAD;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(dai);
        address to = address(ali);
        uint256 deadline = block.timestamp;
        uint256 wethPre = weth.balanceOf(address(ali));
        uint256 daiPre = dai.balanceOf(address(ali));
        ali.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
        uint256 wethPost = weth.balanceOf(address(ali));
        uint256 daiPost = dai.balanceOf(address(ali));
        assertEq(wethPost, wethPre - amountIn);
        assertGe(daiPost, daiPre + amountOutMin);
    }
}
