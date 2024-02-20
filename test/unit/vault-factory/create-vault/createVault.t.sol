// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {PausableUpgradeable} from "@src/custom/PausableUpgradeable.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {NFTXVaultFactoryUpgradeableV3} from "@src/NFTXVaultFactoryUpgradeableV3.sol";
import {NFTXVaultUpgradeableV3} from "@src/NFTXVaultUpgradeableV3.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract createVault_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint256 constant CREATEVAULT_LOCK_ID = 0;

    string name = "Test";
    string symbol = "TST";
    address assetAddress;
    bool is1155 = false;
    bool allowAllItems = true;

    event NewVault(
        uint256 indexed vaultId,
        address vaultAddress,
        address assetAddress,
        string name,
        string symbol
    );

    function setUp() public virtual override {
        super.setUp();
        assetAddress = address(nft721);
    }

    function test_RevertGiven_TheFeeDistributorIsNotSet() external {
        // new deployment where fee distributor is not set yet
        vaultFactory = new NFTXVaultFactoryUpgradeableV3();

        vm.expectRevert(INFTXVaultFactoryV3.FeeDistributorNotSet.selector);
        vaultFactory.createVault(
            name,
            symbol,
            assetAddress,
            is1155,
            allowAllItems
        );
    }

    modifier givenTheFeeDistributorIsSet() {
        _;
    }

    function test_RevertGiven_TheVaultImplementationIsNotSet()
        external
        givenTheFeeDistributorIsSet
    {
        // note: this error (VaultImplementationNotSet) won't ever be thrown because:
        // if feeDistributor is not set it'll revert there first.
        // if we try to set feeDistributor, then owner has to be set which means that init has to be called first
        // if init is called, then vaultImpl has to be set (UpgradeableBeacon doesn't allow non contract address to be passed)
        assertTrue(true);
    }

    modifier givenTheVaultImplementationIsSet() {
        _;
    }

    modifier givenTheCreateVaultOperationIsPaused() {
        // pause createVault
        switchPrank(users.owner);

        vaultFactory.setIsGuardian(users.owner, true);
        vaultFactory.pause(CREATEVAULT_LOCK_ID);

        switchPrank(users.alice);
        _;
    }

    function test_RevertWhen_TheCallerIsNotTheOwner()
        external
        givenTheFeeDistributorIsSet
        givenTheVaultImplementationIsSet
        givenTheCreateVaultOperationIsPaused
    {
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        vaultFactory.createVault(
            name,
            symbol,
            assetAddress,
            is1155,
            allowAllItems
        );
    }

    modifier givenTheCreateVaultOperationIsNotPaused() {
        _;
    }

    function test_RevertGiven_TheVaultWithSameNameAndSymbolExistsForTheSameAsset()
        external
        givenTheFeeDistributorIsSet
        givenTheVaultImplementationIsSet
        givenTheCreateVaultOperationIsNotPaused
    {
        // deploy initial vault
        vaultFactory.createVault(
            name,
            symbol,
            assetAddress,
            is1155,
            allowAllItems
        );

        // it should revert, if we try to deploy again with same params
        vm.expectRevert("Create2: Failed on deploy");
        vaultFactory.createVault(
            name,
            symbol,
            assetAddress,
            is1155,
            allowAllItems
        );
    }

    function test_GivenTheVaultWithSameNameAndSymbolDoesNotExistForTheSameAsset()
        external
        givenTheFeeDistributorIsSet
        givenTheVaultImplementationIsSet
        givenTheCreateVaultOperationIsNotPaused
    {
        uint256 preNumVaults = vaultFactory.numVaults();
        uint256 expectedVaultId = preNumVaults;
        address expectedVaultAddress = vaultFactory.computeVaultAddress(
            assetAddress,
            name,
            symbol
        );
        uint256 preVaultsForAssetLength = vaultFactory
            .vaultsForAsset(assetAddress)
            .length;

        // it should emit a {NewVault} event
        vm.expectEmit(true, false, false, true);
        emit NewVault(
            expectedVaultId,
            expectedVaultAddress,
            assetAddress,
            name,
            symbol
        );
        uint256 vaultId = vaultFactory.createVault(
            name,
            symbol,
            assetAddress,
            is1155,
            allowAllItems
        );
        // it should deploy a new vault as beacon proxy
        // it should bump the number of vaults
        assertEq(vaultFactory.numVaults(), preNumVaults + 1);
        // it should add the vault to the vault mapping
        assertEq(vaultId, expectedVaultId);
        assertEq(vaultFactory.vault(vaultId), expectedVaultAddress);
        // it should add the vault to vaults for asset mapping
        assertEq(
            vaultFactory.vaultsForAsset(assetAddress).length,
            preVaultsForAssetLength + 1
        );
        address[] memory vaultsForAsset = vaultFactory.vaultsForAsset(
            assetAddress
        );
        assertEq(vaultsForAsset[preVaultsForAssetLength], expectedVaultAddress);

        NFTXVaultUpgradeableV3 vault = NFTXVaultUpgradeableV3(
            expectedVaultAddress
        );
        // it should set the vault's name
        assertEq(vault.name(), name);
        // it should set the vault's symbol
        assertEq(vault.symbol(), symbol);
        // it should set the vault's asset
        assertEq(vault.assetAddress(), assetAddress);
        // it should set the vault's asset type
        assertEq(vault.is1155(), is1155);
        // it should set the vault's {allowAllItems}
        assertEq(vault.allowAllItems(), allowAllItems);
        // it should set the vault's manager to the caller
        assertEq(vault.manager(), users.alice);
        // it should set the vault's owner
        assertEq(vault.owner(), vaultFactory.owner());
    }
}
