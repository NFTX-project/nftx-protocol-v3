// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {NFTXVaultFactoryUpgradeableV3} from "@src/NFTXVaultFactoryUpgradeableV3.sol";
import {NFTXRouter} from "@src/NFTXRouter.sol";

import {NewTestBase} from "@test/NewTestBase.sol";

contract NFTXVaultFactory_Unit_Test is NewTestBase {
    address vaultImpl;
    uint32 twapInterval = 20 minutes;
    uint256 premiumDuration = 10 hours;
    uint256 premiumMax = 5 ether;
    uint256 depositorPremiumShare = 0.30 ether;

    NFTXVaultFactoryUpgradeableV3 vaultFactory;
    NFTXRouter nftxRouter;

    function setUp() public virtual override {
        super.setUp();

        switchPrank(users.owner);
        (, nftxRouter, , , vaultFactory, ) = deployFeeDistributor();
        vaultImpl = vaultFactory.implementation();
        switchPrank(users.alice);
    }
}
