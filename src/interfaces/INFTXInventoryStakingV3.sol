// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {IERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";

import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";

interface INFTXInventoryStakingV3 is IERC721Upgradeable {
    function nftxVaultFactory() external view returns (INFTXVaultFactory);

    function deposit(
        uint256 vaultId,
        uint256 amount,
        address recipient
    ) external returns (uint256 tokenId);

    function receiveRewards(
        uint256 vaultId,
        uint256 wethAmount
    ) external returns (bool);
}
