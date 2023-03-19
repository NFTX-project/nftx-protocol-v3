// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";

interface INFTXInventoryStakingV3 {
    function nftxVaultFactory() external view returns (INFTXVaultFactory);

    function deployXTokenForVault(uint256 vaultId) external;

    function receiveRewards(
        uint256 vaultId,
        uint256 wethAmount
    ) external returns (bool);
}
