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

pragma solidity >=0.6.12;

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";
import { Dog } from "dss/dog.sol";
import { Clipper } from "dss/clip.sol";
import { UniswapV2CalleeDai } from "../UniswapV2Callee.sol";

interface UniV2Router02Abstract {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint[] memory amounts);
}

interface WethAbstract is GemAbstract {
    function deposit() external payable;
}

contract Constants {

    // mainnet UniswapV2Router02 address
    address constant uniAddr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 constant WAD = 1E18;
    bytes32 constant ilkName = "ETH-A";

    address wethAddr;
    address daiAddr;
    address vatAddr;
    address wethJoinAddr;
    address spotterAddr;
    address daiJoinAddr;

    UniV2Router02Abstract uniRouter;
    WethAbstract weth;
    VatAbstract vat;
    GemJoinAbstract wethJoin;
    DaiAbstract dai;

    Dog dog;
    Clipper clipper;
    UniswapV2CalleeDai callee;

    function setAddresses() private {
        ChainlogHelper helper = new ChainlogHelper();
        ChainlogAbstract chainLog = helper.ABSTRACT();
        wethAddr = chainLog.getAddress("ETH");
        daiAddr = chainLog.getAddress("MCD_DAI");
        vatAddr = chainLog.getAddress("MCD_VAT");
        wethJoinAddr = chainLog.getAddress("MCD_JOIN_ETH_A");
        spotterAddr = chainLog.getAddress("MCD_SPOT");
        daiJoinAddr = chainLog.getAddress("MCD_JOIN_DAI");
    }

    function setInterfaces() private {
        uniRouter = UniV2Router02Abstract(uniAddr);
        weth = WethAbstract(wethAddr);
        vat = VatAbstract(vatAddr);
        dai = DaiAbstract(daiAddr);
        wethJoin = GemJoinAbstract(wethJoinAddr);
    }

    function deployContracts() private {
        // TODO: change dog and clipper to interface mainnet deployments when
        // available
        dog = new Dog(vatAddr);
        clipper = new Clipper(vatAddr, spotterAddr, address(dog), ilkName);
        callee = new UniswapV2CalleeDai(uniAddr, address(clipper), daiJoinAddr);
    }

    constructor () public {
        setAddresses();
        setInterfaces();
        deployContracts();
    }
}

contract Guy is Constants {

    constructor() public {
        weth.approve(uniAddr, type(uint256).max);
    }

    function swapExactTokensForTokens(
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

    function setUp() public {
        ali = new Guy();
    }

    function getWeth(uint256 value) private {
        weth.deposit{ value: value }();
        weth.transfer(address(ali), value);
    }

    function joinWeth(uint256 value) private {
        weth.deposit{ value: value }();
        weth.approve(wethJoinAddr, type(uint256).max);
        wethJoin.join(address(ali), value);
    }

    function testSwap() public {
        getWeth(2 * WAD);
        uint256 amountIn = 1 * WAD;
        uint256 amountOutMin = 1500 * WAD;
        address[] memory path = new address[](2);
        path[0] = wethAddr;
        path[1] = daiAddr;
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

    function testFlash() public {
        joinWeth(2 * WAD);
    }
}
