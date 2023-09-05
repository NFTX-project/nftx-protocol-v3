contract MigratorZap {
    struct SushiToNFTXAMMParams {
        address sushiPair;
        uint256 lpAmount;
        address vTokenV2;
        uint256[] idsToRedeem;
        bool is1155;
        bytes permitSig;
        uint256 vaultIdV3;
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
        uint160 sqrtPriceX96;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    uint256 private constant DEADLINE = 0xf000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant DUST_THRESHOLD = 0.005 ether;
    IWETH9 public immutable WETH;
    INFTXVaultFactoryV2 public immutable v2NFTXFactory;
    INFTXInventoryStakingV2 public immutable v2Inventory;
    IUniswapV2Router02 public immutable sushiRouter;
    INonfungiblePositionManager public immutable positionManager;
    INFTXVaultFactoryV3 public immutable v3NFTXFactory;
    INFTXInventoryStakingV3 public immutable v3Inventory;
    error InvalidSignatureLength();
    constructor(IWETH9 WETH_, INFTXVaultFactoryV2 v2NFTXFactory_, INFTXInventoryStakingV2 v2Inventory_, IUniswapV2Router02 sushiRouter_, INonfungiblePositionManager positionManager_, INFTXVaultFactoryV3 v3NFTXFactory_, INFTXInventoryStakingV3 v3Inventory_) {
        WETH = WETH_;
        v2NFTXFactory = v2NFTXFactory_;
        v2Inventory = v2Inventory_;
        sushiRouter = sushiRouter_;
        positionManager = positionManager_;
        v3NFTXFactory = v3NFTXFactory_;
        v3Inventory = v3Inventory_;
        WETH_.approve(address(positionManager_), type(uint256).max);
    }
    function sushiToNFTXAMM(SushiToNFTXAMMParams calldata params) external returns (uint256 positionId) {
        if (params.permitSig.length > 0) {
            _permit(params.sushiPair, params.lpAmount, params.permitSig);
        }
        uint256 wethBalance;
        address vTokenV3;
        uint256 vTokenV3Balance;
        {
            uint256 vTokenV2Balance;
            (vTokenV2Balance, wethBalance) = _withdrawFromSushi(params.sushiPair, params.lpAmount, params.vTokenV2);
            uint256 wethReceived;
            (vTokenV3, vTokenV3Balance, wethReceived) = _v2ToV3Vault(
                params.vTokenV2,
                vTokenV2Balance,
                params.idsToRedeem,
                params.vaultIdV3,
                params.is1155,
                0
            );
            wethBalance += wethReceived;
        }
        bool isVTokenV30 = vTokenV3 < address(WETH);
        (address token0, address token1, uint256 amount0, uint256 amount1) = isVTokenV30 ? (vTokenV3, address(WETH), vTokenV3Balance, wethBalance) : (address(WETH), vTokenV3, wethBalance, vTokenV3Balance);
        positionManager.createAndInitializePoolIfNecessary(token0, token1, params.fee, params.sqrtPriceX96);
        TransferLib.unSafeMaxApprove(vTokenV3, address(positionManager), vTokenV3Balance);
        uint256 newAmount0;
        uint256 newAmount1;
        (positionId, , newAmount0, newAmount1) = positionManager.mint(INonfungiblePositionManager.MintParams({token0: token0, token1: token1, fee: params.fee, tickLower: params.tickLower, tickUpper: params.tickUpper, amount0Desired: amount0, amount1Desired: amount1, amount0Min: params.amount0Min, amount1Min: params.amount1Min, recipient: msg.sender, deadline: params.deadline}));
        if (newAmount0 < amount0) {
            IERC20(token0).transfer(msg.sender, amount0 - newAmount0);
        }
        if (newAmount1 < amount1) {
            IERC20(token1).transfer(msg.sender, amount1 - newAmount1);
        }
    }
    function v2InventoryToXNFT(uint256 vaultIdV2, uint256 shares, uint256[] calldata idsToRedeem, bool is1155, uint256 vaultIdV3, uint256 minWethToReceive) external returns (uint256 xNFTId) {
        address xToken = v2Inventory.vaultXToken(vaultIdV2);
        IERC20(xToken).transferFrom(msg.sender, address(this), shares);
        v2Inventory.withdraw(vaultIdV2, shares);
        address vTokenV2 = v2NFTXFactory.vault(vaultIdV2);
        uint256 vTokenV2Balance = IERC20(vTokenV2).balanceOf(address(this));
        (address vTokenV3, uint256 vTokenV3Balance, uint256 wethReceived) = _v2ToV3Vault(vTokenV2, vTokenV2Balance, idsToRedeem, vaultIdV3, is1155, minWethToReceive);
        if (wethReceived > 0) {
            WETH.transfer(msg.sender, wethReceived);
        }
        TransferLib.unSafeMaxApprove(vTokenV3, address(v3Inventory), vTokenV3Balance);
        xNFTId = v3Inventory.deposit(vaultIdV3, vTokenV3Balance, msg.sender, "", false, false);
    }
    function v2VaultToXNFT(address vTokenV2, uint256 vTokenV2Balance, uint256[] calldata idsToRedeem, bool is1155, uint256 vaultIdV3, uint256 minWethToReceive) external returns (uint256 xNFTId) {
        IERC20(vTokenV2).transferFrom(msg.sender, address(this), vTokenV2Balance);
        (address vTokenV3, uint256 vTokenV3Balance, uint256 wethReceived) = _v2ToV3Vault(vTokenV2, vTokenV2Balance, idsToRedeem, vaultIdV3, is1155, minWethToReceive);
        if (wethReceived > 0) {
            WETH.transfer(msg.sender, wethReceived);
        }
        TransferLib.unSafeMaxApprove(vTokenV3, address(v3Inventory), vTokenV3Balance);
        xNFTId = v3Inventory.deposit(vaultIdV3, vTokenV3Balance, msg.sender, "", false, false);
    }
    function _permit(address sushiPair, uint256 lpAmount, bytes memory permitSig) internal {
        if (permitSig.length != 65) revert InvalidSignatureLength();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(permitSig, 32))
            s := mload(add(permitSig, 64))
            v := byte(0, mload(add(permitSig, 96)))
        }
        IUniswapV2Pair(sushiPair).permit(msg.sender, address(this), lpAmount, DEADLINE, v, r, s);
    }
    function _withdrawFromSushi(address sushiPair, uint256 lpAmount, address vTokenV2) internal returns (uint256 vTokenV2Balance, uint256 wethBalance) {
        IUniswapV2Pair(sushiPair).transferFrom(msg.sender, sushiPair, lpAmount);
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(sushiPair).burn(address(this));
        bool isVTokenV20 = vTokenV2 < address(WETH);
        (vTokenV2Balance, wethBalance) = isVTokenV20 ? (amount0, amount1) : (amount1, amount0);
    }
    function _v2ToV3Vault(address vTokenV2, uint256 vTokenV2Balance, uint256[] calldata idsToRedeem, uint256 vaultIdV3, bool is1155, uint256 minWethToReceive) internal returns (address vTokenV3, uint256 vTokenV3Balance, uint256 wethReceived) {
        vTokenV3 = v3NFTXFactory.vault(vaultIdV3);
        uint256[] memory idsRedeemed = INFTXVaultV2(vTokenV2).redeemTo(vTokenV2Balance / 1 ether, idsToRedeem, is1155 ? address(this) : vTokenV3);
        if (is1155) {
            IERC1155(INFTXVaultV3(vTokenV3).assetAddress()).setApprovalForAll(vTokenV3, true);
        }
        vTokenV2Balance = vTokenV2Balance % 1 ether;
        if (vTokenV2Balance > DUST_THRESHOLD) {
            address[] memory path = new address[](2);
            path[0] = vTokenV2;
            path[1] = address(WETH);
            TransferLib.unSafeMaxApprove(vTokenV2, address(sushiRouter), vTokenV2Balance);
            wethReceived = sushiRouter.swapExactTokensForTokens(vTokenV2Balance, minWethToReceive, path, address(this), block.timestamp)[path.length - 1];
        } else if (vTokenV2Balance > 0) {
            IERC20(vTokenV2).transfer(msg.sender, vTokenV2Balance);
        }
        uint256[] memory amounts;
        if (is1155) {
            amounts = new uint256[](idsRedeemed.length);
            for (uint256 i; i < idsRedeemed.length; ) {
                amounts[i] = 1;
                unchecked {
                    ++i;
                }
            }
        }
        vTokenV3Balance = INFTXVaultV3(vTokenV3).mint(idsRedeemed, amounts, msg.sender, address(this));
    }
}
