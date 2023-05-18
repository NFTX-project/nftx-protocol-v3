// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";
import {INFTXInventoryStakingV3} from "@src/interfaces/INFTXInventoryStakingV3.sol";
import {INFTXRouter} from "./INFTXRouter.sol";

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

    function nftxVaultFactory() external view returns (INFTXVaultFactory);

    function inventoryStaking() external view returns (INFTXInventoryStakingV3);

    function WETH() external view returns (IERC20);

    function REWARD_FEE_TIER() external view returns (uint24);

    // =============================================================
    //                            STORAGE
    // =============================================================

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

    function distributionPaused() external view returns (bool);

    // =============================================================
    //                            EVENTS
    // =============================================================

    event UpdateTreasuryAddress(address newTreasury);
    event PauseDistribution(bool paused);

    event AddFeeReceiver(address receiver, uint256 allocPoint);
    event UpdateFeeReceiverAlloc(address receiver, uint256 allocPoint);
    event UpdateFeeReceiverAddress(address oldReceiver, address newReceiver);
    event RemoveFeeReceiver(address receiver);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error IdOutOfBounds();
    error AddressIsZero();

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    function distribute(uint256 vaultId) external;

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    function addReceiver(
        address receiver,
        uint256 allocPoint,
        ReceiverType receiverType
    ) external;

    function changeReceiverAlloc(
        uint256 receiverId,
        uint256 allocPoint
    ) external;

    function changeReceiverAddress(
        uint256 receiverId,
        address receiver,
        ReceiverType receiverType
    ) external;

    function removeReceiver(uint256 receiverId) external;

    function setTreasuryAddress(address treasury_) external;

    function pauseFeeDistribution(bool pause) external;

    function rescueTokens(IERC20 token) external;
}
