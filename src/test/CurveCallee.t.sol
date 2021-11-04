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

pragma solidity ^0.6.12;

import "ds-test/test.sol";
import { CurveCallee } from "../CurveCallee.sol";

interface Hevm {
    function store(address c, bytes32 loc, bytes32 val) external;
}

contract CurveCalleeTest is DSTest {

    Hevm hevm;
    address constant wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    
    function setUp() {
    
    }

}
