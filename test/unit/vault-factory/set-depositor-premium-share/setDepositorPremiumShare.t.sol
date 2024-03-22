// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract setDepositorPremiumShare_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint256 constant MAX_DEPOSITOR_PREMIUM_SHARE = 1 ether;

    uint256 newDepositorPremiumShare = 0.4 ether;

    event NewDepositorPremiumShare(uint256 depositorPremiumShare);

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        vaultFactory.setDepositorPremiumShare(newDepositorPremiumShare);
    }

    modifier whenTheCallerIsTheOwner() {
        switchPrank(users.owner);
        _;
    }

    function test_RevertWhen_TheDepositorPremiumShareGreaterThanTheMaxLimit()
        external
        whenTheCallerIsTheOwner
    {
        vm.expectRevert(
            INFTXVaultFactoryV3.DepositorPremiumShareExceedsLimit.selector
        );

        newDepositorPremiumShare = MAX_DEPOSITOR_PREMIUM_SHARE + 1;

        vaultFactory.setDepositorPremiumShare(newDepositorPremiumShare);
    }

    function test_WhenTheDepositorPremiumShareIsLessThanOrEqualToTheMaxLimit()
        external
        whenTheCallerIsTheOwner
    {
        uint256 preDepositorPremiumShare = vaultFactory.depositorPremiumShare();
        assertTrue(preDepositorPremiumShare != newDepositorPremiumShare);

        // it should emit {NewDepositorPremiumShare} event
        vm.expectEmit(false, false, false, true);
        emit NewDepositorPremiumShare(newDepositorPremiumShare);
        vaultFactory.setDepositorPremiumShare(newDepositorPremiumShare);

        // it should set the depositor premium share
        assertEq(
            vaultFactory.depositorPremiumShare(),
            newDepositorPremiumShare
        );
    }
}
