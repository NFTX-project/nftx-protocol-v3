// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract setVaultFees_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint256 constant MAX_FEE_LIMIT = 0.5 ether;

    uint256 vaultId;
    uint256 mintFee = 0.25 ether;
    uint256 redeemFee = 0.275 ether;
    uint256 swapFee = 0.30 ether;

    enum Caller {
        Owner,
        Vault
    }

    event UpdateVaultFees(
        uint256 vaultId,
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    );

    function setUp() public virtual override {
        super.setUp();
        // deploy vault, so that vaultId is set in the factory
        (vaultId, ) = deployVToken721(vaultFactory);
    }

    function test_RevertWhen_TheCallerIsNotTheOwnerOrTheVaultContract()
        external
    {
        vm.expectRevert(INFTXVaultFactoryV3.CallerIsNotVault.selector);
        vaultFactory.setVaultFees(vaultId, mintFee, redeemFee, swapFee);
    }

    modifier whenTheCallerIsTheOwnerOrTheVaultContract(uint8 callerIndex) {
        vm.assume(callerIndex < 2);
        Caller caller = Caller(callerIndex);

        if (caller == Caller.Owner) {
            switchPrank(users.owner);
        } else if (caller == Caller.Vault) {
            switchPrank(vaultFactory.vault(vaultId));
        }
        _;
    }

    function test_RevertWhen_TheMintFeeIsGreaterThanTheLimit(
        uint256 feeDelta,
        uint8 callerIndex
    ) external whenTheCallerIsTheOwnerOrTheVaultContract(callerIndex) {
        vm.assume(feeDelta > 1);
        // to prevent overflow in the tests below
        vm.assume(feeDelta < type(uint256).max - MAX_FEE_LIMIT);

        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);

        mintFee = MAX_FEE_LIMIT + feeDelta;

        vaultFactory.setVaultFees(vaultId, mintFee, redeemFee, swapFee);
    }

    modifier whenTheMintFeeIsLessThanOrEqualToTheLimit() {
        _;
    }

    function test_RevertWhen_TheRedeemFeeIsGreaterThanTheLimit(
        uint256 feeDelta,
        uint8 callerIndex
    )
        external
        whenTheCallerIsTheOwnerOrTheVaultContract(callerIndex)
        whenTheMintFeeIsLessThanOrEqualToTheLimit
    {
        vm.assume(feeDelta > 1);
        // to prevent overflow in the tests below
        vm.assume(feeDelta < type(uint256).max - MAX_FEE_LIMIT);

        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);

        redeemFee = MAX_FEE_LIMIT + feeDelta;

        vaultFactory.setVaultFees(vaultId, mintFee, redeemFee, swapFee);
    }

    modifier whenTheRedeemFeeIsLessThanOrEqualToTheLimit() {
        _;
    }

    function test_RevertWhen_TheSwapFeeIsGreaterThanTheLimit(
        uint256 feeDelta,
        uint8 callerIndex
    )
        external
        whenTheCallerIsTheOwnerOrTheVaultContract(callerIndex)
        whenTheMintFeeIsLessThanOrEqualToTheLimit
        whenTheRedeemFeeIsLessThanOrEqualToTheLimit
    {
        vm.assume(feeDelta > 1);
        // to prevent overflow in the tests below
        vm.assume(feeDelta < type(uint256).max - MAX_FEE_LIMIT);

        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);

        swapFee = MAX_FEE_LIMIT + feeDelta;

        vaultFactory.setVaultFees(vaultId, mintFee, redeemFee, swapFee);
    }

    function test_WhenTheSwapFeeIsLessThanOrEqualToTheLimit(
        uint256 newMintFee,
        uint256 newRedeemFee,
        uint256 newSwapFee,
        uint8 callerIndex
    )
        external
        whenTheCallerIsTheOwnerOrTheVaultContract(callerIndex)
        whenTheMintFeeIsLessThanOrEqualToTheLimit
        whenTheRedeemFeeIsLessThanOrEqualToTheLimit
    {
        vm.assume(newMintFee <= MAX_FEE_LIMIT);
        vm.assume(newRedeemFee <= MAX_FEE_LIMIT);
        vm.assume(newSwapFee <= MAX_FEE_LIMIT);

        // it should emit {UpdateVaultFees} event
        vm.expectEmit(false, false, false, true);
        // TODO: vaultId can be made indexed in this event
        emit UpdateVaultFees(vaultId, newMintFee, newRedeemFee, newSwapFee);
        vaultFactory.setVaultFees(
            vaultId,
            newMintFee,
            newRedeemFee,
            newSwapFee
        );

        (uint256 _mintFee, uint256 _redeemFee, uint256 _swapFee) = vaultFactory
            .vaultFees(vaultId);

        // it should set the vault mint fee
        assertEq(_mintFee, newMintFee);
        // it should set the vault redeem fee
        assertEq(_redeemFee, newRedeemFee);
        // it should set the vault swap fee
        assertEq(_swapFee, newSwapFee);
    }
}
