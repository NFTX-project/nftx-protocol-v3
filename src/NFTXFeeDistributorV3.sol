contract NFTXFeeDistributorV3 is INFTXFeeDistributorV3, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    INFTXVaultFactoryV3 public immutable override nftxVaultFactory;
    IUniswapV3Factory public immutable override ammFactory;
    INFTXInventoryStakingV3 public immutable override inventoryStaking;
    IERC20 public immutable override WETH;
    uint256 constant POOL_DEFAULT_ALLOC = 0.8 ether; // 80%
    uint256 constant INVENTORY_DEFAULT_ALLOC = 0.2 ether; // 20%
    uint24 public override rewardFeeTier;
    INFTXRouter public override nftxRouter;
    address public override treasury;
    uint256 public override allocTotal;
    FeeReceiver[] public override feeReceivers;
    bool public override distributionPaused;
    constructor(INFTXVaultFactoryV3 nftxVaultFactory_, IUniswapV3Factory ammFactory_, INFTXInventoryStakingV3 inventoryStaking_, INFTXRouter nftxRouter_, address treasury_) {
        if (address(nftxVaultFactory_) == address(0)) revert ZeroAddress();
        if (address(ammFactory_) == address(0)) revert ZeroAddress();
        if (address(inventoryStaking_) == address(0)) revert ZeroAddress();
        if (address(nftxRouter_) == address(0)) revert ZeroAddress();
        nftxVaultFactory = nftxVaultFactory_;
        ammFactory = ammFactory_;
        inventoryStaking = inventoryStaking_;
        WETH = IERC20(nftxRouter_.WETH());
        nftxRouter = nftxRouter_;
        treasury = treasury_;
        rewardFeeTier = 10_000;
        FeeReceiver[] memory feeReceivers_ = new FeeReceiver[](2);
        feeReceivers_[0] = FeeReceiver({receiver: address(0), allocPoint: POOL_DEFAULT_ALLOC, receiverType: ReceiverType.POOL});
        feeReceivers_[1] = FeeReceiver({receiver: address(inventoryStaking_), allocPoint: INVENTORY_DEFAULT_ALLOC, receiverType: ReceiverType.INVENTORY});
        setReceivers(feeReceivers_);
    }
    function distribute(uint256 vaultId) external override nonReentrant {
        INFTXVaultV3 vault = INFTXVaultV3(nftxVaultFactory.vault(vaultId));
        uint256 wethBalance = WETH.balanceOf(address(this));
        if (distributionPaused || allocTotal == 0) {
            WETH.transfer(treasury, wethBalance);
            return;
        }
        uint256 leftover;
        uint256 len = feeReceivers.length;
        for (uint256 i; i < len; ) {
            FeeReceiver storage feeReceiver = feeReceivers[i];
            uint256 wethAmountToSend = leftover + (wethBalance * feeReceiver.allocPoint) / allocTotal;
            bool tokenSent = _sendForReceiver(feeReceiver, wethAmountToSend, vaultId, vault);
            leftover = tokenSent ? 0 : leftover + wethAmountToSend;
            unchecked {
                ++i;
            }
        }
        if (leftover > 0) {
            WETH.transfer(treasury, leftover);
        }
    }
    function distributeVTokensToPool(address pool, address vToken, uint256 vTokenAmount) external {
        if (msg.sender != address(nftxRouter)) revert SenderNotNFTXRouter();
        uint256 liquidity = IUniswapV3Pool(pool).liquidity();
        if (liquidity > 0) {
            IERC20(vToken).transfer(pool, vTokenAmount);
            IUniswapV3Pool(pool).distributeRewards(
                vTokenAmount,
                address(vToken) < address(WETH) // isVToken0
            );
        } else {
            IERC20(vToken).transfer(address(inventoryStaking), vTokenAmount);
        }
    }
    function setReceivers(FeeReceiver[] memory feeReceivers_) public override onlyOwner {
        delete feeReceivers;
        uint256 _allocTotal;
        uint256 len = feeReceivers_.length;
        for (uint256 i; i < len; ) {
            feeReceivers.push(feeReceivers_[i]);
            _allocTotal += feeReceivers_[i].allocPoint;

            unchecked {
                ++i;
            }
        }
        allocTotal = _allocTotal;
    }
    function changeRewardFeeTier(uint24 rewardFeeTier_) external override onlyOwner {
        if (ammFactory.feeAmountTickSpacing(rewardFeeTier_) == 0) revert FeeTierNotEnabled();
        rewardFeeTier = rewardFeeTier_;
        emit NewRewardFeeTier(rewardFeeTier_);
    }
    function setTreasuryAddress(address treasury_) external override onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        emit UpdateTreasuryAddress(treasury, treasury_);
        treasury = treasury_;
    }
    function setNFTXRouter(INFTXRouter nftxRouter_) external override onlyOwner {
        if (address(nftxRouter_) == address(0)) revert ZeroAddress();
        nftxRouter = nftxRouter_;
        emit NewNFTXRouter(address(nftxRouter_));
    }
    function pauseFeeDistribution(bool pause) external override onlyOwner {
        distributionPaused = pause;
        emit PauseDistribution(pause);
    }
    function rescueTokens(IERC20 token) external override onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, balance);
    }
    function _sendForReceiver(FeeReceiver storage feeReceiver, uint256 wethAmountToSend, uint256 vaultId, INFTXVaultV3 vault) internal returns (bool tokenSent) {
        if (feeReceiver.receiverType == ReceiverType.INVENTORY) {
            TransferLib.unSafeMaxApprove(address(WETH), address(inventoryStaking), wethAmountToSend);
            bool pulledTokens = inventoryStaking.receiveWethRewards(vaultId, wethAmountToSend);
            if (pulledTokens) {
                emit WethDistributedToInventory(vaultId, wethAmountToSend);
            }
            tokenSent = pulledTokens;
        } else if (feeReceiver.receiverType == ReceiverType.POOL) {
            (address pool, bool exists) = nftxRouter.getPoolExists(vaultId, rewardFeeTier);
            if (exists) {
                uint256 liquidity = IUniswapV3Pool(pool).liquidity();
                if (liquidity > 0) {
                    WETH.transfer(pool, wethAmountToSend);
                    IUniswapV3Pool(pool).distributeRewards(
                        wethAmountToSend,
                        address(vault) > address(WETH) // !isVToken0
                    );
                    emit WethDistributedToPool(vaultId, wethAmountToSend);
                    tokenSent = true;
                }
            }
        } else {
            WETH.transfer(feeReceiver.receiver, wethAmountToSend);
            tokenSent = true;
        }
    }
}
