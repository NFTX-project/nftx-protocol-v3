// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract setTwapInterval_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint32 newTwapInterval = 60 minutes;

    event NewTwapInterval(uint32 twapInterval);

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        vaultFactory.setTwapInterval(newTwapInterval);
    }

    modifier whenTheCallerIsTheOwner() {
        switchPrank(users.owner);
        _;
    }

    function test_RevertWhen_TheTwapIntervalIsZero()
        external
        whenTheCallerIsTheOwner
    {
        vm.expectRevert(INFTXVaultFactoryV3.ZeroTwapInterval.selector);

        newTwapInterval = 0;

        vaultFactory.setTwapInterval(newTwapInterval);
    }

    function test_WhenTheTwapIntervalIsGreaterThanZero()
        external
        whenTheCallerIsTheOwner
    {
        uint32 preTwapInterval = vaultFactory.twapInterval();
        assertTrue(preTwapInterval != newTwapInterval);

        // it should emit {NewTwapInterval} event
        vm.expectEmit(false, false, false, true);
        emit NewTwapInterval(newTwapInterval);
        vaultFactory.setTwapInterval(newTwapInterval);

        // it should set the twap interval
        assertEq(vaultFactory.twapInterval(), newTwapInterval);
    }
}
