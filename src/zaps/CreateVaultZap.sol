contract CreateVaultZap is ERC1155Holder {
    struct VaultInfo {
        address assetAddress;
        bool is1155;
        bool allowAllItems;
        string name;
        string symbol;
    }
    struct VaultEligibilityStorage {
        uint256 moduleIndex;
        bytes initData;
    }
    struct VaultFees {
        uint256 mintFee;
        uint256 redeemFee;
        uint256 swapFee;
    }
    struct LiquidityParams {
        uint256 lowerNFTPriceInETH;
        uint256 upperNFTPriceInETH;
        uint24 fee;
        // this current price is used if new pool needs to be initialized
        uint256 currentNFTPriceInETH;
        uint256 vTokenMin;
        uint256 wethMin;
        uint256 deadline;
    }
    struct CreateVaultParams {
        VaultInfo vaultInfo;
        VaultEligibilityStorage eligibilityStorage;
        uint256[] nftIds;
        uint256[] nftAmounts; // ignored for ERC721
        uint256 vaultFeaturesFlag; // packedBools in the order: `enableMint`, `enableRedeem`, `enableSwap`
        VaultFees vaultFees;
        LiquidityParams liquidityParams;
    }
    uint256 internal immutable MINIMUM_INVENTORY_LIQUIDITY;
    IWETH9 public immutable WETH;
    INFTXVaultFactoryV3 public immutable vaultFactory;
    INFTXRouter public immutable nftxRouter;
    IUniswapV3Factory public immutable ammFactory;
    INFTXInventoryStakingV3 public immutable inventoryStaking;
    INonfungiblePositionManager internal immutable positionManager;
    error InsufficientETHSent();
    error InsufficientVTokensMinted();
    constructor(INFTXRouter nftxRouter_, IUniswapV3Factory ammFactory_, INFTXInventoryStakingV3 inventoryStaking_) {
        nftxRouter = nftxRouter_;
        ammFactory = ammFactory_;
        inventoryStaking = inventoryStaking_;
        WETH = inventoryStaking_.WETH();
        MINIMUM_INVENTORY_LIQUIDITY = inventoryStaking_.MINIMUM_LIQUIDITY();
        vaultFactory = inventoryStaking_.nftxVaultFactory();
        positionManager = nftxRouter_.positionManager();
    }
    function createVault(CreateVaultParams calldata params) external payable returns (uint256 vaultId) {
        vaultId = vaultFactory.createVault(
            params.vaultInfo.name,
            params.vaultInfo.symbol,
            params.vaultInfo.assetAddress,
            params.vaultInfo.is1155,
            params.vaultInfo.allowAllItems
        );
        INFTXVaultV3 vault = INFTXVaultV3(vaultFactory.vault(vaultId));
        if (params.vaultInfo.allowAllItems == false) {
            vault.deployEligibilityStorage(
                params.eligibilityStorage.moduleIndex,
                params.eligibilityStorage.initData
            );
        }
        if (params.nftIds.length > 0) {
            if (!params.vaultInfo.is1155) {
                TransferLib.transferFromERC721(
                    params.vaultInfo.assetAddress,
                    address(vault),
                    params.nftIds
                );
            } else {
                IERC1155(params.vaultInfo.assetAddress).safeBatchTransferFrom(
                    msg.sender,
                    address(this),
                    params.nftIds,
                    params.nftAmounts,
                    ""
                );
                IERC1155(params.vaultInfo.assetAddress).setApprovalForAll(
                    address(vault),
                    true
                );
            }
            uint256 vTokensBalance = vault.mint(
                params.nftIds,
                params.nftAmounts,
                msg.sender,
                address(this)
            );
            if (params.liquidityParams.fee > 0) {
                if (msg.value < params.liquidityParams.wethMin)
                    revert InsufficientETHSent();
                if (vTokensBalance < params.liquidityParams.vTokenMin)
                    revert InsufficientVTokensMinted();

                TransferLib.unSafeMaxApprove(
                    address(vault),
                    address(nftxRouter),
                    vTokensBalance
                );
                bool isVToken0 = address(vault) < address(WETH);
                (
                    int24 tickLower,
                    int24 tickUpper,
                    uint160 currentSqrtPriceX96
                ) = _getTicks(
                        params.liquidityParams.currentNFTPriceInETH,
                        params.liquidityParams.lowerNFTPriceInETH,
                        params.liquidityParams.upperNFTPriceInETH,
                        params.liquidityParams.fee,
                        isVToken0
                    );
                uint256[] memory emptyIds;
                nftxRouter.addLiquidity{value: msg.value}(
                    INFTXRouter.AddLiquidityParams({
                        vaultId: vaultId,
                        vTokensAmount: vTokensBalance,
                        nftIds: emptyIds,
                        nftAmounts: emptyIds,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        fee: params.liquidityParams.fee,
                        sqrtPriceX96: currentSqrtPriceX96,
                        vTokenMin: params.liquidityParams.vTokenMin,
                        wethMin: params.liquidityParams.wethMin,
                        deadline: params.liquidityParams.deadline,
                        forceTimelock: false
                    })
                );
                vTokensBalance = vault.balanceOf(address(this));
            }
            if (vTokensBalance > 0) {
                if (vTokensBalance > MINIMUM_INVENTORY_LIQUIDITY) {
                    TransferLib.unSafeMaxApprove(
                        address(vault),
                        address(inventoryStaking),
                        vTokensBalance
                    );
                    inventoryStaking.deposit(
                        vaultId,
                        vTokensBalance,
                        msg.sender,
                        "",
                        false,
                        false // as twap doesn't exist so no mint fee would be charged by the vault at this instant, if transacted manually
                    );
                } else {
                    vault.transfer(address(inventoryStaking), vTokensBalance);
                }
            }
        }
        if (params.vaultFeaturesFlag < 7) {
            vault.setVaultFeatures(
                _getBoolean(params.vaultFeaturesFlag, 2),
                _getBoolean(params.vaultFeaturesFlag, 1),
                _getBoolean(params.vaultFeaturesFlag, 0)
            );
        }
        vault.setFees(
            params.vaultFees.mintFee,
            params.vaultFees.redeemFee,
            params.vaultFees.swapFee
        );
        vault.finalizeVault();
        uint256 remainingETH = address(this).balance;
        if (remainingETH > 0) {
            TransferLib.transferETH(msg.sender, remainingETH);
        }
    }
    function _getTicks(uint256 currentNFTPriceInETH, uint256 lowerNFTPriceInETH, uint256 upperNFTPriceInETH, uint24 fee, bool isVToken0) internal view returns (int24 tickLower, int24 tickUpper, uint160 currentSqrtPriceX96) {
        uint256 tickDistance = uint24(ammFactory.feeAmountTickSpacing(fee));
        if (isVToken0) {
            currentSqrtPriceX96 = TickHelpers.encodeSqrtRatioX96(
                currentNFTPriceInETH,
                1 ether
            );
            tickLower = TickHelpers.getTickForAmounts(
                lowerNFTPriceInETH,
                1 ether,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                upperNFTPriceInETH,
                1 ether,
                tickDistance
            );
        } else {
            currentSqrtPriceX96 = TickHelpers.encodeSqrtRatioX96(
                1 ether,
                currentNFTPriceInETH
            );
            tickLower = TickHelpers.getTickForAmounts(
                1 ether,
                upperNFTPriceInETH,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                1 ether,
                lowerNFTPriceInETH,
                tickDistance
            );
        }
    }
    function _getBoolean(uint256 packedBools, uint256 boolNumber) internal pure returns (bool) {
        uint256 flag = (packedBools >> boolNumber) & uint256(1);
        return (flag == 1 ? true : false);
    }
    receive() external payable {
        require(msg.sender == address(positionManager));
    }
}
