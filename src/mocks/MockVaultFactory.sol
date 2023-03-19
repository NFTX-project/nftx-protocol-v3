// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

contract MockVaultFactory {
    address[] internal vaults;

    function addVault(address vToken) external {
        vaults.push(vToken);
    }

    function vault(uint256 vaultId) external view returns (address) {
        return vaults[vaultId];
    }
}
