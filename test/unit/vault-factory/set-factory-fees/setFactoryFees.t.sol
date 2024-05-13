// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract setFactoryFees_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint256 constant MAX_FEE_LIMIT = 0.5 ether;

    uint256 mintFee = 0.25 ether;
    uint256 redeemFee = 0.275 ether;
    uint256 swapFee = 0.30 ether;

    event UpdateFactoryFees(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    );

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        vaultFactory.setFactoryFees(mintFee, redeemFee, swapFee);
    }

    modifier whenTheCallerIsTheOwner() {
        switchPrank(users.owner);
        _;
    }

    function test_RevertWhen_TheMintFeeIsGreaterThanLimit(
        uint256 feeDelta
    ) external whenTheCallerIsTheOwner {
        vm.assume(feeDelta > 1);
        // to prevent overflow in the tests below
        vm.assume(feeDelta < type(uint256).max - MAX_FEE_LIMIT);

        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);

        mintFee = MAX_FEE_LIMIT + feeDelta;

        vaultFactory.setFactoryFees(mintFee, redeemFee, swapFee);
    }

    modifier whenTheMintFeeIsLessThanOrEqualToTheLimit() {
        _;
    }

    function test_RevertWhen_TheRedeemFeeIsGreaterThanLimit(
        uint256 feeDelta
    )
        external
        whenTheCallerIsTheOwner
        whenTheMintFeeIsLessThanOrEqualToTheLimit
    {
        vm.assume(feeDelta > 1);
        // to prevent overflow in the tests below
        vm.assume(feeDelta < type(uint256).max - MAX_FEE_LIMIT);

        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);

        redeemFee = MAX_FEE_LIMIT + feeDelta;

        vaultFactory.setFactoryFees(mintFee, redeemFee, swapFee);
    }

    modifier whenTheRedeemFeeIsLessThanOrEqualToTheLimit() {
        _;
    }

    function test_RevertWhen_TheSwapFeeIsGreaterThanLimit(
        uint256 feeDelta
    )
        external
        whenTheCallerIsTheOwner
        whenTheMintFeeIsLessThanOrEqualToTheLimit
        whenTheRedeemFeeIsLessThanOrEqualToTheLimit
    {
        vm.assume(feeDelta > 1);
        // to prevent overflow in the tests below
        vm.assume(feeDelta < type(uint256).max - MAX_FEE_LIMIT);

        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);

        swapFee = MAX_FEE_LIMIT + feeDelta;

        vaultFactory.setFactoryFees(mintFee, redeemFee, swapFee);
    }

    function test_WhenTheSwapFeeIsLessThanOrEqualToTheLimit(
        uint256 newMintFee,
        uint256 newRedeemFee,
        uint256 newSwapFee
    )
        external
        whenTheCallerIsTheOwner
        whenTheMintFeeIsLessThanOrEqualToTheLimit
        whenTheRedeemFeeIsLessThanOrEqualToTheLimit
    {
        vm.assume(newMintFee <= MAX_FEE_LIMIT);
        vm.assume(newRedeemFee <= MAX_FEE_LIMIT);
        vm.assume(newSwapFee <= MAX_FEE_LIMIT);

        // it should emit {UpdateFactoryFees} event
        vm.expectEmit(false, false, false, true);
        emit UpdateFactoryFees(newMintFee, newRedeemFee, newSwapFee);
        vaultFactory.setFactoryFees(newMintFee, newRedeemFee, newSwapFee);

        // it should set the mint fee
        assertEq(vaultFactory.factoryMintFee(), uint64(newMintFee));
        // it should set the redeem fee
        assertEq(vaultFactory.factoryRedeemFee(), uint64(newRedeemFee));
        // it should set the swap fee
        assertEq(vaultFactory.factorySwapFee(), uint64(newSwapFee));
    }
}
