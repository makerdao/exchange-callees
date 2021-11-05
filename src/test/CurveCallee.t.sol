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

interface Chainlog {
    function getAddress(bytes32) external returns (address);
}

interface Token {
    function approve(address, uint256) external;
}

interface Join {
    function join(address, uint256) external;
}

interface Vat {
    function ilks(bytes32)
        external returns (uint256, uint256, uint256, uint256, uint256);
    function frob(
        bytes32 i,
        address u,
        address v,
        address w,
        int dink,
        int dart
    ) external;
}

contract CurveCalleeTest is DSTest {

    address constant hevm     = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    address constant wstEth   = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant chainlog = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    uint256 constant amt      = 5e18;
    
    function setUp() public {
        Hevm(hevm).store({
            c:   wstEth,
            loc: keccak256(abi.encode(address(this), uint256(0))),
            val: bytes32(amt)
        });
        address join = Chainlog(chainlog).getAddress("MCD_JOIN_WSTETH_A");
        Token(wstEth).approve(join, amt);
        Join(join).join(address(this), amt);
        address vat = Chainlog(chainlog).getAddress("MCD_VAT");
        (, uint256 rate, uint256 spot,,) = Vat(vat).ilks("WSTETH-A");
        uint256 maxArt = amt * spot / rate;
        Vat(vat).frob({
            i:    "WSTETH-A",
            u:    address(this),
            v:    address(this),
            w:    address(this),
            dink: int(amt),
            dart: int(maxArt)
        });
    }

    function test() public {
        log_uint(TokenLike(wstEth).balanceOf(address(this)));
        address vat = Chainlog(chainlog).getAddress("MCD_VAT");
        log_uint(VatLike(vat).gem("WSTETH-A", address(this)));
        (uint256 ink, uint256 art) = VatLike(vat).urns("WSTETH-A", address(this));
        log_uint(ink);
        log_uint(art);
    }

}

interface TokenLike {
    function balanceOf(address) external returns (uint256);
}

interface VatLike {
    function gem(bytes32, address) external returns (uint256);
    function urns(bytes32, address) external returns (uint256, uint256);
}
