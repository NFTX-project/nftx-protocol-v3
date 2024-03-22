// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract setFeeDistributor_Unit_Test is NFTXVaultFactory_Unit_Test {
    address newFeeDistributor;

    event NewFeeDistributor(address oldDistributor, address newDistributor);

    function setUp() public virtual override {
        super.setUp();

        newFeeDistributor = makeAddr("newFeeDistributor");
    }

    function test_WhenTheCallerIsNotTheOwner() external {
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        vaultFactory.setFeeDistributor(newFeeDistributor);
    }

    modifier whenTheCallerIsTheOwner() {
        switchPrank(users.owner);
        _;
    }

    function test_WhenTheFeeDistributorIsTheZeroAddress()
        external
        whenTheCallerIsTheOwner
    {
        vm.expectRevert(INFTXVaultFactoryV3.ZeroAddress.selector);

        newFeeDistributor = address(0);

        vaultFactory.setFeeDistributor(newFeeDistributor);
    }

    function test_WhenTheFeeDistributorIsNotTheZeroAddress()
        external
        whenTheCallerIsTheOwner
    {
        address preFeeDistributor = vaultFactory.feeDistributor();
        assertTrue(preFeeDistributor != newFeeDistributor);

        // it emits the {NewFeeDistributor} event
        vm.expectEmit(false, false, false, true);
        emit NewFeeDistributor(preFeeDistributor, newFeeDistributor);
        vaultFactory.setFeeDistributor(newFeeDistributor);

        // it sets the fee distributor
        assertEq(vaultFactory.feeDistributor(), newFeeDistributor);
    }
}
