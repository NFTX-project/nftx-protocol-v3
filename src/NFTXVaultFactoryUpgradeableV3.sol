// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {UpgradeableBeacon} from "@src/custom/proxy/UpgradeableBeacon.sol";
import {PausableUpgradeable} from "@src/custom/PausableUpgradeable.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {NFTXVaultUpgradeableV3} from "@src/NFTXVaultUpgradeableV3.sol";

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";

// Authors: @0xKiwi_, @alexgausman and @apoorvlathey

contract NFTXVaultFactoryUpgradeableV3 is
    INFTXVaultFactoryV3,
    PausableUpgradeable,
    UpgradeableBeacon
{
    // =============================================================
    //                            VARIABLES
    // =============================================================

    address public override feeDistributor;
    address public override eligibilityManager;

    mapping(address => address[]) internal _vaultsForAsset;

    address[] internal _vaults;

    mapping(address => bool) public override excludedFromFees;

    mapping(uint256 => VaultFees) internal _vaultFees;

    uint64 public override factoryMintFee;
    uint64 public override factoryRedeemFee;
    uint64 public override factorySwapFee;

    uint32 public override twapInterval;
    // time during which a deposited tokenId incurs premium during withdrawal from the vault
    uint256 public override premiumDuration;
    // max premium value in vTokens when NFT just deposited
    uint256 public override premiumMax;
    // fraction in wei, what portion of the premium to send to the NFT depositor
    uint256 public override depositorPremiumShare;

    // =============================================================
    //                           INIT
    // =============================================================

    function __NFTXVaultFactory_init(
        address vaultImpl
    ) public override initializer {
        __Pausable_init();
        // We use a beacon proxy so that every child contract follows the same implementation code.
        __UpgradeableBeacon__init(vaultImpl);
        setFactoryFees(0.1 ether, 0.1 ether, 0.1 ether);
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    function createVault(
        string memory name,
        string memory symbol,
        address assetAddress,
        bool is1155,
        bool allowAllItems
    ) external override returns (uint256 vaultId) {
        onlyOwnerIfPaused(0);

        if (feeDistributor == address(0)) revert FeeDistributorNotSet();
        if (implementation() == address(0)) revert VaultImplementationNotSet();

        address vaultAddr = _deployVault(
            name,
            symbol,
            assetAddress,
            is1155,
            allowAllItems
        );

        vaultId = _vaults.length;
        _vaultsForAsset[assetAddress].push(vaultAddr);
        _vaults.push(vaultAddr);

        emit NewVault(vaultId, vaultAddr, assetAddress);
    }

    // =============================================================
    //                     ONLY PRIVILEGED WRITE
    // =============================================================

    function setFactoryFees(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    ) public override onlyOwner {
        if (mintFee > 0.5 ether) revert FeeExceedsLimit();
        if (redeemFee > 0.5 ether) revert FeeExceedsLimit();
        if (swapFee > 0.5 ether) revert FeeExceedsLimit();

        factoryMintFee = uint64(mintFee);
        factoryRedeemFee = uint64(redeemFee);
        factorySwapFee = uint64(swapFee);

        emit UpdateFactoryFees(mintFee, redeemFee, swapFee);
    }

    function setVaultFees(
        uint256 vaultId,
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    ) external override {
        if (msg.sender != owner()) {
            address vaultAddr = _vaults[vaultId];
            if (msg.sender != vaultAddr) revert CallerIsNotVault();
        }
        if (mintFee > 0.5 ether) revert FeeExceedsLimit();
        if (redeemFee > 0.5 ether) revert FeeExceedsLimit();
        if (swapFee > 0.5 ether) revert FeeExceedsLimit();

        _vaultFees[vaultId] = VaultFees(
            true,
            uint64(mintFee),
            uint64(redeemFee),
            uint64(swapFee)
        );
        emit UpdateVaultFees(vaultId, mintFee, redeemFee, swapFee);
    }

    function disableVaultFees(uint256 vaultId) external override {
        if (msg.sender != owner()) {
            address vaultAddr = _vaults[vaultId];
            if (msg.sender != vaultAddr) revert CallerIsNotVault();
        }
        delete _vaultFees[vaultId];
        emit DisableVaultFees(vaultId);
    }

    function setFeeDistributor(
        address feeDistributor_
    ) external override onlyOwner {
        require(feeDistributor_ != address(0));
        emit NewFeeDistributor(feeDistributor, feeDistributor_);
        feeDistributor = feeDistributor_;
    }

    function setFeeExclusion(
        address excludedAddr,
        bool excluded
    ) external override onlyOwner {
        excludedFromFees[excludedAddr] = excluded;
        emit FeeExclusion(excludedAddr, excluded);
    }

    function setEligibilityManager(
        address eligibilityManager_
    ) external override onlyOwner {
        emit NewEligibilityManager(eligibilityManager, eligibilityManager_);
        eligibilityManager = eligibilityManager_;
    }

    function setTwapInterval(uint32 twapInterval_) external override onlyOwner {
        twapInterval = twapInterval_;
    }

    function setPremiumDuration(
        uint256 premiumDuration_
    ) external override onlyOwner {
        premiumDuration = premiumDuration_;
    }

    function setPremiumMax(uint256 premiumMax_) external override onlyOwner {
        premiumMax = premiumMax_;
    }

    function setDepositorPremiumShare(
        uint256 depositorPremiumShare_
    ) external override onlyOwner {
        depositorPremiumShare = depositorPremiumShare_;
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    function vaultFees(
        uint256 vaultId
    )
        external
        view
        override
        returns (uint256 mintFee, uint256 redeemFee, uint256 swapFee)
    {
        VaultFees memory fees = _vaultFees[vaultId];
        if (fees.active) {
            return (
                uint256(fees.mintFee),
                uint256(fees.redeemFee),
                uint256(fees.swapFee)
            );
        }

        return (
            uint256(factoryMintFee),
            uint256(factoryRedeemFee),
            uint256(factorySwapFee)
        );
    }

    function isLocked(uint256 lockId) external view override returns (bool) {
        return isPaused[lockId];
    }

    function vaultsForAsset(
        address assetAddress
    ) external view override returns (address[] memory) {
        return _vaultsForAsset[assetAddress];
    }

    function allVaults() external view override returns (address[] memory) {
        return _vaults;
    }

    function numVaults() external view override returns (uint256) {
        return _vaults.length;
    }

    function vault(uint256 vaultId) external view override returns (address) {
        return _vaults[vaultId];
    }

    // =============================================================
    //                        INTERNAL HELPERS
    // =============================================================

    function _deployVault(
        string memory name,
        string memory symbol,
        address assetAddress,
        bool is1155,
        bool allowAllItems
    ) internal returns (address) {
        address newBeaconProxy = address(new BeaconProxy(address(this), ""));
        NFTXVaultUpgradeableV3(newBeaconProxy).__NFTXVault_init(
            name,
            symbol,
            assetAddress,
            is1155,
            allowAllItems
        );
        // Manager for configuration.
        NFTXVaultUpgradeableV3(newBeaconProxy).setManager(msg.sender);
        // Owner for administrative functions.
        NFTXVaultUpgradeableV3(newBeaconProxy).transferOwnership(owner());
        return newBeaconProxy;
    }
}
