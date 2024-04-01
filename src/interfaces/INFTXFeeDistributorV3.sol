// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INFTXRouter} from "@src/interfaces/INFTXRouter.sol";
import {IUniswapV3Factory} from "@uni-core/interfaces/IUniswapV3Factory.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {INFTXInventoryStakingV3} from "@src/interfaces/INFTXInventoryStakingV3.sol";

interface INFTXFeeDistributorV3 {
    enum ReceiverType {
        INVENTORY,
        POOL,
        ADDRESS
    }

    struct FeeReceiver {
        address receiver;
        uint256 allocPoint;
        ReceiverType receiverType; // NOTE: receiver address is ignored for `POOL` type, as each vaultId has different pool address
    }

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    function nftxVaultFactory() external view returns (INFTXVaultFactoryV3);

    function ammFactory() external view returns (IUniswapV3Factory);

    function inventoryStaking() external view returns (INFTXInventoryStakingV3);

    function WETH() external view returns (IERC20);

    // =============================================================
    //                            STORAGE
    // =============================================================

    function rewardFeeTier() external view returns (uint24);

    function nftxRouter() external view returns (INFTXRouter);

    function treasury() external view returns (address);

    function allocTotal() external view returns (uint256);

    function feeReceivers(
        uint256
    )
        external
        view
        returns (
            address receiver,
            uint256 allocPoint,
            ReceiverType receiverType
        );

    // =============================================================
    //                            EVENTS
    // =============================================================

    event UpdateTreasuryAddress(address oldTreasury, address newTreasury);
    event PauseDistribution(bool paused);
    event NewRewardFeeTier(uint24 rewardFeeTier);
    event NewNFTXRouter(address nftxRouter);
    event WethDistributedToInventory(uint256 vaultId, uint256 amount);
    event WethDistributedToPool(uint256 vaultId, uint256 amount);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error IdOutOfBounds();
    error ZeroAddress();
    error SenderNotNFTXRouter();
    error FeeTierNotEnabled();

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    /**
     * @notice Distributes current WETH balance with the `feeReceivers` for `vaultId`
     * @dev called by other contracts like NFTXVault, after transferring WETH to distribute in the same tx
     */
    function distribute(uint256 vaultId) external;

    /**
     * @notice Distributes vTokens to NFTX AMM pool, can only be called by NFTXRouter
     * @dev called by NFTXRouter, after it sends the vTokens to this contract
     */
    function distributeVTokensToPool(
        address pool,
        address vToken,
        uint256 vTokenAmount
    ) external;

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    function setReceivers(FeeReceiver[] memory feeReceivers_) external;

    /**
     * @notice Updating reward fee tier here won't change cardinality for existing UniV3 pools already deployed with `rewardFeeTier_`. That has to be increased externally for each pool.
     * If the new rewardFeeTier pool doesn't exist for a vToken, then the corresponding vault fees would immediately become 0, till liquidity is provided in the new pool.
     *
     * @param rewardFeeTier_ New reward fee tier
     */
    function changeRewardFeeTier(uint24 rewardFeeTier_) external;

    function setTreasuryAddress(address treasury) external;

    function setNFTXRouter(INFTXRouter nftxRouter) external;

    function rescueTokens(IERC20 token) external;
}
