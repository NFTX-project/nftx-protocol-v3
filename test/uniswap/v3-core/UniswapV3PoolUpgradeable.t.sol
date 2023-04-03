// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {Helpers} from "@test/lib/Helpers.sol";
import {TestExtend} from "@test/lib/TestExtend.sol";

import {UniswapV3PoolUpgradeable, IUniswapV3Pool} from "@uni-core/UniswapV3PoolUpgradeable.sol";

contract UniswapV3PoolUpgradeableTests is TestExtend {
    UniswapV3PoolUpgradeable pool;

    address factory = makeAddr("factory");
    address token0 = makeAddr("token0");
    address token1 = makeAddr("token1");
    uint24 fee = 500;
    int24 tickSpacing = 10;

    function setUp() external {
        pool = new UniswapV3PoolUpgradeable();
        pool.__UniswapV3PoolUpgradeable_init(
            factory,
            token0,
            token1,
            fee,
            tickSpacing
        );
    }

    function test_init_Success() external {
        assertEq(pool.factory(), factory);
        assertEq(pool.token0(), token0);
        assertEq(pool.token1(), token1);
        assertEq(pool.fee(), fee);
        assertEq(pool.tickSpacing(), tickSpacing);
        assertGt(pool.maxLiquidityPerTick(), 0);
    }

    function test_init_RevertsOnReInitialize() external {
        vm.expectRevert("Initializable: contract is already initialized");
        pool.__UniswapV3PoolUpgradeable_init(
            factory,
            token0,
            token1,
            fee,
            tickSpacing
        );
    }
}
