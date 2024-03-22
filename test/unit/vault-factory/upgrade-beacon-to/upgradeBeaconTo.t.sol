// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {UpgradeableBeacon} from "@src/custom/proxy/UpgradeableBeacon.sol";
import {NFTXVaultFactoryUpgradeableV3} from "@src/NFTXVaultFactoryUpgradeableV3.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract upgradeBeaconTo_Unit_Test is NFTXVaultFactory_Unit_Test {
    address newImplementation;

    event Upgraded(address indexed beaconImplementation);

    function setUp() public virtual override {
        super.setUp();

        newImplementation = makeAddr("newImplementation");
    }

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        vaultFactory.upgradeBeaconTo(newImplementation);
    }

    modifier whenTheCallerIsTheOwner() {
        switchPrank(users.owner);
        _;
    }

    function test_RevertWhen_TheImplementationIsNotAContract()
        external
        whenTheCallerIsTheOwner
    {
        vm.expectRevert(
            UpgradeableBeacon.ChildImplementationIsNotAContract.selector
        );
        vaultFactory.upgradeBeaconTo(newImplementation);
    }

    function test_WhenTheImplementationIsAContract()
        external
        whenTheCallerIsTheOwner
    {
        newImplementation = address(new NFTXVaultFactoryUpgradeableV3());

        // it should emit {Upgraded} event
        vm.expectEmit(false, false, false, true);
        emit Upgraded(newImplementation);
        vaultFactory.upgradeBeaconTo(newImplementation);

        // it should set the implementation
        assertEq(vaultFactory.implementation(), newImplementation);
    }
}
