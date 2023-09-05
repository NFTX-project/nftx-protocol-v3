contract NFTXRouter is INFTXRouter, Ownable, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;
    address public immutable override WETH;
    IPermitAllowanceTransfer public immutable override PERMIT2;
    INonfungiblePositionManager public immutable override positionManager;
    SwapRouter public immutable override router;
    IQuoterV2 public immutable override quoter;
    INFTXVaultFactoryV3 public immutable override nftxVaultFactory;
    INFTXInventoryStakingV3 public immutable override inventoryStaking;
    uint256 public override lpTimelock;
    uint256 public override earlyWithdrawPenaltyInWei;
    uint256 public override vTokenDustThreshold;
    constructor(INonfungiblePositionManager positionManager_, SwapRouter router_, IQuoterV2 quoter_, INFTXVaultFactoryV3 nftxVaultFactory_, IPermitAllowanceTransfer PERMIT2_, uint256 lpTimelock_, uint256 earlyWithdrawPenaltyInWei_, uint256 vTokenDustThreshold_, INFTXInventoryStakingV3 inventoryStaking_) {
        positionManager = positionManager_;
        router = router_;
        quoter = quoter_;
        nftxVaultFactory = nftxVaultFactory_;
        PERMIT2 = PERMIT2_;
        if (lpTimelock_ == 0) revert ZeroLPTimelock();
        lpTimelock = lpTimelock_;
        if (earlyWithdrawPenaltyInWei_ > 1 ether) revert InvalidEarlyWithdrawPenalty();
        earlyWithdrawPenaltyInWei = earlyWithdrawPenaltyInWei_;
        vTokenDustThreshold = vTokenDustThreshold_;
        inventoryStaking = inventoryStaking_;
        WETH = positionManager_.WETH9();
    }
    function addLiquidity(AddLiquidityParams calldata params) external payable override returns (uint256 positionId) {
        INFTXVaultV3 vToken = INFTXVaultV3(nftxVaultFactory.vault(params.vaultId));
        if (params.vTokensAmount > 0) {
            vToken.transferFrom(msg.sender, address(this), params.vTokensAmount);
        }
        return _addLiquidity(params, vToken);
    }
    function addLiquidityWithPermit2(AddLiquidityParams calldata params, bytes calldata encodedPermit2) external payable override returns (uint256 positionId) {
        INFTXVaultV3 vToken = INFTXVaultV3(nftxVaultFactory.vault(params.vaultId));
        if (encodedPermit2.length > 0) {
            (address owner, IPermitAllowanceTransfer.PermitSingle memory permitSingle, bytes memory signature) = abi.decode(encodedPermit2, (address, IPermitAllowanceTransfer.PermitSingle, bytes));
            PERMIT2.permit(owner, permitSingle, signature);
        }
        if (params.vTokensAmount > 0) {
            PERMIT2.transferFrom(msg.sender, address(this), SafeCast.toUint160(params.vTokensAmount), address(vToken));
        }
        return _addLiquidity(params, vToken);
    }
    function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable override {
        INFTXVaultV3 vToken = INFTXVaultV3(nftxVaultFactory.vault(params.vaultId));
        if (params.vTokensAmount > 0) {
            vToken.transferFrom(msg.sender, address(this), params.vTokensAmount);
        }
        return _increaseLiquidity(params, vToken);
    }
    function increaseLiquidityWithPermit2(IncreaseLiquidityParams calldata params, bytes calldata encodedPermit2) external payable override {
        INFTXVaultV3 vToken = INFTXVaultV3(nftxVaultFactory.vault(params.vaultId));
        if (encodedPermit2.length > 0) {
            (address owner, IPermitAllowanceTransfer.PermitSingle memory permitSingle, bytes memory signature) = abi.decode(encodedPermit2, (address, IPermitAllowanceTransfer.PermitSingle, bytes));
            PERMIT2.permit(owner, permitSingle, signature);
        }
        if (params.vTokensAmount > 0) {
            PERMIT2.transferFrom(msg.sender, address(this), SafeCast.toUint160(params.vTokensAmount), address(vToken));
        }
        return _increaseLiquidity(params, vToken);
    }
    function removeLiquidity(RemoveLiquidityParams calldata params) external payable override {
        if (positionManager.ownerOf(params.positionId) != msg.sender) revert NotPositionOwner();
        positionManager.decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams({tokenId: params.positionId, liquidity: params.liquidity, amount0Min: params.amount0Min, amount1Min: params.amount1Min, deadline: params.deadline}));
        INFTXVaultV3 vToken;
        uint256 vTokenAmt;
        uint256 wethAmt;
        {
            (uint256 amount0, uint256 amount1) = positionManager.collect(INonfungiblePositionManager.CollectParams({tokenId: params.positionId, recipient: address(this), amount0Max: type(uint128).max, amount1Max: type(uint128).max}));
            vToken = INFTXVaultV3(nftxVaultFactory.vault(params.vaultId));
            bool _isVToken0 = isVToken0(address(vToken));
            (vTokenAmt, wethAmt) = _isVToken0 ? (amount0, amount1) : (amount1, amount0);
        }
        uint256 _timelockedUntil = positionManager.lockedUntil(params.positionId);
        uint256 _timelock = positionManager.timelock(params.positionId);
        if (block.timestamp <= _timelockedUntil) {
            if (vTokenAmt > 0) {
                uint256 vTokenPenalty = ((_timelockedUntil - block.timestamp) * vTokenAmt * earlyWithdrawPenaltyInWei) / (_timelock * 1 ether);
                {
                    (, , , , uint24 fee, , , , , , , ) = positionManager.positions(params.positionId);
                    address pool = IUniswapV3Factory(router.factory()).getPool(address(vToken), WETH, fee);
                    address feeDistributor = nftxVaultFactory.feeDistributor();
                    vToken.transfer(feeDistributor, vTokenPenalty);
                    INFTXFeeDistributorV3(feeDistributor).distributeVTokensToPool(pool, address(vToken), vTokenPenalty);
                }
                vTokenAmt -= vTokenPenalty;
            }
        }
        if (params.nftIds.length == 0 && vTokenAmt > 0) {
            if (msg.value > 0) revert NoETHFundsNeeded();
            vToken.transfer(msg.sender, vTokenAmt);
        } else {
            if (msg.value > 0) {
                IWETH9(WETH).deposit{value: msg.value}();
                wethAmt += msg.value;
            }
            bool chargeFees = positionManager.lockedUntil(params.positionId) == 0;
            if (chargeFees) {
                TransferLib.unSafeMaxApprove(WETH, address(vToken), wethAmt);
            }
            uint256 vTokenBurned = params.nftIds.length * 1 ether;
            if (vTokenAmt < vTokenBurned) revert InsufficientVTokens();
            uint256 wethFees = vToken.redeem(params.nftIds, msg.sender, wethAmt, params.vTokenPremiumLimit, chargeFees);
            wethAmt -= wethFees;
            uint256 vTokenResidue = vTokenAmt - vTokenBurned;
            if (vTokenResidue > 0) {
                vToken.transfer(msg.sender, vTokenResidue);
            }
        }
        IWETH9(WETH).withdraw(wethAmt);
        TransferLib.transferETH(msg.sender, wethAmt);
        emit RemoveLiquidity(params.positionId, params.vaultId, vTokenAmt, wethAmt);
    }
    function sellNFTs(SellNFTsParams calldata params) external payable override returns (uint256 wethReceived) {
        INFTXVaultV3 vToken = INFTXVaultV3(nftxVaultFactory.vault(params.vaultId));
        address assetAddress = INFTXVaultV3(address(vToken)).assetAddress();
        if (!vToken.is1155()) {
            TransferLib.transferFromERC721(assetAddress, address(vToken), params.nftIds);
        } else {
            IERC1155(assetAddress).safeBatchTransferFrom(msg.sender, address(this), params.nftIds, params.nftAmounts, "");
            IERC1155(assetAddress).setApprovalForAll(address(vToken), true);
        }
        uint256 vTokensAmount = vToken.mint(params.nftIds, params.nftAmounts, msg.sender, address(this));
        TransferLib.unSafeMaxApprove(address(vToken), address(router), vTokensAmount);
        wethReceived = router.exactInputSingle(ISwapRouter.ExactInputSingleParams({tokenIn: address(vToken), tokenOut: WETH, fee: params.fee, recipient: address(this), deadline: params.deadline, amountIn: vTokensAmount, amountOutMinimum: params.amountOutMinimum, sqrtPriceLimitX96: params.sqrtPriceLimitX96}));
        if (msg.value > 0) {
            IWETH9(WETH).deposit{value: msg.value}();
            wethReceived += msg.value;
        }
        uint256 nftCount = !vToken.is1155() ? params.nftIds.length : _sum1155Ids(params.nftIds, params.nftAmounts);
        uint256 wethFees = _ethMintFees(vToken, nftCount);
        _distributeVaultFees(params.vaultId, wethFees, true);
        uint256 wethRemaining = wethReceived - wethFees; // if underflow, then revert desired
        IWETH9(WETH).withdraw(wethRemaining);
        TransferLib.transferETH(msg.sender, wethRemaining);
        emit SellNFTs(nftCount, wethRemaining);
    }
    function buyNFTs(BuyNFTsParams calldata params) external payable override {
        INFTXVaultV3 vToken = INFTXVaultV3(nftxVaultFactory.vault(params.vaultId));
        uint256 vTokenAmt = params.nftIds.length * 1 ether;
        IWETH9(WETH).deposit{value: msg.value}();
        TransferLib.unSafeMaxApprove(WETH, address(router), msg.value);
        uint256 wethSpent = router.exactOutputSingle(ISwapRouter.ExactOutputSingleParams({tokenIn: WETH, tokenOut: address(vToken), fee: params.fee, recipient: address(this), deadline: params.deadline, amountOut: vTokenAmt, amountInMaximum: msg.value, sqrtPriceLimitX96: params.sqrtPriceLimitX96}));
        uint256 wethLeft = msg.value - wethSpent;
        TransferLib.unSafeMaxApprove(WETH, address(vToken), wethLeft);
        uint256 wethFees = vToken.redeem(params.nftIds, msg.sender, wethLeft, params.vTokenPremiumLimit, true);
        wethLeft -= wethFees;
        if (wethLeft > 0) {
            IWETH9(WETH).withdraw(wethLeft);
            TransferLib.transferETH(msg.sender, wethLeft);
        }
        emit BuyNFTs(params.nftIds.length, wethSpent + wethFees);
    }
    function rescueTokens(IERC20 token) external override onlyOwner {
        if (address(token) != address(0)) {
            uint256 balance = token.balanceOf(address(this));
            token.safeTransfer(msg.sender, balance);
        } else {
            uint256 balance = address(this).balance;
            TransferLib.transferETH(msg.sender, balance);
        }
    }
    function setLpTimelock(uint256 lpTimelock_) external override onlyOwner {
        if (lpTimelock_ == 0) revert ZeroLPTimelock();
        lpTimelock = lpTimelock_;
    }
    function setVTokenDustThreshold(uint256 vTokenDustThreshold_) external override onlyOwner {
        vTokenDustThreshold = vTokenDustThreshold_;
    }
    function setEarlyWithdrawPenalty(uint256 earlyWithdrawPenaltyInWei_) external onlyOwner {
        if (earlyWithdrawPenaltyInWei_ > 1 ether) revert InvalidEarlyWithdrawPenalty();
        earlyWithdrawPenaltyInWei = earlyWithdrawPenaltyInWei_;
    }
    function quoteBuyNFTs(address vtoken, uint256 nftsCount, uint24 fee, uint160 sqrtPriceLimitX96) external override returns (uint256 ethRequired) {
        uint256 vTokenAmt = nftsCount * 1 ether;
        (ethRequired, , , ) = quoter.quoteExactOutputSingle(IQuoterV2.QuoteExactOutputSingleParams({tokenIn: WETH, tokenOut: address(vtoken), amount: vTokenAmt, fee: fee, sqrtPriceLimitX96: sqrtPriceLimitX96}));
    }
    function getPoolExists(uint256 vaultId, uint24 fee) external view override returns (address pool, bool exists) {
        address vToken_ = nftxVaultFactory.vault(vaultId);
        pool = IUniswapV3Factory(router.factory()).getPool(vToken_, WETH, fee);
        exists = pool != address(0);
    }
    function getPoolExists(address vToken_, uint24 fee) external view override returns (address pool, bool exists) {
        pool = IUniswapV3Factory(router.factory()).getPool(vToken_, WETH, fee);
        exists = pool != address(0);
    }
    function getPool(address vToken_, uint24 fee) external view override returns (address pool) {
        pool = IUniswapV3Factory(router.factory()).getPool(vToken_, WETH, fee);
        if (pool == address(0)) revert();
    }
    function computePool(address vToken_, uint24 fee) external view override returns (address) {
        return PoolAddress.computeAddress(router.factory(), PoolAddress.getPoolKey(vToken_, WETH, fee));
    }
    function isVToken0(address vtoken) public view override returns (bool) {
        return vtoken < WETH;
    }
    function _addLiquidity(AddLiquidityParams calldata params, INFTXVaultV3 vToken) internal returns (uint256 positionId) {
        (uint256 vTokensAmount, bool _isVToken0) = _pullAndMintVTokens(vToken, params.nftIds, params.nftAmounts, !vToken.is1155(), params.vTokensAmount);
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({token0: address(0), token1: address(0), fee: params.fee, tickLower: params.tickLower, tickUpper: params.tickUpper, amount0Desired: 0, amount1Desired: 0, amount0Min: 0, amount1Min: 0, recipient: msg.sender, deadline: params.deadline});
        if (msg.value < params.wethMin) revert ETHValueLowerThanMin();
        (mintParams.token0, mintParams.token1, mintParams.amount0Desired, mintParams.amount1Desired, mintParams.amount0Min, mintParams.amount1Min) = _isVToken0 ? (address(vToken), WETH, vTokensAmount, msg.value, params.vTokenMin, params.wethMin) : (WETH, address(vToken), msg.value, vTokensAmount, params.wethMin, params.vTokenMin);
        address pool = positionManager.createAndInitializePoolIfNecessary(mintParams.token0, mintParams.token1, params.fee, params.sqrtPriceX96);
        (positionId, , , ) = positionManager.mint{value: msg.value}(mintParams);
        _postAddLiq(vToken, params.nftIds, positionId, params.vaultId, params.forceTimelock);
        emit AddLiquidity(positionId, params.vaultId, params.vTokensAmount, params.nftIds, pool);
    }
    function _increaseLiquidity(IncreaseLiquidityParams calldata params, INFTXVaultV3 vToken) internal {
        if (positionManager.ownerOf(params.positionId) != msg.sender) revert NotPositionOwner();
        (uint256 vTokensAmount, bool _isVToken0) = _pullAndMintVTokens(vToken, params.nftIds, params.nftAmounts, !vToken.is1155(), params.vTokensAmount);
        if (msg.value < params.wethMin) revert ETHValueLowerThanMin();
        (uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min) = _isVToken0 ? (vTokensAmount, msg.value, params.vTokenMin, params.wethMin) : (msg.value, vTokensAmount, params.wethMin, params.vTokenMin);
        positionManager.increaseLiquidity{value: msg.value}(INonfungiblePositionManager.IncreaseLiquidityParams({tokenId: params.positionId, amount0Desired: amount0Desired, amount1Desired: amount1Desired, amount0Min: amount0Min, amount1Min: amount1Min, deadline: params.deadline}));
        _postAddLiq(vToken, params.nftIds, params.positionId, params.vaultId, params.forceTimelock);
        emit IncreaseLiquidity(params.positionId, params.vaultId, params.vTokensAmount, params.nftIds);
    }
    function _pullAndMintVTokens(INFTXVaultV3 vToken, uint256[] calldata nftIds, uint256[] calldata nftAmounts, bool is721, uint256 currentVTokensAmount) internal returns (uint256 vTokensAmount, bool _isVToken0) {
        vTokensAmount = currentVTokensAmount;
        if (nftIds.length > 0) {
            address assetAddress = vToken.assetAddress();
            if (is721) {
                TransferLib.transferFromERC721(assetAddress, address(vToken), nftIds);
            } else {
                IERC1155(assetAddress).safeBatchTransferFrom(msg.sender, address(this), nftIds, nftAmounts, "");
                IERC1155(assetAddress).setApprovalForAll(address(vToken), true);
            }
            vTokensAmount += vToken.mint(nftIds, nftAmounts, msg.sender, address(this));
        }
        TransferLib.unSafeMaxApprove(address(vToken), address(positionManager), vTokensAmount);
        _isVToken0 = isVToken0(address(vToken));
    }
    function _postAddLiq(INFTXVaultV3 vToken, uint256[] calldata nftIds, uint256 positionId, uint256 vaultId, bool forceTimelock) internal {
        uint256 vTokenBalance = vToken.balanceOf(address(this));
        if (nftIds.length > 0) {
            uint256 _lpTimelock = lpTimelock;
            positionManager.setLockedUntil(positionId, block.timestamp + _lpTimelock, _lpTimelock);
            if (vTokenBalance > 0) {
                if (vTokenBalance > vTokenDustThreshold) {
                    TransferLib.unSafeMaxApprove(address(vToken), address(inventoryStaking), vTokenBalance);
                    inventoryStaking.deposit(vaultId, vTokenBalance, msg.sender, "", false, true);
                } else {
                    vToken.transfer(msg.sender, vTokenBalance);
                }
            }
        } else {
            if (forceTimelock) {
                uint256 _lpTimelock = lpTimelock;
                positionManager.setLockedUntil(positionId, block.timestamp + _lpTimelock, _lpTimelock);
            }
            if (vTokenBalance > 0) {
                vToken.transfer(msg.sender, vTokenBalance);
            }
        }
        positionManager.refundETH(msg.sender);
    }
    function _distributeVaultFees(uint256 vaultId, uint256 ethAmount, bool isWeth) internal {
        if (ethAmount > 0) {
            INFTXFeeDistributorV3 feeDistributor = INFTXFeeDistributorV3(nftxVaultFactory.feeDistributor());
            if (!isWeth) {
                IWETH9(WETH).deposit{value: ethAmount}();
            }
            IWETH9(WETH).transfer(address(feeDistributor), ethAmount);
            feeDistributor.distribute(vaultId);
        }
    }
    function _sum1155Ids(uint256[] calldata ids, uint256[] calldata amounts) internal pure returns (uint256 totalAmount) {
        for (uint i; i < ids.length; ) {
            unchecked {
                totalAmount += amounts[i];
                ++i;
            }
        }
    }
    function _ethMintFees(INFTXVaultV3 vToken, uint256 nftCount) internal view returns (uint256) {
        (uint256 mintFee, , ) = vToken.vaultFees();
        return vToken.vTokenToETH(mintFee * nftCount);
    }
    receive() external payable {}
}
