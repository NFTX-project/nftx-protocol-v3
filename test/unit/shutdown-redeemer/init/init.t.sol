// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ShutdownRedeemerUpgradeable} from "@src/ShutdownRedeemerUpgradeable.sol";
import {INFTXVaultFactoryV2} from "@src/v2/interfaces/INFTXVaultFactoryV2.sol";

import {ShutdownRedeemer_Unit_Test} from "../ShutdownRedeemer.t.sol";

contract ShutdownRedeemer_Init_Unit_Test is ShutdownRedeemer_Unit_Test {
    function setUp() public virtual override {
        super.setUp();

        // this contract should be initialized by the deployer(owner)
        switchPrank(users.owner);
        // use uninitialized ShutdownRedeemer for these tests
        shutdownRedeemer = new ShutdownRedeemerUpgradeable(
            INFTXVaultFactoryV2(address(vaultFactory))
        );
    }

    function test_RevertGiven_TheContractIsInitialized() external {
        // initialize the contract
        shutdownRedeemer.__ShutdownRedeemer_init();

        // it should revert, if initialized again
        vm.expectRevert(REVERT_ALREADY_INITIALIZED);
        shutdownRedeemer.__ShutdownRedeemer_init();
    }

    function test_GivenTheContractIsNotInitialized() external {
        shutdownRedeemer.__ShutdownRedeemer_init();

        // it should set the owner
        assertEq(shutdownRedeemer.owner(), users.owner);
        // it should have the vault factory already set
        assertEq(
            address(shutdownRedeemer.V2VaultFactory()),
            address(vaultFactory)
        );
    }
}
