// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Create2Upgradeable} from "@openzeppelin-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {Create2BeaconProxy} from "@src/custom/proxy/Create2BeaconProxy.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract computeAddress_Unit_Test is NFTXVaultFactory_Unit_Test {
    string name = "CryptoPunk";
    string symbol = "PUNK";
    address assetAddress;

    function setUp() public virtual override {
        super.setUp();
        assetAddress = address(nft721);
    }

    function test_ShouldMatchTheComputedAddressWithTheVaultAddress() external {
        address computedAddress = vaultFactory.computeVaultAddress(
            assetAddress,
            name,
            symbol
        );

        address expectedVaultAddress = Create2Upgradeable.computeAddress(
            keccak256(abi.encode(assetAddress, name, symbol)),
            keccak256(type(Create2BeaconProxy).creationCode),
            address(vaultFactory)
        );

        uint256 vaultId = vaultFactory.createVault({
            name: name,
            symbol: symbol,
            assetAddress: assetAddress,
            is1155: false,
            allowAllItems: true
        });
        address actualVaultAddress = vaultFactory.vault(vaultId);

        // it should match the computed address with the vault address
        assertEq(computedAddress, expectedVaultAddress);
        assertEq(computedAddress, actualVaultAddress);
    }
}
