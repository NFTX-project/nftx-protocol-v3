contract NFTXVaultFactoryUpgradeableV3 is INFTXVaultFactoryV3, PausableUpgradeable, UpgradeableBeacon {
    uint256 constant MAX_DEPOSITOR_PREMIUM_SHARE = 1 ether;
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
    uint256 public override premiumDuration;
    uint256 public override premiumMax;
    uint256 public override depositorPremiumShare;
    function __NFTXVaultFactory_init(address vaultImpl, uint32 twapInterval_, uint256 premiumDuration_, uint256 premiumMax_, uint256 depositorPremiumShare_) public override initializer {
        __Pausable_init();
        __UpgradeableBeacon__init(vaultImpl);
        setFactoryFees(0.1 ether, 0.1 ether, 0.1 ether);
        if (twapInterval_ == 0) revert ZeroTwapInterval();
        if (depositorPremiumShare_ > MAX_DEPOSITOR_PREMIUM_SHARE) revert DepositorPremiumShareExceedsLimit();
        twapInterval = twapInterval_;
        premiumDuration = premiumDuration_;
        premiumMax = premiumMax_;
        depositorPremiumShare = depositorPremiumShare_;
    }
    function createVault(string memory name, string memory symbol, address assetAddress, bool is1155, bool allowAllItems) external override returns (uint256 vaultId) {
        onlyOwnerIfPaused(0);
        if (feeDistributor == address(0)) revert FeeDistributorNotSet();
        if (implementation() == address(0)) revert VaultImplementationNotSet();
        address vaultAddr = _deployVault(name, symbol, assetAddress, is1155, allowAllItems);
        vaultId = _vaults.length;
        _vaultsForAsset[assetAddress].push(vaultAddr);
        _vaults.push(vaultAddr);
        emit NewVault(vaultId, vaultAddr, assetAddress, name, symbol);
    }
    function setFactoryFees(uint256 mintFee, uint256 redeemFee, uint256 swapFee) public override onlyOwner {
        if (mintFee > 0.5 ether) revert FeeExceedsLimit();
        if (redeemFee > 0.5 ether) revert FeeExceedsLimit();
        if (swapFee > 0.5 ether) revert FeeExceedsLimit();
        factoryMintFee = uint64(mintFee);
        factoryRedeemFee = uint64(redeemFee);
        factorySwapFee = uint64(swapFee);
        emit UpdateFactoryFees(mintFee, redeemFee, swapFee);
    }
    function setVaultFees(uint256 vaultId, uint256 mintFee, uint256 redeemFee, uint256 swapFee) external override {
        if (msg.sender != owner()) {
            address vaultAddr = _vaults[vaultId];
            if (msg.sender != vaultAddr) revert CallerIsNotVault();
        }
        if (mintFee > 0.5 ether) revert FeeExceedsLimit();
        if (redeemFee > 0.5 ether) revert FeeExceedsLimit();
        if (swapFee > 0.5 ether) revert FeeExceedsLimit();
        _vaultFees[vaultId] = VaultFees(true, uint64(mintFee), uint64(redeemFee), uint64(swapFee));
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
    function setFeeDistributor(address feeDistributor_) external override onlyOwner {
        if (feeDistributor_ == address(0)) revert ZeroAddress();
        emit NewFeeDistributor(feeDistributor, feeDistributor_);
        feeDistributor = feeDistributor_;
    }
    function setFeeExclusion(address excludedAddr, bool excluded) external override onlyOwner {
        excludedFromFees[excludedAddr] = excluded;
        emit FeeExclusion(excludedAddr, excluded);
    }
    function setEligibilityManager(address eligibilityManager_) external override onlyOwner {
        emit NewEligibilityManager(eligibilityManager, eligibilityManager_);
        eligibilityManager = eligibilityManager_;
    }
    function setTwapInterval(uint32 twapInterval_) external override onlyOwner {
        if (twapInterval_ == 0) revert ZeroTwapInterval();
        twapInterval = twapInterval_;
        emit NewTwapInterval(twapInterval_);
    }
    function setPremiumDuration(uint256 premiumDuration_) external override onlyOwner {
        premiumDuration = premiumDuration_;
        emit NewPremiumDuration(premiumDuration_);
    }
    function setPremiumMax(uint256 premiumMax_) external override onlyOwner {
        premiumMax = premiumMax_;
        emit NewPremiumMax(premiumMax_);
    }
    function setDepositorPremiumShare(uint256 depositorPremiumShare_) external override onlyOwner {
        if (depositorPremiumShare_ > MAX_DEPOSITOR_PREMIUM_SHARE) revert DepositorPremiumShareExceedsLimit();
        depositorPremiumShare = depositorPremiumShare_;
        emit NewDepositorPremiumShare(depositorPremiumShare_);
    }
    function vaultFees(uint256 vaultId) external view override returns (uint256 mintFee, uint256 redeemFee, uint256 swapFee) {
        VaultFees memory fees = _vaultFees[vaultId];
        if (fees.active) {
            return (uint256(fees.mintFee), uint256(fees.redeemFee), uint256(fees.swapFee));
        }
        return (uint256(factoryMintFee), uint256(factoryRedeemFee), uint256(factorySwapFee));
    }
    function getVTokenPremium721(uint256 vaultId, uint256 tokenId) external view override returns (uint256 premium, address depositor) {
        INFTXVaultV3 _vault = INFTXVaultV3(_vaults[vaultId]);
        if (_vault.holdingsContains(tokenId)) {
            uint48 timestamp;
            (timestamp, depositor) = _vault.tokenDepositInfo(tokenId);
            premium = _getVTokenPremium(timestamp, premiumMax, premiumDuration);
        }
    }
    function getVTokenPremium1155(uint256 vaultId, uint256 tokenId, uint256 amount) external view override returns (uint256 netPremium, uint256[] memory premiums, address[] memory depositors) {
        INFTXVaultV3 _vault = INFTXVaultV3(_vaults[vaultId]);
        if (_vault.holdingsContains(tokenId)) {
            if (amount == 0) revert ZeroAmountRequested();
            premiums = new uint256[](amount);
            depositors = new address[](amount);
            uint256 _pointerIndex1155 = _vault.pointerIndex1155(tokenId);
            uint256 i = 0;
            uint256 _premiumMax = premiumMax;
            uint256 _premiumDuration = premiumDuration;
            uint256 _tokenPositionLength = _vault.depositInfo1155Length(tokenId);
            while (true) {
                if (_tokenPositionLength <= _pointerIndex1155 + i) revert NFTInventoryExceeded();
                (uint256 qty, address depositor, uint48 timestamp) = _vault.depositInfo1155(tokenId, _pointerIndex1155 + i);
                if (qty > amount) {
                    uint256 vTokenPremium = _getVTokenPremium(timestamp, _premiumMax, _premiumDuration) * amount;
                    netPremium += vTokenPremium;
                    premiums[i] = vTokenPremium;
                    depositors[i] = depositor;
                    break;
                } else {
                    amount -= qty;
                    uint256 vTokenPremium = _getVTokenPremium(timestamp, _premiumMax, _premiumDuration) * qty;
                    netPremium += vTokenPremium;
                    premiums[i] = vTokenPremium;
                    depositors[i] = depositor;
                    unchecked {
                        ++i;
                    }
                }
            }
            uint256 finalArrayLength = i + 1;
            if (finalArrayLength < premiums.length) {
                assembly {
                    mstore(premiums, finalArrayLength)
                    mstore(depositors, finalArrayLength)
                }
            }
        }
    }
    function isLocked(uint256 lockId) external view override returns (bool) {
        return isPaused[lockId];
    }
    function vaultsForAsset(address assetAddress) external view override returns (address[] memory) {
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
    function getTwapX96(address pool) external view override returns (uint256 priceX96) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapInterval;
        secondsAgos[1] = 0;
        (bool success, bytes memory data) = pool.staticcall(abi.encodeWithSelector(IUniswapV3PoolDerivedState.observe.selector, secondsAgos));
        if (!success) {
            (, , uint16 index, uint16 cardinality, , , ) = IUniswapV3Pool(pool).slot0();
            (uint32 oldestAvailableTimestamp, , , bool initialized) = IUniswapV3Pool(pool).observations((index + 1) % cardinality);
            if (!initialized) (oldestAvailableTimestamp, , , ) = IUniswapV3Pool(pool).observations(0);
            secondsAgos[0] = uint32(block.timestamp - oldestAvailableTimestamp);
            (success, data) = pool.staticcall(abi.encodeWithSelector(IUniswapV3PoolDerivedState.observe.selector, secondsAgos));
            if (!success || secondsAgos[0] == 0) {
                return 0;
            }
        }
        int56[] memory tickCumulatives = abi.decode(data, (int56[])); // don't bother decoding the liquidityCumulatives array
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(secondsAgos[0]))));
        priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }
    function _deployVault(string memory name, string memory symbol, address assetAddress, bool is1155, bool allowAllItems) internal returns (address) {
        address newBeaconProxy = address(new BeaconProxy(address(this), ""));
        NFTXVaultUpgradeableV3(newBeaconProxy).__NFTXVault_init(name, symbol, assetAddress, is1155, allowAllItems);
        NFTXVaultUpgradeableV3(newBeaconProxy).setManager(msg.sender);
        NFTXVaultUpgradeableV3(newBeaconProxy).transferOwnership(owner());
        return newBeaconProxy;
    }
    function _getVTokenPremium(uint48 timestamp, uint256 _premiumMax, uint256 _premiumDuration) internal view returns (uint256) {
        return ExponentialPremium.getPremium(timestamp, _premiumMax, _premiumDuration);
    }
}
