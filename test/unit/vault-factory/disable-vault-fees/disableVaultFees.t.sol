// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract disableVaultFees_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint64 constant DEFAULT_VAULT_FACTORY_FEES = 0.1 ether;

    uint256 vaultId;

    enum Caller {
        Owner,
        Vault
    }

    event DisableVaultFees(uint256 vaultId);

    function setUp() public virtual override {
        super.setUp();
        // deploy vault, so that vaultId is set in the factory
        (vaultId, ) = deployVToken721(vaultFactory);
        // set custom vault fees
        switchPrank(users.owner);
        vaultFactory.setVaultFees({
            vaultId: vaultId,
            mintFee: 0.25 ether,
            redeemFee: 0.275 ether,
            swapFee: 0.30 ether
        });
        switchPrank(users.alice);
    }

    function test_RevertWhen_TheCallerIsNotTheOwnerOrTheVaultContract()
        external
    {
        vm.expectRevert(INFTXVaultFactoryV3.CallerIsNotVault.selector);
        vaultFactory.disableVaultFees(vaultId);
    }

    function test_WhenTheCallerIsTheOwnerOrTheVaultContract(
        uint8 callerIndex
    ) external {
        vm.assume(callerIndex < 2);
        Caller caller = Caller(callerIndex);
        if (caller == Caller.Owner) {
            switchPrank(users.owner);
        } else if (caller == Caller.Vault) {
            switchPrank(vaultFactory.vault(vaultId));
        }

        // it should emit {DisableVaultFees} event
        vm.expectEmit(false, false, false, true);
        // TODO: vaultId can be made indexed in this event
        emit DisableVaultFees(vaultId);
        vaultFactory.disableVaultFees(vaultId);

        // it should reset the vault mint, redeem and swap fees to the factory default
        (uint256 _mintFee, uint256 _redeemFee, uint256 _swapFee) = vaultFactory
            .vaultFees(vaultId);

        assertEq(_mintFee, DEFAULT_VAULT_FACTORY_FEES);
        assertEq(_redeemFee, DEFAULT_VAULT_FACTORY_FEES);
        assertEq(_swapFee, DEFAULT_VAULT_FACTORY_FEES);
    }
}
