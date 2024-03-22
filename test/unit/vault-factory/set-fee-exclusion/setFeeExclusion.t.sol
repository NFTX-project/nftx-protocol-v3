// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract setFeeExclusion_Unit_Test is NFTXVaultFactory_Unit_Test {
    address excludedAddr;

    event FeeExclusion(address feeExcluded, bool excluded);

    function setUp() public virtual override {
        super.setUp();

        excludedAddr = makeAddr("excludedAddr");
    }

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        vaultFactory.setFeeExclusion({
            excludedAddr: excludedAddr,
            excluded: true
        });
    }

    function test_WhenTheCallerIsTheOwner(bool excluded) external {
        switchPrank(users.owner);

        // it should emit {FeeExclusion} event
        vm.expectEmit(false, false, false, true);
        emit FeeExclusion(excludedAddr, excluded);
        vaultFactory.setFeeExclusion(excludedAddr, excluded);

        // it should add the address to the fee exclusion list
        assertEq(vaultFactory.excludedFromFees(excludedAddr), excluded);
    }
}
