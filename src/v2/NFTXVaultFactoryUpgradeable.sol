// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./util/PausableUpgradeable.sol";
import "./proxy/UpgradeableBeacon.sol";
import "./proxy/BeaconProxy.sol";
import "./interface/INFTXVaultFactory.sol";
import "./interface/INFTXFeeDistributor.sol";
import "./NFTXVaultUpgradeable.sol";

// Authors: @0xKiwi_, @alexgausman and @apoorvlathey

contract NFTXVaultFactoryUpgradeable is
    PausableUpgradeable,
    UpgradeableBeacon,
    INFTXVaultFactory
{
    uint256 private NOT_USED1; // Removed, no longer needed.
    address public override zapContract; // No longer needed, but keeping for compatibility.
    address public override feeDistributor;
    address public override eligibilityManager;

    mapping(uint256 => address) private NOT_USED3; // Removed, no longer needed.
    mapping(address => address[]) _vaultsForAsset;

    address[] internal vaults;

    // v1.0.1
    mapping(address => bool) public override excludedFromFees;

    // v1.0.2
    struct VaultFees {
        bool active;
        uint64 mintFee;
        uint64 NOT_USED4; // Removed, no longer needed.
        uint64 targetRedeemFee;
        uint64 NOT_USED5; // Removed, no longer needed.
        uint64 targetSwapFee;
    }
    mapping(uint256 => VaultFees) private _vaultFees;
    uint64 public override factoryMintFee;
    uint64 private NOT_USED6; // Removed, no longer needed.
    uint64 public override factoryTargetRedeemFee;
    uint64 private NOT_USED7; // Removed, no longer needed.
    uint64 public override factoryTargetSwapFee;

    // v1.0.3
    mapping(address => bool) public override zapContracts;

    uint32 public override twapInterval;
    // time during which a deposited tokenId incurs premium during withdrawal from the vault
    uint256 public override premiumDuration;
    // max premium value in vTokens when NFT just deposited
    uint256 public override premiumMax;
    // fraction in wei, what portion of the premium to send to the NFT depositor
    uint256 public override depositorPremiumShare;

    function __NFTXVaultFactory_init(
        address _vaultImpl
    ) public override initializer {
        __Pausable_init();
        // We use a beacon proxy so that every child contract follows the same implementation code.
        __UpgradeableBeacon__init(_vaultImpl);
        setFactoryFees(0.1 ether, 0.1 ether, 0.1 ether);
    }

    function createVault(
        string memory name,
        string memory symbol,
        address _assetAddress,
        bool is1155,
        bool allowAllItems
    ) external virtual override returns (uint256) {
        onlyOwnerIfPaused(0);
        require(feeDistributor != address(0), "NFTX: Fee receiver unset");
        require(
            childImplementation() != address(0),
            "NFTX: Vault implementation unset"
        );
        address vaultAddr = deployVault(
            name,
            symbol,
            _assetAddress,
            is1155,
            allowAllItems
        );
        uint256 _vaultId = vaults.length;
        _vaultsForAsset[_assetAddress].push(vaultAddr);
        vaults.push(vaultAddr);

        emit NewVault(_vaultId, vaultAddr, _assetAddress);
        return _vaultId;
    }

    function setFactoryFees(
        uint256 mintFee,
        uint256 targetRedeemFee,
        uint256 targetSwapFee
    ) public virtual override onlyOwner {
        require(mintFee <= 0.5 ether, "Cannot > 0.5 ether");
        require(targetRedeemFee <= 0.5 ether, "Cannot > 0.5 ether");
        require(targetSwapFee <= 0.5 ether, "Cannot > 0.5 ether");

        factoryMintFee = uint64(mintFee);
        factoryTargetRedeemFee = uint64(targetRedeemFee);
        factoryTargetSwapFee = uint64(targetSwapFee);

        emit UpdateFactoryFees(mintFee, targetRedeemFee, targetSwapFee);
    }

    function setVaultFees(
        uint256 vaultId,
        uint256 mintFee,
        uint256 targetRedeemFee,
        uint256 targetSwapFee
    ) public virtual override {
        if (msg.sender != owner()) {
            address vaultAddr = vaults[vaultId];
            require(msg.sender == vaultAddr, "Not from vault");
        }
        require(mintFee <= 0.5 ether, "Cannot > 0.5 ether");
        require(targetRedeemFee <= 0.5 ether, "Cannot > 0.5 ether");
        require(targetSwapFee <= 0.5 ether, "Cannot > 0.5 ether");

        _vaultFees[vaultId] = VaultFees(
            true,
            uint64(mintFee),
            0,
            uint64(targetRedeemFee),
            0,
            uint64(targetSwapFee)
        );
        emit UpdateVaultFees(vaultId, mintFee, targetRedeemFee, targetSwapFee);
    }

    function disableVaultFees(uint256 vaultId) public virtual override {
        if (msg.sender != owner()) {
            address vaultAddr = vaults[vaultId];
            require(msg.sender == vaultAddr, "Not vault");
        }
        delete _vaultFees[vaultId];
        emit DisableVaultFees(vaultId);
    }

    function setFeeDistributor(
        address _feeDistributor
    ) public virtual override onlyOwner {
        require(_feeDistributor != address(0));
        emit NewFeeDistributor(feeDistributor, _feeDistributor);
        feeDistributor = _feeDistributor;
    }

    function setZapContract(
        address _zapContract,
        bool _excluded
    ) public virtual override onlyOwner {
        emit UpdatedZapContract(_zapContract, _excluded);
        zapContracts[_zapContract] = _excluded;
    }

    function setFeeExclusion(
        address _excludedAddr,
        bool excluded
    ) public virtual override onlyOwner {
        emit FeeExclusion(_excludedAddr, excluded);
        excludedFromFees[_excludedAddr] = excluded;
    }

    function setEligibilityManager(
        address _eligibilityManager
    ) external virtual override onlyOwner {
        emit NewEligibilityManager(eligibilityManager, _eligibilityManager);
        eligibilityManager = _eligibilityManager;
    }

    function setTwapInterval(
        uint32 twapInterval_
    ) external virtual override onlyOwner {
        twapInterval = twapInterval_;
    }

    function setPremiumDuration(
        uint256 premiumDuration_
    ) external virtual override onlyOwner {
        premiumDuration = premiumDuration_;
    }

    function setPremiumMax(
        uint256 premiumMax_
    ) external virtual override onlyOwner {
        premiumMax = premiumMax_;
    }

    function setDepositorPremiumShare(
        uint256 depositorPremiumShare_
    ) external virtual override onlyOwner {
        depositorPremiumShare = depositorPremiumShare_;
    }

    function vaultFees(
        uint256 vaultId
    ) external view virtual override returns (uint256, uint256, uint256) {
        VaultFees memory fees = _vaultFees[vaultId];
        if (fees.active) {
            return (
                uint256(fees.mintFee),
                uint256(fees.targetRedeemFee),
                uint256(fees.targetSwapFee)
            );
        }

        return (
            uint256(factoryMintFee),
            uint256(factoryTargetRedeemFee),
            uint256(factoryTargetSwapFee)
        );
    }

    function isLocked(
        uint256 lockId
    ) external view virtual override returns (bool) {
        return isPaused[lockId];
    }

    function vaultsForAsset(
        address assetAddress
    ) external view virtual override returns (address[] memory) {
        return _vaultsForAsset[assetAddress];
    }

    function vault(
        uint256 vaultId
    ) external view virtual override returns (address) {
        return vaults[vaultId];
    }

    function allVaults()
        external
        view
        virtual
        override
        returns (address[] memory)
    {
        return vaults;
    }

    function numVaults() external view virtual override returns (uint256) {
        return vaults.length;
    }

    function deployVault(
        string memory name,
        string memory symbol,
        address _assetAddress,
        bool is1155,
        bool allowAllItems
    ) internal returns (address) {
        address newBeaconProxy = address(new BeaconProxy(address(this), ""));
        NFTXVaultUpgradeable(newBeaconProxy).__NFTXVault_init(
            name,
            symbol,
            _assetAddress,
            is1155,
            allowAllItems
        );
        // Manager for configuration.
        NFTXVaultUpgradeable(newBeaconProxy).setManager(msg.sender);
        // Owner for administrative functions.
        NFTXVaultUpgradeable(newBeaconProxy).transferOwnership(owner());
        return newBeaconProxy;
    }
}
