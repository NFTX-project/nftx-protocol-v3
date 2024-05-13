// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ShutdownRedeemerUpgradeable} from "@src/periphery/ShutdownRedeemerUpgradeable.sol";
import {NFTXVaultFactoryUpgradeableV3} from "@src/NFTXVaultFactoryUpgradeableV3.sol";

import {INFTXVaultFactoryV2} from "@src/v2/interfaces/INFTXVaultFactoryV2.sol";

import {NewTestBase} from "@test/NewTestBase.sol";

contract ShutdownRedeemer_Unit_Test is NewTestBase {
    ShutdownRedeemerUpgradeable shutdownRedeemer;
    NFTXVaultFactoryUpgradeableV3 vaultFactory;

    function setUp() public virtual override {
        super.setUp();

        switchPrank(users.owner);
        (, , , , vaultFactory, ) = deployNFTXV3Core();

        // `vault` function same in V2 and V3 vault factories along with ERC20 functions for V2 and V3 vaults, so using v3 here for simplicity
        shutdownRedeemer = new ShutdownRedeemerUpgradeable(
            INFTXVaultFactoryV2(address(vaultFactory))
        );
        shutdownRedeemer.__ShutdownRedeemer_init();

        switchPrank(users.alice);
    }
}
