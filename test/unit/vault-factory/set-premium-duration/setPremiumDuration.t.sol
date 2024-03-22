// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract setPremiumDuration_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint256 newPremiumDuration = 20 hours;

    event NewPremiumDuration(uint256 premiumDuration);

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        vaultFactory.setPremiumDuration(newPremiumDuration);
    }

    function test_WhenTheCallerIsTheOwner() external {
        switchPrank(users.owner);

        uint256 prePremiumDuration = vaultFactory.premiumDuration();
        assertTrue(prePremiumDuration != newPremiumDuration);

        // it should emit {NewPremiumDuration} event
        vm.expectEmit(false, false, false, true);
        emit NewPremiumDuration(newPremiumDuration);
        vaultFactory.setPremiumDuration(newPremiumDuration);

        // it should set the premium duration
        assertEq(vaultFactory.premiumDuration(), newPremiumDuration);
    }
}
