// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IBeacon} from "@src/custom/proxy/IBeacon.sol";

interface INFTXVaultFactoryV3 is IBeacon {
    // =============================================================
    //                            STRUCTS
    // =============================================================

    struct VaultFees {
        bool active;
        uint64 mintFee;
        uint64 redeemFee;
        uint64 swapFee;
    }

    // =============================================================
    //                            VARIABLES
    // =============================================================

    function feeDistributor() external view returns (address);

    function eligibilityManager() external view returns (address);

    function excludedFromFees(address addr) external view returns (bool);

    function factoryMintFee() external view returns (uint64);

    function factoryRedeemFee() external view returns (uint64);

    function factorySwapFee() external view returns (uint64);

    function twapInterval() external view returns (uint32);

    function premiumDuration() external view returns (uint256);

    function premiumMax() external view returns (uint256);

    function depositorPremiumShare() external view returns (uint256);

    // =============================================================
    //                            EVENTS
    // =============================================================

    event NewFeeDistributor(address oldDistributor, address newDistributor);
    event NewZapContract(address oldZap, address newZap);
    event UpdatedZapContract(address zap, bool excluded);
    event FeeExclusion(address feeExcluded, bool excluded);
    event NewEligibilityManager(address oldEligManager, address newEligManager);
    event NewVault(
        uint256 indexed vaultId,
        address vaultAddress,
        address assetAddress
    );
    event UpdateVaultFees(
        uint256 vaultId,
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    );
    event DisableVaultFees(uint256 vaultId);
    event UpdateFactoryFees(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    );

    // =============================================================
    //                            ERRORS
    // =============================================================

    error FeeDistributorNotSet();
    error VaultImplementationNotSet();
    error FeeExceedsLimit();
    error CallerIsNotVault();

    // =============================================================
    //                           INIT
    // =============================================================

    function __NFTXVaultFactory_init(address vaultImpl) external;

    // =============================================================
    //                     ONLY PRIVILEGED WRITE
    // =============================================================

    function setFactoryFees(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    ) external;

    function setVaultFees(
        uint256 vaultId,
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    ) external;

    function disableVaultFees(uint256 vaultId) external;

    function setFeeDistributor(address feeDistributor_) external;

    function setFeeExclusion(address excludedAddr, bool excluded) external;

    function setEligibilityManager(address eligibilityManager_) external;

    function setTwapInterval(uint32 twapInterval_) external;

    function setPremiumDuration(uint256 premiumDuration_) external;

    function setPremiumMax(uint256 premiumMax_) external;

    function setDepositorPremiumShare(uint256 depositorPremiumShare_) external;

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    function createVault(
        string calldata name,
        string calldata symbol,
        address assetAddress,
        bool is1155,
        bool allowAllItems
    ) external returns (uint256 vaultId);

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    function vaultFees(
        uint256 vaultId
    )
        external
        view
        returns (uint256 mintFee, uint256 redeemFee, uint256 swapFee);

    function isLocked(uint256 id) external view returns (bool);

    function vaultsForAsset(
        address asset
    ) external view returns (address[] memory);

    function allVaults() external view returns (address[] memory);

    function numVaults() external view returns (uint256);

    function vault(uint256 vaultId) external view returns (address);
}
