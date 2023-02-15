// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;
pragma abicoder v2;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {IUniswapV3Factory} from "@uni-core/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uni-periphery/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter, SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {IQuoterV2} from "@uni-periphery/interfaces/IQuoterV2.sol";
import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {PoolAddress} from "@uni-periphery/libraries/PoolAddress.sol";

import {vToken} from "@mocks/vToken.sol";

/**
 * @notice Intermediate Router to facilitate minting + concentrated liquidity addition (and reverse)
 */
contract NFTXRouter is ERC721Holder {
    INonfungiblePositionManager public positionManager;
    SwapRouter public router;
    IQuoterV2 public quoter;
    IERC721 public nft;
    // TODO: make vtoken dynamic
    vToken public vtoken;
    address public immutable WETH;

    bool public isVToken0; // check if vToken would be token0
    address token0;
    address token1;

    uint24 public constant FEE = 10000;

    error UnableToSendETH();

    constructor(
        INonfungiblePositionManager positionManager_,
        SwapRouter router_,
        IQuoterV2 quoter_,
        IERC721 nft_,
        vToken vtoken_
    ) {
        positionManager = positionManager_;
        router = router_;
        quoter = quoter_;
        nft = nft_;
        vtoken = vtoken_;

        WETH = positionManager_.WETH9();

        if (address(vtoken_) < WETH) {
            isVToken0 = true;
            token0 = address(vtoken_);
            token1 = WETH;
        } else {
            token0 = WETH;
            token1 = address(vtoken_);
        }
    }

    struct AddLiquidityParams {
        uint256[] nftIds;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
        uint256 deadline;
    }

    /**
     * @notice User should have given NFT approval to vtoken contract, else revert
     */
    function addLiquidity(AddLiquidityParams calldata params)
        external
        payable
        returns (uint256 positionId)
    {
        uint256 vTokensAmount = vtoken.mint(
            params.nftIds,
            msg.sender,
            address(this)
        );
        vtoken.approve(address(positionManager), vTokensAmount);

        // cache
        address token0_ = token0;
        address token1_ = token1;

        positionManager.createAndInitializePoolIfNecessary(
            token0_,
            token1_,
            FEE,
            params.sqrtPriceX96
        );

        // mint position with vtoken and ETH
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        if (isVToken0) {
            amount0Desired = vTokensAmount;
            amount0Min = amount0Desired;
            amount1Desired = msg.value;
        } else {
            amount0Desired = msg.value;
            amount1Desired = vTokensAmount;
            amount1Min = amount1Min;
        }

        (positionId, , , ) = positionManager.mint{value: msg.value}(
            INonfungiblePositionManager.MintParams({
                token0: token0_,
                token1: token1_,
                fee: FEE,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: msg.sender,
                deadline: params.deadline
            })
        );

        positionManager.refundETH(msg.sender);
    }

    struct RemoveLiquidityParams {
        uint256 positionId;
        uint256[] nftIds;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function removeLiquidity(RemoveLiquidityParams calldata params) external {
        // remove liquidity to get vTokens and ETH
        positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: params.positionId,
                liquidity: params.liquidity,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                deadline: params.deadline
            })
        );

        // collect vtokens & weth from removing liquidity + earned fees
        (uint256 amount0, uint256 amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: params.positionId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        uint256 vTokenAmt;
        uint256 wethAmt;
        if (isVToken0) {
            vTokenAmt = amount0;
            wethAmt = amount1;
        } else {
            wethAmt = amount0;
            vTokenAmt = amount1;
        }

        // TODO: make this optional. User can want vTokens
        // swap decimal part of vTokens to WETH
        uint256 fractionalVTokenAmt = vTokenAmt % 1 ether;
        if (fractionalVTokenAmt > 0) {
            vtoken.approve(address(router), fractionalVTokenAmt);
            uint256 fractionalWethAmt = router.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(vtoken),
                    tokenOut: WETH,
                    fee: FEE,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: fractionalVTokenAmt,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
            wethAmt += fractionalWethAmt;
        }
        // send all ETH to sender
        IWETH9(WETH).withdraw(wethAmt);
        (bool success, ) = msg.sender.call{value: wethAmt}("");
        if (!success) revert UnableToSendETH();
        // burn vTokens to provided tokenIds array
        vtoken.burn(params.nftIds, address(this), msg.sender);

        // TODO: handle vtoken left (if any)
    }

    /**
     * @param sqrtPriceLimitX96 the price limit, if reached, stop swapping
     */
    struct SellNFTsParams {
        uint256[] nftIds;
        uint256 deadline;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @notice User should have given NFT approval to vtoken contract, else revert
     */
    function sellNFTs(SellNFTsParams calldata params)
        external
        returns (uint256 wethReceived)
    {
        uint256 vTokensAmount = vtoken.mint(
            params.nftIds,
            msg.sender,
            address(this)
        );
        vtoken.approve(address(router), vTokensAmount);

        wethReceived = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(vtoken),
                tokenOut: WETH,
                fee: FEE,
                recipient: address(this),
                deadline: params.deadline,
                amountIn: vTokensAmount,
                amountOutMinimum: params.amountOutMinimum,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // convert WETH to ETH & send to user
        IWETH9(WETH).withdraw(wethReceived);
        (bool success, ) = msg.sender.call{value: wethReceived}("");
        if (!success) revert UnableToSendETH();
    }

    /**
     * @param sqrtPriceLimitX96 the price limit, if reached, stop swapping
     */
    struct BuyNFTsParams {
        uint256[] nftIds;
        uint256 deadline;
        uint160 sqrtPriceLimitX96;
    }

    function buyNFTs(BuyNFTsParams calldata params) external payable {
        uint256 vTokenAmt = params.nftIds.length * 1 ether;

        // swap ETH to required vTokens amount
        router.exactOutputSingle{value: msg.value}(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: WETH,
                tokenOut: address(vtoken),
                fee: FEE,
                recipient: address(this),
                deadline: params.deadline,
                amountOut: vTokenAmt,
                amountInMaximum: msg.value,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // unwrap vTokens to tokenIds specified, and send to sender
        vtoken.burn(params.nftIds, address(this), msg.sender);

        // refund ETH
        router.refundETH(msg.sender);
    }

    /**
     * @dev These functions are not gas efficient and should _not_ be called on chain. Instead, optimistically execute
     * the swap and check the amounts in the callback.
     */
    function quoteBuyNFTs(uint256[] memory nftIds, uint160 sqrtPriceLimitX96)
        external
        returns (uint256 ethRequired)
    {
        uint256 vTokenAmt = nftIds.length * 1 ether;

        (ethRequired, , , ) = quoter.quoteExactOutputSingle(
            IQuoterV2.QuoteExactOutputSingleParams({
                tokenIn: WETH,
                tokenOut: address(vtoken),
                amount: vTokenAmt,
                fee: FEE,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
        );
    }

    /**
     * @notice Get deployed pool address for vToken. Reverts if pool doesn't exist
     */
    function getPool(address vToken_) external view returns (address pool) {
        pool = IUniswapV3Factory(router.factory()).getPool(vToken_, WETH, FEE);
        if (pool == address(0)) revert();
    }

    /**
     * @notice Compute the pool address corresponding to vToken
     */
    function computePool(address vToken_) external view returns (address) {
        return
            PoolAddress.computeAddress(
                router.factory(),
                PoolAddress.getPoolKey(vToken_, WETH, FEE)
            );
    }

    receive() external payable {}
}
