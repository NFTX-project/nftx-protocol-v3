// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {INonfungiblePositionManager} from "@uni-periphery/interfaces/INonfungiblePositionManager.sol";
import {SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {IQuoterV2} from "@uni-periphery/interfaces/IQuoterV2.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";

import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";

interface INFTXRouter {
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    function WETH() external returns (address);

    function PERMIT2() external returns (IPermitAllowanceTransfer);

    function positionManager() external returns (INonfungiblePositionManager);

    function router() external returns (SwapRouter);

    function quoter() external returns (IQuoterV2);

    function nftxVaultFactory() external returns (INFTXVaultFactory);

    // =============================================================
    //                            EVENTS
    // =============================================================

    event AddLiquidity(
        uint256 vaultId,
        uint256 vTokensAmount,
        uint256 nftCount,
        uint256 positionId
    );

    event RemoveLiquidity(
        uint256 positionId,
        uint256 vaultId,
        uint256 vTokenAmt,
        uint256 wethAmt
    );

    event SellNFTs(uint256 nftCount, uint256 ethReceived);

    event BuyNFTs(uint256 nftCount, uint256 ethSpent);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error UnableToSendETH();

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    struct AddLiquidityParams {
        uint256 vaultId;
        uint256 vTokensAmount; // user can provide just vTokens or NFTs or both
        uint256[] nftIds;
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
        uint160 sqrtPriceX96;
        uint256 deadline;
    }

    function addLiquidity(
        AddLiquidityParams calldata params
    ) external payable returns (uint256 positionId);

    function addLiquidityWithPermit2(
        AddLiquidityParams calldata params,
        bytes calldata encodedPermit2
    ) external payable returns (uint256 positionId);

    struct RemoveLiquidityParams {
        uint256 positionId;
        uint256 vaultId;
        uint256[] nftIds;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function removeLiquidity(
        RemoveLiquidityParams calldata params
    ) external payable;

    /**
     * @param sqrtPriceLimitX96 the price limit, if reached, stop swapping
     */
    struct SellNFTsParams {
        uint256 vaultId;
        uint256[] nftIds;
        uint256 deadline;
        uint24 fee;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function sellNFTs(
        SellNFTsParams calldata params
    ) external payable returns (uint256 wethReceived);

    /**
     * @param sqrtPriceLimitX96 the price limit, if reached, stop swapping
     */
    struct BuyNFTsParams {
        uint256 vaultId;
        uint256[] nftIds;
        uint256 deadline;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function buyNFTs(BuyNFTsParams calldata params) external payable;

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    /**
     * @param token ERC20 token address or address(0) in case of ETH
     */
    function rescueTokens(IERC20 token) external;

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    /**
     * @dev This function is not gas efficient and should _not_ be called on chain.
     */
    function quoteBuyNFTs(
        address vtoken,
        uint256 nftsCount,
        uint24 fee,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 ethRequired);

    /**
     * @notice Get deployed pool address for vaultId. `exists` is false if pool doesn't exist. `vaultId` must be valid.
     */
    function getPoolExists(
        uint256 vaultId,
        uint24 fee
    ) external view returns (address pool, bool exists);

    /**
     * @notice Get deployed pool address for vToken. `exists` is false if pool doesn't exist.
     */
    function getPoolExists(
        address vToken_,
        uint24 fee
    ) external view returns (address pool, bool exists);

    /**
     * @notice Get deployed pool address for vToken. Reverts if pool doesn't exist
     */
    function getPool(
        address vToken_,
        uint24 fee
    ) external view returns (address pool);

    /**
     * @notice Compute the pool address corresponding to vToken
     */
    function computePool(
        address vToken_,
        uint24 fee
    ) external view returns (address);

    /**
     * @notice Checks if vToken is token0 or not
     */
    function isVToken0(address vtoken) external view returns (bool);
}
