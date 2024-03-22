// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract setEligibilityManager_Unit_Test is NFTXVaultFactory_Unit_Test {
    address newEligibilityManager;

    event NewEligibilityManager(address oldEligManager, address newEligManager);

    function setUp() public virtual override {
        super.setUp();

        newEligibilityManager = makeAddr("newEligibilityManager");
    }

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        vaultFactory.setEligibilityManager(newEligibilityManager);
    }

    function test_WhenTheCallerIsTheOwner() external {
        switchPrank(users.owner);

        address preEligibilityManager = vaultFactory.eligibilityManager();
        assertTrue(preEligibilityManager != newEligibilityManager);

        // it should emit {NewEligibilityManager} event
        vm.expectEmit(false, false, false, true);
        emit NewEligibilityManager(
            preEligibilityManager,
            newEligibilityManager
        );
        vaultFactory.setEligibilityManager(newEligibilityManager);

        // it should set the eligibility manager
        assertEq(vaultFactory.eligibilityManager(), newEligibilityManager);
    }
}
