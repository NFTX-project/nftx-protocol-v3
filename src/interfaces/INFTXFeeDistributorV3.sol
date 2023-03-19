// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INFTXVaultFactory} from "../v2/interface/INFTXVaultFactory.sol";
import {INFTXInventoryStaking} from "../v2/interface/INFTXInventoryStaking.sol";
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

    function nftxVaultFactory() external returns (INFTXVaultFactory);

    function inventoryStaking() external returns (INFTXInventoryStaking);

    function WETH() external returns (IERC20);

    // =============================================================
    //                            STORAGE
    // =============================================================

    function nftxRouter() external returns (INFTXRouter);

    function treasury() external returns (address);

    function allocTotal() external returns (uint256);

    /**
    // Overriding with the following functions doesn't work:
    
    function feeReceivers(uint256)
        external
        view
        returns (
            address receiver,
            uint256 allocPoint,
            uint8 receiverType
        );

    function feeReceivers(uint256) external view returns (FeeReceiver memory);
    */

    function distributionPaused() external returns (bool);

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

    function initializeVaultReceivers(uint256 vaultId) external;

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
