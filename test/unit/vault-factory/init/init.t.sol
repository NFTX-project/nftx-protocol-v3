// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {UpgradeableBeacon} from "@src/custom/proxy/UpgradeableBeacon.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract NFTXVaultFactory_Init_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint256 constant MAX_DEPOSITOR_PREMIUM_SHARE = 1 ether;
    uint64 constant DEFAULT_VAULT_FACTORY_FEES = 0.1 ether;

    event Initialized(uint8 version);

    function setUp() public virtual override {
        super.setUp();

        // this function should be called by the owner
        switchPrank(users.owner);
    }

    function test_RevertGiven_TheContractIsInitialized() external {
        /// initialize the vault factory
        vaultFactory.__NFTXVaultFactory_init({
            vaultImpl: address(vaultImpl),
            twapInterval_: twapInterval,
            premiumDuration_: premiumDuration,
            premiumMax_: premiumMax,
            depositorPremiumShare_: depositorPremiumShare
        });

        // it should revert, if initialized again
        vm.expectRevert(REVERT_ALREADY_INITIALIZED);
        vaultFactory.__NFTXVaultFactory_init({
            vaultImpl: address(vaultImpl),
            twapInterval_: twapInterval,
            premiumDuration_: premiumDuration,
            premiumMax_: premiumMax,
            depositorPremiumShare_: depositorPremiumShare
        });
    }

    modifier givenTheContractIsNotInitialized() {
        _;
    }

    function test_RevertWhen_TheVaultImplementationIsNotAContract()
        external
        givenTheContractIsNotInitialized
    {
        vm.expectRevert(
            UpgradeableBeacon.ChildImplementationIsNotAContract.selector
        );
        address nonContractImplementation = makeAddr(
            "nonContractImplementation"
        );
        vaultFactory.__NFTXVaultFactory_init({
            vaultImpl: nonContractImplementation,
            twapInterval_: twapInterval,
            premiumDuration_: premiumDuration,
            premiumMax_: premiumMax,
            depositorPremiumShare_: depositorPremiumShare
        });
    }

    modifier whenTheVaultImplementationIsAContract() {
        _;
    }

    function test_RevertWhen_TheTwapIntervalIsZero()
        external
        givenTheContractIsNotInitialized
        whenTheVaultImplementationIsAContract
    {
        vm.expectRevert(INFTXVaultFactoryV3.ZeroTwapInterval.selector);

        twapInterval = 0;

        vaultFactory.__NFTXVaultFactory_init({
            vaultImpl: vaultImpl,
            twapInterval_: twapInterval,
            premiumDuration_: premiumDuration,
            premiumMax_: premiumMax,
            depositorPremiumShare_: depositorPremiumShare
        });
    }

    modifier whenTheTwapIntervalIsGreaterThanZero() {
        _;
    }

    function test_RevertWhen_TheDepositorPremiumShareIsGreaterThanMaxDepositorPremiumShare()
        external
        givenTheContractIsNotInitialized
        whenTheVaultImplementationIsAContract
        whenTheTwapIntervalIsGreaterThanZero
    {
        vm.expectRevert(
            INFTXVaultFactoryV3.DepositorPremiumShareExceedsLimit.selector
        );

        depositorPremiumShare = MAX_DEPOSITOR_PREMIUM_SHARE + 1;

        vaultFactory.__NFTXVaultFactory_init({
            vaultImpl: vaultImpl,
            twapInterval_: twapInterval,
            premiumDuration_: premiumDuration,
            premiumMax_: premiumMax,
            depositorPremiumShare_: depositorPremiumShare
        });
    }

    function test_WhenTheDepositorPremiumShareIsLessThanOrEqualToMaxDepositorPremiumShare()
        external
        givenTheContractIsNotInitialized
        whenTheVaultImplementationIsAContract
        whenTheTwapIntervalIsGreaterThanZero
    {
        vm.expectEmit(false, false, false, true);
        // it should set the contract as initialized
        emit Initialized(1); // 1 = version
        vaultFactory.__NFTXVaultFactory_init({
            vaultImpl: vaultImpl,
            twapInterval_: twapInterval,
            premiumDuration_: premiumDuration,
            premiumMax_: premiumMax,
            depositorPremiumShare_: depositorPremiumShare
        });

        // it should set the owner
        assertEq(vaultFactory.owner(), users.owner);
        // it should set the vault implementation
        assertEq(vaultFactory.implementation(), vaultImpl);
        // it should set the factory mint fee
        assertEq(vaultFactory.factoryMintFee(), DEFAULT_VAULT_FACTORY_FEES);
        // it should set the factory redeem fee
        assertEq(vaultFactory.factoryRedeemFee(), DEFAULT_VAULT_FACTORY_FEES);
        // it should set the factory swap fee
        assertEq(vaultFactory.factorySwapFee(), DEFAULT_VAULT_FACTORY_FEES);
        // it should set the twap interval
        assertEq(vaultFactory.twapInterval(), twapInterval);
        // it should set the premium duration
        assertEq(vaultFactory.premiumDuration(), premiumDuration);
        // it should set the premium max
        assertEq(vaultFactory.premiumMax(), premiumMax);
        // it should set the depositor premium share
        assertEq(vaultFactory.depositorPremiumShare(), depositorPremiumShare);
    }
}
