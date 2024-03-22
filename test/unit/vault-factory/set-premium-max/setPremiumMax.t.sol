// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract setPremiumMax_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint256 newPremiumMax = 10 ether;

    event NewPremiumMax(uint256 premiumMax);

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        vaultFactory.setPremiumMax(newPremiumMax);
    }

    function test_WhenTheCallerIsTheOwner() external {
        switchPrank(users.owner);

        uint256 prePremiumMax = vaultFactory.premiumMax();
        assertTrue(prePremiumMax != newPremiumMax);

        // it should emit {NewPremiumMax} event
        vm.expectEmit(false, false, false, true);
        emit NewPremiumMax(newPremiumMax);
        vaultFactory.setPremiumMax(newPremiumMax);

        // it should set the premium max
        assertEq(vaultFactory.premiumMax(), newPremiumMax);
    }
}
