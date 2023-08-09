// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

// inheriting
import {UpgradeableBeacon} from "@src/custom/proxy/UpgradeableBeacon.sol";
import {PausableUpgradeable} from "@src/custom/PausableUpgradeable.sol";

// libs
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";

// contracts
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {NFTXVaultUpgradeableV3} from "@src/NFTXVaultUpgradeableV3.sol";

// interfaces
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolDerivedState} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol";

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";

// Authors: @0xKiwi_, @alexgausman and @apoorvlathey

contract NFTXVaultFactoryUpgradeableV3 is
    INFTXVaultFactoryV3,
    PausableUpgradeable,
    UpgradeableBeacon
{
    // =============================================================
    //                            CONSTANTS
    // =============================================================
    uint256 MAX_DEPOSITOR_PREMIUM_SHARE = 1 ether;

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
        address vaultImpl,
        uint32 twapInterval_,
        uint256 premiumDuration_,
        uint256 premiumMax_,
        uint256 depositorPremiumShare_
    ) public override initializer {
        __Pausable_init();
        // We use a beacon proxy so that every child contract follows the same implementation code.
        __UpgradeableBeacon__init(vaultImpl);
        setFactoryFees(0.1 ether, 0.1 ether, 0.1 ether);

        if(twapInterval_ == 0) revert ZeroTwapInterval();
        if(depositorPremiumShare_ > MAX_DEPOSITOR_PREMIUM_SHARE) revert DepositorPremiumShareExceedsLimit();

        twapInterval = twapInterval_;
        premiumDuration = premiumDuration_;
        premiumMax = premiumMax_;
        depositorPremiumShare = depositorPremiumShare_;
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
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

        emit NewVault(vaultId, vaultAddr, assetAddress, name, symbol);
    }

    // =============================================================
    //                     ONLY PRIVILEGED WRITE
    // =============================================================

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
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

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
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

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function disableVaultFees(uint256 vaultId) external override {
        if (msg.sender != owner()) {
            address vaultAddr = _vaults[vaultId];
            if (msg.sender != vaultAddr) revert CallerIsNotVault();
        }
        delete _vaultFees[vaultId];
        emit DisableVaultFees(vaultId);
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function setFeeDistributor(
        address feeDistributor_
    ) external override onlyOwner {
        require(feeDistributor_ != address(0));
        emit NewFeeDistributor(feeDistributor, feeDistributor_);
        feeDistributor = feeDistributor_;
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function setFeeExclusion(
        address excludedAddr,
        bool excluded
    ) external override onlyOwner {
        excludedFromFees[excludedAddr] = excluded;
        emit FeeExclusion(excludedAddr, excluded);
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function setEligibilityManager(
        address eligibilityManager_
    ) external override onlyOwner {
        emit NewEligibilityManager(eligibilityManager, eligibilityManager_);
        eligibilityManager = eligibilityManager_;
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function setTwapInterval(uint32 twapInterval_) external override onlyOwner {
        if(twapInterval_ == 0) revert ZeroTwapInterval();

        twapInterval = twapInterval_;

        emit NewTwapInterval(twapInterval_);
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function setPremiumDuration(
        uint256 premiumDuration_
    ) external override onlyOwner {
        premiumDuration = premiumDuration_;

        emit NewPremiumDuration(premiumDuration_);
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function setPremiumMax(uint256 premiumMax_) external override onlyOwner {
        premiumMax = premiumMax_;

        emit NewPremiumMax(premiumMax_);
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function setDepositorPremiumShare(
        uint256 depositorPremiumShare_
    ) external override onlyOwner {
        if(depositorPremiumShare_ > MAX_DEPOSITOR_PREMIUM_SHARE) revert DepositorPremiumShareExceedsLimit();

        depositorPremiumShare = depositorPremiumShare_;

        emit NewDepositorPremiumShare(depositorPremiumShare_);
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
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

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function isLocked(uint256 lockId) external view override returns (bool) {
        return isPaused[lockId];
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function vaultsForAsset(
        address assetAddress
    ) external view override returns (address[] memory) {
        return _vaultsForAsset[assetAddress];
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function allVaults() external view override returns (address[] memory) {
        return _vaults;
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function numVaults() external view override returns (uint256) {
        return _vaults.length;
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function vault(uint256 vaultId) external view override returns (address) {
        return _vaults[vaultId];
    }

    /**
     * @inheritdoc INFTXVaultFactoryV3
     */
    function getTwapX96(
        address pool
    ) external view override returns (uint256 priceX96) {
        // secondsAgos[0] (from [before]) -> secondsAgos[1] (to [now])
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapInterval;
        secondsAgos[1] = 0;

        (bool success, bytes memory data) = pool.staticcall(
            abi.encodeWithSelector(
                IUniswapV3PoolDerivedState.observe.selector,
                secondsAgos
            )
        );

        // observe might fail for newly created pools that don't have sufficient observations yet
        if (!success) {
            // observations = [0, 1, 2, ..., index, (index + 1), ..., (cardinality - 1)]
            // Case 1: if entire array initialized once, then oldest observation at (index + 1) % cardinality
            // Case 2: array only initialized till index, then oldest obseravtion at index 0

            // Check Case 1
            (, , uint16 index, uint16 cardinality, , , ) = IUniswapV3Pool(pool)
                .slot0();

            (
                uint32 oldestAvailableTimestamp,
                ,
                ,
                bool initialized
            ) = IUniswapV3Pool(pool).observations((index + 1) % cardinality);

            // Case 2
            if (!initialized)
                (oldestAvailableTimestamp, , , ) = IUniswapV3Pool(pool)
                    .observations(0);

            // get corresponding observation
            secondsAgos[0] = uint32(block.timestamp - oldestAvailableTimestamp);
            (success, data) = pool.staticcall(
                abi.encodeWithSelector(
                    IUniswapV3PoolDerivedState.observe.selector,
                    secondsAgos
                )
            );
            // might revert if oldestAvailableTimestamp == block.timestamp, so we return price as 0
            if (!success || secondsAgos[0] == 0) {
                return 0;
            }
        }

        int56[] memory tickCumulatives = abi.decode(data, (int56[])); // don't bother decoding the liquidityCumulatives array

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24(
                (tickCumulatives[1] - tickCumulatives[0]) /
                    int56(int32(secondsAgos[0]))
            )
        );
        priceX96 = FullMath.mulDiv(
            sqrtPriceX96,
            sqrtPriceX96,
            FixedPoint96.Q96
        );
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
