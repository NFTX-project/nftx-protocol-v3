// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {ERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {FixedPoint128} from "@uni-core/libraries/FixedPoint128.sol";
import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";

import {INFTXFeeDistributorV3} from "./interfaces/INFTXFeeDistributorV3.sol";

/**
 * @title NFTX Inventory Staking V3
 * @author @apoorvlathey
 *
 * @notice Allows users to stake vTokens to earn fees in vTokens and WETH. The position is minted as xNFT.
 */

contract NFTXInventoryStakingV3Upgradeable is
    INFTXFeeDistributorV3,
    ERC721Upgradeable,
    OwnableUpgradeable
{
    // details about the staking position
    struct Position {
        // the nonce for permits
        uint256 nonce; // TODO: add permit logic
        // vaultId corresponding to the vTokens staked in this position
        uint256 vaultId;
        // the vTokenAmount staked
        uint256 vTokenAmount;
        // timestamp at which this position was minted
        uint256 mintTimestamp;
        // the fee growth of the aggregate position as of the last action on the individual position
        uint256 feeGrowthInsideVTokenLastX128;
        uint256 feeGrowthInsideWETHLastX128;
    }

    struct VaultGlobal {
        uint256 feeGrowthGlobalVTokenX128;
        uint256 feeGrowthGlobalWETHX128;
        uint256 totalVTokenAmount;
    }

    INFTXVaultFactory public override nftxVaultFactory;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId = 1;

    /// @dev The token ID position data
    mapping(uint256 => Position) public positions;

    /// @dev vaultId => VaultGlobal
    mapping(uint256 => VaultGlobal) public vaultGlobal;

    // =============================================================
    //                           INIT
    // =============================================================

    function __NFTXInventoryStaking_init(
        INFTXVaultFactory nftxVaultFactory_
    ) external initializer {
        // TODO: finalize token name and symbol
        __ERC721_init("NFTX Inventory Staking", "xNFT");
        __Ownable_init();

        nftxVaultFactory = nftxVaultFactory_;
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    function deposit(
        uint256 vaultId,
        uint256 amount,
        address recipient
    ) external returns (uint256 tokenId) {
        // TODO: onlyOwnerIfPaused(10)

        address vToken = nftxVaultFactory.vault(vaultId);
        IERC20(vToken).transferFrom(msg.sender, address(this), amount);

        _mint(recipient, (tokenId = _nextId++));

        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];
        _vaultGlobal.totalVTokenAmount += amount;
        positions[tokenId] = Position({
            nonce: 0,
            vaultId: vaultId,
            vTokenAmount: amount,
            mintTimestamp: block.timestamp,
            feeGrowthInsideVTokenLastX128: _vaultGlobal
                .feeGrowthGlobalVTokenX128,
            feeGrowthInsideWETHLastX128: _vaultGlobal.feeGrowthGlobalWETHX128
        });

        //TODO: emit Deposit event
    }

    function withdraw(uint256 positionId, uint256 amount) external {
        require(amount > 0);
        Position storage position = positions[positionId];

        uint256 positionVTokenAmount = position.vTokenAmount;
        require(positionVTokenAmount >= amount);
    }

    /// @dev Can only be called by feeDistributor, after it sends the reward tokens to this contract
    function receiveRewards(
        uint256 vaultId,
        uint256 amount,
        bool isRewardWeth
    ) external returns (bool) {
        require(msg.sender == nftxVaultFactory.feeDistributor());

        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];
        require(_vaultGlobal.totalVTokenAmount > 0);

        uint256 feeGrowthGlobalX128 = isRewardWeth
            ? _vaultGlobal.feeGrowthGlobalWETHX128
            : _vaultGlobal.feeGrowthGlobalVTokenX128;

        unchecked {
            feeGrowthGlobalX128 += FullMath.mulDiv(
                amount,
                FixedPoint128.Q128,
                _vaultGlobal.totalVTokenAmount
            );
        }

        if (isRewardWeth) {
            _vaultGlobal.feeGrowthGlobalWETHX128 = feeGrowthGlobalX128;
        } else {
            _vaultGlobal.feeGrowthGlobalVTokenX128 = feeGrowthGlobalX128;
        }
    }
}
