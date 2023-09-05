// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {INonfungiblePositionManager} from "@uni-periphery/interfaces/INonfungiblePositionManager.sol";
import {SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {IQuoterV2} from "@uni-periphery/interfaces/IQuoterV2.sol";
import {INFTXInventoryStakingV3} from "@src/interfaces/INFTXInventoryStakingV3.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/external/IPermitAllowanceTransfer.sol";

import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";

interface INFTXRouter {
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    function WETH() external returns (address);

    function PERMIT2() external returns (IPermitAllowanceTransfer);

    function positionManager() external returns (INonfungiblePositionManager);

    function router() external returns (SwapRouter);

    function quoter() external returns (IQuoterV2);

    function nftxVaultFactory() external returns (INFTXVaultFactoryV3);

    function inventoryStaking() external returns (INFTXInventoryStakingV3);

    // =============================================================
    //                           STORAGE
    // =============================================================

    function lpTimelock() external returns (uint256);

    function earlyWithdrawPenaltyInWei() external returns (uint256);

    /// @notice the dust threshold for vTokens above which the additional vTokens minted during add/increase liquidity are put into inventory staking.
    function vTokenDustThreshold() external returns (uint256);

    // =============================================================
    //                            EVENTS
    // =============================================================

    event AddLiquidity(
        uint256 indexed positionId,
        uint256 vaultId,
        uint256 vTokensAmount,
        uint256[] nftIds,
        address pool
    );

    event RemoveLiquidity(
        uint256 indexed positionId,
        uint256 vaultId,
        uint256 vTokenAmt,
        uint256 wethAmt
    );

    event IncreaseLiquidity(
        uint256 indexed positionId,
        uint256 vaultId,
        uint256 vTokensAmount,
        uint256[] nftIds
    );

    event SellNFTs(uint256 nftCount, uint256 ethReceived);

    event BuyNFTs(uint256 nftCount, uint256 ethSpent);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidEarlyWithdrawPenalty();
    error InsufficientVTokens();
    error ETHValueLowerThanMin();
    error NoETHFundsNeeded();
    error NotPositionOwner();
    error ZeroLPTimelock();

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    struct AddLiquidityParams {
        uint256 vaultId;
        // amount of vTokens to deposit (can be 0)
        uint256 vTokensAmount;
        // array of nft ids to deposit (can be empty)
        uint256[] nftIds;
        // for ERC1155: quantity corresponding to each tokenId to deposit
        uint256[] nftAmounts;
        // ticks range to provide the liquidity into
        int24 tickLower;
        int24 tickUpper;
        // fee tier of the AMM pool
        uint24 fee;
        // the initial sqrt price (as a Q64.96) to set if a new pool is deployed
        uint160 sqrtPriceX96;
        // Minimum amount of vTokens to be provided as liquidity
        uint256 vTokenMin;
        // Minimum amount of Weth to be provided as liquidity
        uint256 wethMin;
        // deadline after which the tx fails
        uint256 deadline;
        // Forcefully apply timelock to the position
        bool forceTimelock;
    }

    /**
     * @notice Adds liquidity to the NFTX AMM. Deploys new AMM pool if doesn't already exist. User can addLiquidity via vTokens, NFTs or both. Timelock is set for the position if NFTs deposited.
     */
    function addLiquidity(
        AddLiquidityParams calldata params
    ) external payable returns (uint256 positionId);

    /**
     * @notice Adds liquidity to the NFTX AMM. Deploys new AMM pool if doesn't already exist. User can deposit via vTokens, NFTs or both. Timelock is set for the position if NFTs deposited.
     *
     * @param encodedPermit2 Encoded function params (owner, permitSingle, signature) for `PERMIT2.permit()` to permit vToken
     */
    function addLiquidityWithPermit2(
        AddLiquidityParams calldata params,
        bytes calldata encodedPermit2
    ) external payable returns (uint256 positionId);

    struct IncreaseLiquidityParams {
        // the liquidity position to update
        uint256 positionId;
        // vault id corresponding to the vTokens in this position
        uint256 vaultId;
        // amount of vTokens to deposit (can be 0)
        uint256 vTokensAmount;
        // array of nft ids to deposit (can be empty)
        uint256[] nftIds;
        // for ERC1155: quantity corresponding to each tokenId to deposit
        uint256[] nftAmounts;
        // Minimum amount of vTokens to be provided as liquidity
        uint256 vTokenMin;
        // Minimum amount of Weth to be provided as liquidity
        uint256 wethMin;
        // deadline after which the tx fails
        uint256 deadline;
        // Forcefully apply timelock to the position
        bool forceTimelock;
    }

    /**
     * @notice Increase liquidity of an existing position. User can deposit via vTokens, NFTs or both. Timelock is updated for the position if NFTs deposited.
     */
    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    ) external payable;

    /**
     * @notice Increase liquidity of an existing position. User can deposit via vTokens, NFTs or both. Timelock is updated for the position if NFTs deposited.
     *
     * @param encodedPermit2 Encoded function params (owner, permitSingle, signature) for `PERMIT2.permit()` to permit vToken
     */
    function increaseLiquidityWithPermit2(
        IncreaseLiquidityParams calldata params,
        bytes calldata encodedPermit2
    ) external payable;

    struct RemoveLiquidityParams {
        // the position id to withdraw liquidity from
        uint256 positionId;
        // vault id corresponding to the vTokens in this position
        uint256 vaultId;
        // array of nft ids to redeem with the vTokens (can be empty to just receive vTokens)
        uint256[] nftIds;
        // The max net premium in vTokens the user is willing to pay to redeem nftIds, else tx reverts
        uint256 vTokenPremiumLimit;
        // the liquidity amount to burn and withdraw
        uint128 liquidity;
        // Minimum amount of token0 to be withdrawn
        uint256 amount0Min;
        // Minimum amount of token1 to be withdrawn
        uint256 amount1Min;
        // deadline after which the tx fails
        uint256 deadline;
    }

    /**
     * Remove liquidity from position into ETH + vTokens or NFTs or a combination of both. ETH from the withdrawn liquidity and msg.value is used to pay for redeem fees if NFTs withdrawn.
     */
    function removeLiquidity(
        RemoveLiquidityParams calldata params
    ) external payable;

    struct SellNFTsParams {
        // vault id corresponding to the nfts being sold
        uint256 vaultId;
        // array of nft ids to sell
        uint256[] nftIds;
        // for ERC1155: quantity corresponding to each tokenId to sell
        uint256[] nftAmounts;
        // deadline after which the tx fails
        uint256 deadline;
        // the fee tier to execute the swap through
        uint24 fee;
        // minimum amount of ETH to receive after swap (without considering any mint fees)
        uint256 amountOutMinimum;
        // the price limit (as a Q64.96), if reached, to stop swapping
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @notice Sell NFT ids into ETH via the given fee tier pool. Extra ETH sent as msg.value if the received WETH is insufficient to pay for the vault fees.
     */
    function sellNFTs(
        SellNFTsParams calldata params
    ) external payable returns (uint256 ethReceived);

    struct BuyNFTsParams {
        // vault id corresponding to the nfts being bought
        uint256 vaultId;
        // array of nft ids to buy
        uint256[] nftIds;
        // The max net premium in vTokens the user is willing to pay to redeem nftIds, else tx reverts
        uint256 vTokenPremiumLimit;
        // deadline after which the tx fails
        uint256 deadline;
        // the fee tier to execute the swap through
        uint24 fee;
        // the price limit (as a Q64.96), if reached, to stop swapping
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @notice Buy NFT ids with ETH via the given fee tier pool. ETH sent as msg.value includes the amount to swap for vTokens + vault redeem fees (including premiums).
     */
    function buyNFTs(BuyNFTsParams calldata params) external payable;

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    /**
     * @param token ERC20 token address or address(0) in case of ETH
     */
    function rescueTokens(IERC20 token) external;

    function setLpTimelock(uint256 lpTimelock_) external;

    function setVTokenDustThreshold(uint256 vTokenDustThreshold_) external;

    function setEarlyWithdrawPenalty(
        uint256 earlyWithdrawPenaltyInWei_
    ) external;

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
