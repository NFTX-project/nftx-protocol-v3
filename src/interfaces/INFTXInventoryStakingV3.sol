// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {ITimelockExcludeList} from "@src/interfaces/ITimelockExcludeList.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";

interface INFTXInventoryStakingV3 is IERC721Upgradeable {
    // details about the staking position
    struct Position {
        // the nonce for permits
        uint256 nonce;
        // vaultId corresponding to the vTokens staked in this position
        uint256 vaultId;
        // timestamp at which the timelock expires
        uint256 timelockedUntil;
        // shares balance is used to track position's ownership of total vToken balance
        uint256 vTokenShareBalance;
        // used to evaluate weth fees accumulated per vTokenShare since this snapshot
        uint256 wethFeesPerVTokenShareSnapshotX128;
        // owed weth fees, updates when positions merged
        uint256 wethOwed;
    }

    struct VaultGlobal {
        uint256 totalVTokenShares;
        uint256 globalWethFeesPerVTokenShareX128;
    }

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    function MINIMUM_LIQUIDITY() external view returns (uint256);

    function nftxVaultFactory() external view returns (INFTXVaultFactoryV3);

    function timelockExcludeList() external view returns (ITimelockExcludeList);

    function WETH() external view returns (IWETH9);

    function PERMIT2() external returns (IPermitAllowanceTransfer);

    // =============================================================
    //                            STORAGE
    // =============================================================

    function timelock() external view returns (uint256);

    function earlyWithdrawPenaltyInWei() external view returns (uint256);

    function positions(
        uint256 positionId
    )
        external
        view
        returns (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        );

    function vaultGlobal(
        uint256 vaultId
    )
        external
        view
        returns (
            uint256 totalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        );

    // =============================================================
    //                            EVENTS
    // =============================================================

    event Deposit(
        uint256 indexed vaultId,
        uint256 indexed positionId,
        uint256 amount
    );
    event DepositWithNFT(
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
    event UpdateTimelock(uint256 newTimelock);
    event UpdateEarlyWithdrawPenalty(uint256 newEarlyWithdrawPenaltyInWei);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error TimelockTooLong();
    error InvalidEarlyWithdrawPenalty();
    error NotPositionOwner();
    error Timelocked();
    error VaultIdMismatch();
    error ParentChildSame();
    error RedeemNotAllowedWithoutTimelock();
    error InsufficientVTokens();

    // =============================================================
    //                           INIT
    // =============================================================

    function __NFTXInventoryStaking_init(
        uint256 timelock_,
        uint256 earlyWithdrawPenaltyInWei_,
        ITimelockExcludeList timelockExcludeList_
    ) external;

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    function deposit(
        uint256 vaultId,
        uint256 amount,
        address recipient,
        bool forceTimelock
    ) external returns (uint256 positionId);

    function depositWithPermit2(
        uint256 vaultId,
        uint256 amount,
        address recipient,
        bytes calldata encodedPermit2,
        bool forceTimelock
    ) external returns (uint256 positionId);

    /// @notice This contract must be on the feeExclusion list to avoid mint fees, else revert
    function depositWithNFT(
        uint256 vaultId,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        address recipient
    ) external returns (uint256 positionId);

    /// @notice This contract must be on the feeExclusion list to avoid redeem fees, else revert
    function withdraw(
        uint256 positionId,
        uint256 vTokenShares,
        uint256[] calldata nftIds
    ) external;

    function combinePositions(
        uint256 parentPositionId,
        uint256[] calldata childPositionIds
    ) external;

    function collectWethFees(uint256 positionId) external;

    function receiveWethRewards(
        uint256 vaultId,
        uint256 wethAmount
    ) external returns (bool);

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    function setTimelock(uint256 timelock_) external;

    function setEarlyWithdrawPenalty(
        uint256 earlyWithdrawPenaltyInWei_
    ) external;

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    function pricePerShareVToken(
        uint256 vaultId
    ) external view returns (uint256);

    function wethBalance(uint256 positionId) external view returns (uint256);
}
