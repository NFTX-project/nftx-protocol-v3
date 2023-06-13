// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {ERC721PermitUpgradeable} from "@src/util/ERC721PermitUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {FixedPoint128} from "@uni-core/libraries/FixedPoint128.sol";
import {PausableUpgradeable} from "./util/PausableUpgradeable.sol";
import {TransferLib} from "@src/lib/TransferLib.sol";

import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";
import {INFTXVault} from "@src/v2/interface/INFTXVault.sol";
import {ITimelockExcludeList} from "@src/v2/interface/ITimelockExcludeList.sol";
import {INFTXFeeDistributorV3} from "./interfaces/INFTXFeeDistributorV3.sol";
import {INFTXInventoryStakingV3} from "./interfaces/INFTXInventoryStakingV3.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";

/**
 * @title NFTX Inventory Staking V3
 * @author @apoorvlathey
 *
 * @dev lockId's:
 * 0: deposit & depositWithPermit2
 * 1: depositWithNFT
 * 2: withdraw
 * 3: collectWethFees
 *
 * @notice Allows users to stake vTokens to earn fees in vTokens and WETH. The position is minted as xNFT.
 */

contract NFTXInventoryStakingV3Upgradeable is
    INFTXInventoryStakingV3,
    ERC721PermitUpgradeable,
    PausableUpgradeable
{
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    IERC20 public immutable override WETH;
    IPermitAllowanceTransfer public immutable override PERMIT2;
    INFTXVaultFactory public immutable override nftxVaultFactory;

    ITimelockExcludeList public override timelockExcludeList;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId = 1;

    /// @dev timelock in seconds
    uint256 public override timelock;
    /// @dev the max penalty applicable. The penalty goes down linearly as the `timelockedUntil` approaches
    uint256 public override earlyWithdrawPenaltyInWei;

    /// @dev The token ID position data
    mapping(uint256 => Position) public override positions;

    /// @dev vaultId => VaultGlobal
    mapping(uint256 => VaultGlobal) public override vaultGlobal;

    // =============================================================
    //                           INIT
    // =============================================================

    constructor(
        IERC20 WETH_,
        IPermitAllowanceTransfer PERMIT2_,
        INFTXVaultFactory nftxVaultFactory_
    ) {
        WETH = WETH_;
        PERMIT2 = PERMIT2_;
        nftxVaultFactory = nftxVaultFactory_;
    }

    function __NFTXInventoryStaking_init(
        uint256 timelock_,
        uint256 earlyWithdrawPenaltyInWei_,
        ITimelockExcludeList timelockExcludeList_
    ) external override initializer {
        __ERC721PermitUpgradeable_init("NFTX Inventory Staking", "xNFT", "1");
        __Pausable_init();

        if (timelock_ > 14 days) revert TimelockTooLong();
        if (earlyWithdrawPenaltyInWei_ > 1 ether)
            revert InvalidEarlyWithdrawPenalty();
        timelock = timelock_;
        earlyWithdrawPenaltyInWei = earlyWithdrawPenaltyInWei_;
        timelockExcludeList = timelockExcludeList_;
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    function deposit(
        uint256 vaultId,
        uint256 amount,
        address recipient
    ) external override returns (uint256 positionId) {
        address vToken = nftxVaultFactory.vault(vaultId);
        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];

        uint256 preVTokenBalance = _vaultGlobal.netVTokenBalance; // TODO: use balanceOf() instead of netVTokenBalance to account for tokens sent directly, like by MarketplaceZap
        IERC20(vToken).transferFrom(msg.sender, address(this), amount);

        return
            _deposit(
                vaultId,
                amount,
                recipient,
                _vaultGlobal,
                preVTokenBalance
            );
    }

    function depositWithPermit2(
        uint256 vaultId,
        uint256 amount,
        address recipient,
        bytes calldata encodedPermit2
    ) external override returns (uint256 positionId) {
        address vToken = nftxVaultFactory.vault(vaultId);
        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];

        uint256 preVTokenBalance = _vaultGlobal.netVTokenBalance; // TODO: use balanceOf() instead of netVTokenBalance to account for tokens sent directly, like by MarketplaceZap

        if (encodedPermit2.length > 0) {
            (
                address _owner,
                IPermitAllowanceTransfer.PermitSingle memory permitSingle,
                bytes memory signature
            ) = abi.decode(
                    encodedPermit2,
                    (address, IPermitAllowanceTransfer.PermitSingle, bytes)
                );

            PERMIT2.permit(_owner, permitSingle, signature);
        }

        PERMIT2.transferFrom(
            msg.sender,
            address(this),
            uint160(amount),
            address(vToken)
        );

        return
            _deposit(
                vaultId,
                amount,
                recipient,
                _vaultGlobal,
                preVTokenBalance
            );
    }

    function depositWithNFT(
        uint256 vaultId,
        uint256[] calldata tokenIds,
        address recipient
    ) external returns (uint256 positionId) {
        onlyOwnerIfPaused(1);

        address vToken = nftxVaultFactory.vault(vaultId);
        uint256 amount;
        {
            address assetAddress = INFTXVault(vToken).assetAddress();

            // transfer tokenIds from user directly to the vault
            TransferLib.transferFromERC721(
                assetAddress,
                address(vToken),
                tokenIds
            );

            // mint vTokens
            uint256[] memory emptyIds;
            amount = INFTXVault(vToken).mint(tokenIds, emptyIds) * 1 ether;
        }

        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];

        uint256 preVTokenBalance = _vaultGlobal.netVTokenBalance;
        _vaultGlobal.netVTokenBalance = preVTokenBalance + amount;

        _mint(recipient, (positionId = _nextId++));

        uint256 vTokenShares;
        if (_vaultGlobal.totalVTokenShares == 0) {
            vTokenShares = amount;
        } else {
            vTokenShares =
                (amount * _vaultGlobal.totalVTokenShares) /
                preVTokenBalance;
        }
        _vaultGlobal.totalVTokenShares += vTokenShares;

        positions[positionId] = Position({
            nonce: 0,
            vaultId: vaultId,
            timelockedUntil: timelockExcludeList.isExcluded(msg.sender, vaultId)
                ? 0
                : block.timestamp + timelock,
            vTokenShareBalance: vTokenShares,
            wethFeesPerVTokenShareSnapshotX128: _vaultGlobal
                .globalWethFeesPerVTokenShareX128,
            wethOwed: 0
        });

        emit DepositWithNFT(vaultId, positionId, amount);
    }

    function withdraw(
        uint256 positionId,
        uint256 vTokenShares,
        uint256[] calldata nftIds
    ) external override {
        onlyOwnerIfPaused(2);

        if (ownerOf(positionId) != msg.sender) revert NotPositionOwner();

        Position storage position = positions[positionId];

        uint256 positionVTokenShareBalance = position.vTokenShareBalance;
        require(positionVTokenShareBalance >= vTokenShares);

        uint256 vaultId = position.vaultId;
        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];
        // withdraw vTokens corresponding to the vTokenShares requested
        uint256 vTokenOwed = (_vaultGlobal.netVTokenBalance * vTokenShares) /
            _vaultGlobal.totalVTokenShares;
        // withdraw all the weth fees accrued
        uint256 wethOwed = _calcWethOwed(
            _vaultGlobal.globalWethFeesPerVTokenShareX128,
            position.wethFeesPerVTokenShareSnapshotX128,
            vTokenShares
        ) + position.wethOwed;
        position.wethFeesPerVTokenShareSnapshotX128 = _vaultGlobal
            .globalWethFeesPerVTokenShareX128;
        position.wethOwed = 0;

        if (block.timestamp <= position.timelockedUntil) {
            // Eg: timelock = 10 days, vTokenOwed = 100, penalty% = 5%
            // Case 1: Instant withdraw, with 10 days left
            // penaltyAmt = 100 * 5% = 5
            // Case 2: With 2 days timelock left
            // penaltyAmt = (100 * 5%) * 2 / 10 = 1
            uint256 vTokenPenalty = ((position.timelockedUntil -
                block.timestamp) *
                vTokenOwed *
                earlyWithdrawPenaltyInWei) / (timelock * 1 ether);
            vTokenOwed -= vTokenPenalty;
        }

        // in case of penalty, more shares are burned than the corresponding vToken balance
        // resulting in an increase of `pricePerShareVToken`, hence the penalty collected is distributed amongst other stakers
        _vaultGlobal.netVTokenBalance -= vTokenOwed;
        _vaultGlobal.totalVTokenShares -= vTokenShares;
        position.vTokenShareBalance -= vTokenShares;

        uint256 nftCount = nftIds.length;
        if (nftCount > 0) {
            // redeem is only available for positions which were/are under timelock (as redeem fee is avoided here)
            if (position.timelockedUntil == 0)
                revert RedeemNotAllowedWithoutTimelock();

            // check if we have sufficient vTokens
            uint256 requiredVTokens = nftCount * 1 ether;
            if (vTokenOwed < requiredVTokens) revert InsufficientVTokens();

            address vault = nftxVaultFactory.vault(vaultId);
            INFTXVault(vault).redeemTo(nftIds, msg.sender);

            // send vToken residue
            uint256 vTokenResidue = vTokenOwed - requiredVTokens;
            if (vTokenResidue > 0) {
                IERC20(vault).transfer(msg.sender, vTokenResidue);
            }
        } else {
            // transfer tokens to the user
            IERC20(nftxVaultFactory.vault(vaultId)).transfer(
                msg.sender,
                vTokenOwed
            );
        }
        WETH.transfer(msg.sender, wethOwed);

        emit Withdraw(positionId, vTokenShares, vTokenOwed, wethOwed);
    }

    // combine multiple xNFTs (if timelock expired)
    function combinePositions(
        uint256 parentPositionId,
        uint256[] calldata childPositionIds
    ) external override {
        // `ownerOf` handles invalid positionId
        if (ownerOf(parentPositionId) != msg.sender) revert NotPositionOwner();
        Position storage parentPosition = positions[parentPositionId];
        uint256 parentVaultId = parentPosition.vaultId;

        VaultGlobal storage _vaultGlobal = vaultGlobal[parentVaultId];

        if (block.timestamp <= parentPosition.timelockedUntil)
            revert Timelocked();

        // weth owed for the parent position
        uint256 netWethOwed = _calcWethOwed(
            _vaultGlobal.globalWethFeesPerVTokenShareX128,
            parentPosition.wethFeesPerVTokenShareSnapshotX128,
            parentPosition.vTokenShareBalance
        );
        uint256 childrenPositionsCount = childPositionIds.length;
        for (uint256 i; i < childrenPositionsCount; ) {
            if (childPositionIds[i] == parentPositionId)
                revert ParentChildSame();
            // `ownerOf` handles invalid positionId
            if (ownerOf(childPositionIds[i]) != msg.sender)
                revert NotPositionOwner();

            Position storage childPosition = positions[childPositionIds[i]];
            if (block.timestamp <= childPosition.timelockedUntil)
                revert Timelocked();
            if (childPosition.vaultId != parentVaultId)
                revert VaultIdMismatch();

            // add weth owed for this child position
            netWethOwed +=
                _calcWethOwed(
                    _vaultGlobal.globalWethFeesPerVTokenShareX128,
                    childPosition.wethFeesPerVTokenShareSnapshotX128,
                    childPosition.vTokenShareBalance
                ) +
                childPosition.wethOwed;
            // transfer vToken share balance to parent position
            parentPosition.vTokenShareBalance += childPosition
                .vTokenShareBalance;
            childPosition.vTokenShareBalance = 0;
            childPosition.wethOwed = 0;

            unchecked {
                ++i;
            }
        }

        // set new wethFeesPerVTokenShare snapshot
        parentPosition.wethFeesPerVTokenShareSnapshotX128 = _vaultGlobal
            .globalWethFeesPerVTokenShareX128;

        // add net wethOwed to the parent position
        parentPosition.wethOwed += netWethOwed;
    }

    function collectWethFees(uint256 positionId) external override {
        onlyOwnerIfPaused(3);

        if (ownerOf(positionId) != msg.sender) revert NotPositionOwner();

        Position storage position = positions[positionId];
        VaultGlobal storage _vaultGlobal = vaultGlobal[position.vaultId];
        uint256 wethOwed = _calcWethOwed(
            _vaultGlobal.globalWethFeesPerVTokenShareX128,
            position.wethFeesPerVTokenShareSnapshotX128,
            position.vTokenShareBalance
        ) + position.wethOwed;
        position.wethFeesPerVTokenShareSnapshotX128 = _vaultGlobal
            .globalWethFeesPerVTokenShareX128;
        position.wethOwed = 0;

        WETH.transfer(msg.sender, wethOwed);

        emit CollectWethFees(positionId, wethOwed);
    }

    /// @dev Can only be called by feeDistributor, after it sends the reward tokens to this contract
    function receiveRewards(
        uint256 vaultId,
        uint256 amount,
        bool isRewardWeth
    ) external override returns (bool rewardsDistributed) {
        require(msg.sender == nftxVaultFactory.feeDistributor());

        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];
        if (_vaultGlobal.totalVTokenShares == 0) {
            return false;
        }
        rewardsDistributed = true;

        if (isRewardWeth) {
            WETH.transferFrom(msg.sender, address(this), amount);
            _vaultGlobal.globalWethFeesPerVTokenShareX128 += FullMath.mulDiv(
                amount,
                FixedPoint128.Q128,
                _vaultGlobal.totalVTokenShares
            );
        } else {
            // TODO: if reward is vToken, and we removed netVTokenBalance then the logic below can be removed and the sender can directly transfer vTokens without calling any functions here
            address vToken = nftxVaultFactory.vault(vaultId);
            IERC20(vToken).transferFrom(msg.sender, address(this), amount);
            _vaultGlobal.netVTokenBalance += amount;
        }
    }

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    function setTimelock(uint256 timelock_) external override onlyOwner {
        if (timelock_ > 14 days) revert TimelockTooLong();

        timelock = timelock_;
        emit UpdateTimelock(timelock_);
    }

    function setEarlyWithdrawPenalty(
        uint256 earlyWithdrawPenaltyInWei_
    ) external override onlyOwner {
        if (earlyWithdrawPenaltyInWei_ > 1 ether)
            revert InvalidEarlyWithdrawPenalty();

        earlyWithdrawPenaltyInWei = earlyWithdrawPenaltyInWei_;
        emit UpdateEarlyWithdrawPenalty(earlyWithdrawPenaltyInWei_);
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    function pricePerShareVToken(
        uint256 vaultId
    ) external view returns (uint256) {
        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];
        return
            (_vaultGlobal.netVTokenBalance * 1 ether) /
            _vaultGlobal.totalVTokenShares;
    }

    // TODO: add tokenURI for these xNFTs

    // =============================================================
    //                        INTERNAL HELPERS
    // =============================================================

    function _deposit(
        uint256 vaultId,
        uint256 amount,
        address recipient,
        VaultGlobal storage _vaultGlobal,
        uint256 preVTokenBalance
    ) internal returns (uint256 positionId) {
        onlyOwnerIfPaused(0);

        _vaultGlobal.netVTokenBalance = preVTokenBalance + amount;

        _mint(recipient, (positionId = _nextId++));

        uint256 vTokenShares;
        if (_vaultGlobal.totalVTokenShares == 0) {
            vTokenShares = amount;
        } else {
            vTokenShares =
                (amount * _vaultGlobal.totalVTokenShares) /
                preVTokenBalance;
        }
        _vaultGlobal.totalVTokenShares += vTokenShares;

        positions[positionId] = Position({
            nonce: 0,
            vaultId: vaultId,
            timelockedUntil: 0,
            vTokenShareBalance: vTokenShares,
            wethFeesPerVTokenShareSnapshotX128: _vaultGlobal
                .globalWethFeesPerVTokenShareX128,
            wethOwed: 0
        });

        emit Deposit(vaultId, positionId, amount);
    }

    function _calcWethOwed(
        uint256 globalWethFeesPerVTokenShareX128,
        uint256 positionWethFeesPerVTokenShareSnapshotX128,
        uint256 positionVTokenShareBalance
    ) internal pure returns (uint256 wethOwed) {
        wethOwed = FullMath.mulDiv(
            globalWethFeesPerVTokenShareX128 -
                positionWethFeesPerVTokenShareSnapshotX128,
            positionVTokenShareBalance,
            FixedPoint128.Q128
        );
    }

    function _getAndIncrementNonce(
        uint256 tokenId
    ) internal override returns (uint256) {
        return uint256(positions[tokenId].nonce++);
    }
}
