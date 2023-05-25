// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {Helpers} from "@test/lib/Helpers.sol";
import {TestExtend} from "@test/lib/TestExtend.sol";

import {UniswapV3FactoryUpgradeable, IUniswapV3Factory} from "@uni-core/UniswapV3FactoryUpgradeable.sol";
import {UniswapV3PoolUpgradeable, IUniswapV3Pool} from "@uni-core/UniswapV3PoolUpgradeable.sol";

contract UniswapV3FactoryUpgradeableTests is TestExtend {
    uint16 constant REWARD_TIER_CARDINALITY = 102;

    UniswapV3FactoryUpgradeable factory;
    UniswapV3PoolUpgradeable poolImpl;

    function setUp() external {
        poolImpl = new UniswapV3PoolUpgradeable();
        factory = new UniswapV3FactoryUpgradeable();
        factory.__UniswapV3FactoryUpgradeable_init(
            address(poolImpl),
            REWARD_TIER_CARDINALITY
        );
    }

    // UniswapV3FactoryUpgradeable#init

    function test_init_Success() external {
        assertEq(factory.owner(), address(this));
        assertEq(factory.implementation(), address(poolImpl));
        assertEq(factory.rewardTierCardinality(), REWARD_TIER_CARDINALITY);
    }

    function test_init_RevertsOnReInitialize() external {
        vm.expectRevert("Initializable: contract is already initialized");
        factory.__UniswapV3FactoryUpgradeable_init(
            address(poolImpl),
            REWARD_TIER_CARDINALITY
        );
    }

    // UpgradeableBeacon#upgradeBeaconTo

    function test_upgradeBeaconTo_RevertsForNonOwner() external {
        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        factory.upgradeBeaconTo(makeAddr("newBeaconImplementation"));
    }

    function test_upgradeBeaconTo_Success() external {
        address newBeaconImplementation = address(
            new UniswapV3PoolUpgradeable()
        );

        address preBeaconImplementation = factory.implementation();
        assertTrue(preBeaconImplementation != newBeaconImplementation);

        factory.upgradeBeaconTo(newBeaconImplementation);

        address postBeaconImplementation = factory.implementation();
        assertEq(postBeaconImplementation, newBeaconImplementation);
    }

    // UniswapV3FactoryUpgradeable#enableFeeAmount

    function test_enableFeeAmount_RevertsForNonOwner() external {
        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        factory.enableFeeAmount(500, 10);
    }

    function test_enableFeeAmount_Success() external {
        uint24 newFeeAmount = 500;
        int24 newTickSpacing = 10;

        int24 preTickSpacing = factory.feeAmountTickSpacing(newFeeAmount);
        assertTrue(preTickSpacing == 0);

        factory.enableFeeAmount(newFeeAmount, newTickSpacing);
        assertEq(factory.feeAmountTickSpacing(newFeeAmount), newTickSpacing);
    }
}
