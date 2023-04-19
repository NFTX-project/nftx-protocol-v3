// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {ERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {FixedPoint128} from "@uni-core/libraries/FixedPoint128.sol";
import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";

import {INFTXFeeDistributorV3} from "./interfaces/INFTXFeeDistributorV3.sol";
import {INFTXInventoryStakingV3} from "./interfaces/INFTXInventoryStakingV3.sol";

/**
 * @title NFTX Inventory Staking V3
 * @author @apoorvlathey
 *
 * @dev lockId's:
 * 0: deposit
 * 1: withdraw
 * 2: collectWethFees
 * 3: receiveRewards
 *
 * @notice Allows users to stake vTokens to earn fees in vTokens and WETH. The position is minted as xNFT.
 */

contract NFTXInventoryStakingV3Upgradeable is
    INFTXInventoryStakingV3,
    ERC721Upgradeable,
    PausableUpgradeable
{
    // details about the staking position
    struct Position {
        // the nonce for permits
        uint256 nonce; // TODO: add permit logic
        // vaultId corresponding to the vTokens staked in this position
        uint256 vaultId;
        // the vToken amount staked
        uint256 vTokenLiquidity;
        // timestamp at which this position was minted
        uint256 mintTimestamp;
        // shares balance is used to track position's ownership of total vToken balance
        uint256 vTokenShareBalance;
        // used to evaluate weth fees accumulated per vTokenShare since this snapshot
        uint256 wethFeesPerVTokenShareSnapshotX128;
    }

    struct VaultGlobal {
        uint256 netVTokenBalance; // vToken liquidity + earned fees
        uint256 totalVTokenShares;
        uint256 globalWethFeesPerVTokenShareX128;
    }

    INFTXVaultFactory public override nftxVaultFactory;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId = 1;

    IERC20 public WETH;

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
        __Pausable_init();

        nftxVaultFactory = nftxVaultFactory_;
        WETH = INFTXFeeDistributorV3(nftxVaultFactory_.feeDistributor()).WETH();
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    function deposit(
        uint256 vaultId,
        uint256 amount,
        address recipient
    ) external returns (uint256 tokenId) {
        onlyOwnerIfPaused(0);

        address vToken = nftxVaultFactory.vault(vaultId);
        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];

        uint256 preVTokenBalance = _vaultGlobal.netVTokenBalance;
        IERC20(vToken).transferFrom(msg.sender, address(this), amount);
        _vaultGlobal.netVTokenBalance = preVTokenBalance + amount;

        _mint(recipient, (tokenId = _nextId++));

        uint256 vTokenShares;
        if (_vaultGlobal.totalVTokenShares == 0) {
            vTokenShares = amount;
        } else {
            vTokenShares =
                (amount * _vaultGlobal.totalVTokenShares) /
                preVTokenBalance;
        }
        _vaultGlobal.totalVTokenShares += vTokenShares;

        positions[tokenId] = Position({
            nonce: 0,
            vaultId: vaultId,
            vTokenLiquidity: amount,
            mintTimestamp: block.timestamp,
            vTokenShareBalance: vTokenShares,
            wethFeesPerVTokenShareSnapshotX128: _vaultGlobal
                .globalWethFeesPerVTokenShareX128
        });

        //TODO: emit Deposit event
    }

    // TODO: verify redeem timelock and impose penalty if required
    // TODO: distribute penalty to other inventory stakers
    function withdraw(uint256 positionId, uint256 vTokenShares) external {
        onlyOwnerIfPaused(1);

        Position storage position = positions[positionId];

        uint256 positionvTokenShareBalance = position.vTokenShareBalance;
        require(positionvTokenShareBalance >= vTokenShares);

        uint256 vaultId = position.vaultId;
        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];
        // withdraw vTokens corresponding to the vTokenShares requested
        uint256 vTokenOwed = (_vaultGlobal.netVTokenBalance * vTokenShares) /
            _vaultGlobal.totalVTokenShares;
        // withdraw all the weth fees accrued
        uint256 wethOwed = FullMath.mulDiv(
            _vaultGlobal.globalWethFeesPerVTokenShareX128 -
                position.wethFeesPerVTokenShareSnapshotX128,
            positionvTokenShareBalance,
            FixedPoint128.Q128
        );
        position.wethFeesPerVTokenShareSnapshotX128 = _vaultGlobal
            .globalWethFeesPerVTokenShareX128;

        // transfer tokens to the user
        IERC20(nftxVaultFactory.vault(vaultId)).transfer(
            msg.sender,
            vTokenOwed
        );
        WETH.transfer(msg.sender, wethOwed);

        // TODO: emit withdraw event
    }

    function collectWethFees(uint256 positionId) external {
        onlyOwnerIfPaused(2);

        Position storage position = positions[positionId];
        uint256 positionvTokenShareBalance = position.vTokenShareBalance;
        VaultGlobal storage _vaultGlobal = vaultGlobal[position.vaultId];
        uint256 wethOwed = FullMath.mulDiv(
            _vaultGlobal.globalWethFeesPerVTokenShareX128 -
                position.wethFeesPerVTokenShareSnapshotX128,
            positionvTokenShareBalance,
            FixedPoint128.Q128
        );
        position.wethFeesPerVTokenShareSnapshotX128 = _vaultGlobal
            .globalWethFeesPerVTokenShareX128;

        WETH.transfer(msg.sender, wethOwed);

        // TODO: emit collect event
    }

    /// @dev Can only be called by feeDistributor, after it sends the reward tokens to this contract
    function receiveRewards(
        uint256 vaultId,
        uint256 amount,
        bool isRewardWeth
    ) external returns (bool rewardsDistributed) {
        onlyOwnerIfPaused(3);
        require(msg.sender == nftxVaultFactory.feeDistributor());

        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];
        if (_vaultGlobal.totalVTokenShares == 0) {
            return false;
        }
        rewardsDistributed = true;
        WETH.transferFrom(msg.sender, address(this), amount);

        if (isRewardWeth) {
            _vaultGlobal.globalWethFeesPerVTokenShareX128 += FullMath.mulDiv(
                amount,
                FixedPoint128.Q128,
                _vaultGlobal.totalVTokenShares
            );
        } else {
            _vaultGlobal.netVTokenBalance += amount;
        }
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    // TODO: add ability to combine multiple xNFTs (if timelock expired)

    function pricePerShareVToken(
        uint256 vaultId
    ) external view returns (uint256) {
        VaultGlobal storage _vaultGlobal = vaultGlobal[vaultId];
        return
            (_vaultGlobal.netVTokenBalance * 1 ether) /
            _vaultGlobal.totalVTokenShares;
    }
}
