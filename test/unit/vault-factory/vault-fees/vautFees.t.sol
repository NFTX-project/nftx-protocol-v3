// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract vaultFees_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint64 constant DEFAULT_VAULT_FACTORY_FEES = 0.1 ether;
    uint256 constant FEE_LIMIT = 0.5 ether;

    uint256 vaultId;

    function setUp() public virtual override {
        super.setUp();

        // deploy vault
        (vaultId, ) = deployVToken721(vaultFactory);
    }

    function test_GivenTheCustomVaultFeeIsNotSet() external {
        (uint256 mintFee, uint256 redeemFee, uint256 swapFee) = vaultFactory
            .vaultFees(vaultId);

        // it should return the factory mint, redeem and swap fees
        assertEq(mintFee, DEFAULT_VAULT_FACTORY_FEES);
        assertEq(redeemFee, DEFAULT_VAULT_FACTORY_FEES);
        assertEq(swapFee, DEFAULT_VAULT_FACTORY_FEES);
    }

    function test_GivenTheCustomVaultFeeIsSet(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    ) external {
        // set custom vault fees
        vm.assume(
            mintFee <= FEE_LIMIT && mintFee != DEFAULT_VAULT_FACTORY_FEES
        );
        vm.assume(
            redeemFee <= FEE_LIMIT && redeemFee != DEFAULT_VAULT_FACTORY_FEES
        );
        vm.assume(
            swapFee <= FEE_LIMIT && swapFee != DEFAULT_VAULT_FACTORY_FEES
        );
        switchPrank(users.owner);
        vaultFactory.setVaultFees(vaultId, mintFee, redeemFee, swapFee);

        // it should return the custom vault mint, redeem and swap fees
        (uint256 _mintFee, uint256 _redeemFee, uint256 _swapFee) = vaultFactory
            .vaultFees(vaultId);

        assertEq(_mintFee, mintFee);
        assertEq(_redeemFee, redeemFee);
        assertEq(_swapFee, swapFee);
    }
}
