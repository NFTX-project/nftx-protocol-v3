// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {IERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";

import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";

interface INFTXInventoryStakingV3 is IERC721Upgradeable {
    // =============================================================
    //                            EVENTS
    // =============================================================

    event Deposit(
        uint256 indexed vaultId,
        uint256 indexed positionId,
        uint256 amount
    );
    event Withdraw(
        uint256 indexed positionId,
        uint256 vTokenShares,
        uint256 vTokenAmount,
        uint256 wethAmount
    );
    event CollectWethFees(uint256 indexed positionId, uint256 wethAmount);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error TimelockTooLong();

    error NotPositionOwner();

    error Timelocked();

    error VaultIdMismatch();

    function nftxVaultFactory() external view returns (INFTXVaultFactory);

    function deposit(
        uint256 vaultId,
        uint256 amount,
        address recipient
    ) external returns (uint256 tokenId);

    function withdraw(uint256 positionId, uint256 vTokenShares) external;

    function collectWethFees(uint256 positionId) external;

    function receiveRewards(
        uint256 vaultId,
        uint256 amount,
        bool isRewardWeth
    ) external returns (bool);

    function pricePerShareVToken(
        uint256 vaultId
    ) external view returns (uint256);

    // TODO: add missing functions
}
