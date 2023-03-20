// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {UniswapV3Pool} from "@uni-core/UniswapV3Pool.sol";

contract UniswapV3PoolTests {
    function test_GetPoolInitCodeHash() external {
        console.logBytes32(keccak256(type(UniswapV3Pool).creationCode));
    }
}
