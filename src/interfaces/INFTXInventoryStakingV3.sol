// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {ITimelockExcludeList} from "@src/interfaces/ITimelockExcludeList.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";
import {InventoryStakingDescriptor} from "@src/custom/InventoryStakingDescriptor.sol";

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

    function descriptor() external view returns (InventoryStakingDescriptor);

    // =============================================================
    //                            EVENTS
    // =============================================================

    event Deposit(
        uint256 indexed vaultId,
        uint256 indexed positionId,
        uint256 amount,
        bool forceTimelock
    );
    event DepositWithNFT(
        uint256 indexed vaultId,
        uint256 indexed positionId,
        uint256[] tokenIds,
        uint256[] amounts
    );
    event IncreasePosition(
        uint256 indexed vaultId,
        uint256 indexed positionId,
        uint256 amount
    );
    event CombinePositions(
        uint256 parentPositionId,
        uint256[] childPositionIds
    );
    event CollectWethFees(uint256 indexed positionId, uint256 wethAmount);
    event Withdraw(
        uint256 indexed positionId,
        uint256 vTokenShares,
        uint256 vTokenAmount,
        uint256 wethAmount
    );
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
    error InsufficientVTokens();

    // =============================================================
    //                           INIT
    // =============================================================

    function __NFTXInventoryStaking_init(
        uint256 timelock_,
        uint256 earlyWithdrawPenaltyInWei_,
        ITimelockExcludeList timelockExcludeList_,
        InventoryStakingDescriptor descriptor_
    ) external;

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    /**
     * @notice Deposits vToken to mint inventory staking xNFT position
     *
     * @param vaultId The id of the vault
     * @param amount Vault tokens amount to deposit
     * @param recipient Recipient address for the xNFT
     * @param encodedPermit2 Encoded function params (owner, permitSingle, signature) for `PERMIT2.permit()`
     * @param viaPermit2 If true then vTokens transferred via Permit2 else normal token transferFrom
     * @param forceTimelock Forcefully apply timelock to the position
     *
     * @return positionId The tokenId for the xNFT position
     */
    function deposit(
        uint256 vaultId,
        uint256 amount,
        address recipient,
        bytes calldata encodedPermit2,
        bool viaPermit2,
        bool forceTimelock
    ) external returns (uint256 positionId);

    /**
     * @notice Deposits NFT to mint inventory staking xNFT position
     *
     * @param vaultId The id of the vault corresponding to the NFT
     * @param tokenIds The token ids to deposit
     * @param amounts For ERC1155: quantity corresponding to each tokenId to deposit
     * @param recipient Recipient address for the xNFT
     *
     * @return positionId The tokenId for the xNFT position
     */
    function depositWithNFT(
        uint256 vaultId,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        address recipient
    ) external returns (uint256 positionId);

    /**
     * @notice Add more vTokens to an existing position (the position have been created with just vTokens)
     *
     * @param positionId The position to add vTokens into
     * @param amount Vault tokens amount to deposit
     * @param encodedPermit2 Encoded function params (owner, permitSingle, signature) for `PERMIT2.permit()`
     * @param viaPermit2 If true then vTokens transferred via Permit2 else normal token transferFrom
     * @param forceTimelock Forcefully apply timelock to the position
     */
    function increasePosition(
        uint256 positionId,
        uint256 amount,
        bytes calldata encodedPermit2,
        bool viaPermit2,
        bool forceTimelock
    ) external;

    /**
     * @notice Withdraw vault tokens from the position. Penalty is deducted if position has not finished the timelock.
     *
     * @param positionId The position id to withdraw vault tokens from
     * @param vTokenShares Amount of vault token shares to burn
     * @param nftIds NFT tokenIds to redeem with the vault tokens withdrawn. If array is empty then only vault tokens transferred. Redeem fees (in ETH from msg.value) only paid for positions which were minted with vTokens
     */
    function withdraw(
        uint256 positionId,
        uint256 vTokenShares,
        uint256[] calldata nftIds
    ) external payable;

    /**
     * @notice Combine underlying vToken and WETH balances from childPositions into parentPosition, if all of their timelocks ended. All positions must be for the same vault id.
     *
     * @param parentPositionId xNFT Position id that will receive the underlying balances from childPositions
     * @param childPositionIds Array of xNFT position ids to be combined
     */
    function combinePositions(
        uint256 parentPositionId,
        uint256[] calldata childPositionIds
    ) external;

    /**
     * @notice Receive WETH fees accumulated by multiple positions
     *
     * @param positionIds The positions to withdraw weth fees from
     */
    function collectWethFees(uint256[] calldata positionIds) external;

    /**
     * @dev Can only be called by feeDistributor. vToken rewards can be directly transferred to this contract without calling this function
     *
     * @param vaultId The vault id that should receive the rewards
     * @param wethAmount Amount of WETH to pull as rewards
     *
     * @return rewardsDistributed Returns false if the `totalVTokenShares` is zero for the given `vaultId`
     */
    function receiveWethRewards(
        uint256 vaultId,
        uint256 wethAmount
    ) external returns (bool rewardsDistributed);

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    function setTimelock(uint256 timelock_) external;

    function setEarlyWithdrawPenalty(
        uint256 earlyWithdrawPenaltyInWei_
    ) external;

    function setDescriptor(InventoryStakingDescriptor descriptor_) external;

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    /**
     * @notice Returns the worth of 10^18 vTokenShares in terms of the underlying vToken corresponding to the provided `vaultId`
     */
    function pricePerShareVToken(
        uint256 vaultId
    ) external view returns (uint256);

    /**
     * @notice Returns the current WETH balance for a given `positionId`
     */
    function wethBalance(uint256 positionId) external view returns (uint256);
}
