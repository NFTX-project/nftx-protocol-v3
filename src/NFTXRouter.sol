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

    address public immutable WETH;

    uint24 public constant FEE = 10000;

    error UnableToSendETH();

    constructor(
        INonfungiblePositionManager positionManager_,
        SwapRouter router_,
        IQuoterV2 quoter_
    ) {
        positionManager = positionManager_;
        router = router_;
        quoter = quoter_;

        WETH = positionManager_.WETH9();
    }

    struct AddLiquidityParams {
        address vtoken;
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
        uint256 vTokensAmount = vToken(params.vtoken).mint(
            params.nftIds,
            msg.sender,
            address(this)
        );
        vToken(params.vtoken).approve(address(positionManager), vTokensAmount);

        bool _isVToken0 = isVToken0(params.vtoken);
        address token0 = _isVToken0 ? params.vtoken : WETH;
        address token1 = _isVToken0 ? WETH : params.vtoken;

        positionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            FEE,
            params.sqrtPriceX96
        );

        // mint position with vtoken and ETH
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        if (_isVToken0) {
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
                token0: token0,
                token1: token1,
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
        address vtoken;
        uint256[] nftIds;
        bool receiveVTokens; // directly receive vTokens, instead of redeeming for NFTs
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

        bool _isVToken0 = isVToken0(params.vtoken);
        uint256 vTokenAmt = _isVToken0 ? amount0 : amount1;
        uint256 wethAmt = _isVToken0 ? amount1 : amount0;

        if (params.receiveVTokens) {
            vToken(params.vtoken).transfer(msg.sender, vTokenAmt);
        } else {
            // swap decimal part of vTokens to WETH
            uint256 fractionalVTokenAmt = vTokenAmt % 1 ether;
            if (fractionalVTokenAmt > 0) {
                vToken(params.vtoken).approve(
                    address(router),
                    fractionalVTokenAmt
                );
                uint256 fractionalWethAmt = router.exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: address(params.vtoken),
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

                // burn vTokens to provided tokenIds array
                uint256 vTokenBurned = vToken(params.vtoken).burn(
                    params.nftIds,
                    address(this),
                    msg.sender
                );

                // if more vTokens collected than burned
                uint256 vTokenResidue = vTokenAmt -
                    fractionalVTokenAmt -
                    vTokenBurned;

                if (vTokenResidue > 0) {
                    vToken(params.vtoken).transfer(msg.sender, vTokenResidue);
                }
            }
        }
        // send all ETH to sender
        IWETH9(WETH).withdraw(wethAmt);
        (bool success, ) = msg.sender.call{value: wethAmt}("");
        if (!success) revert UnableToSendETH();
    }

    /**
     * @param sqrtPriceLimitX96 the price limit, if reached, stop swapping
     */
    struct SellNFTsParams {
        address vtoken;
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
        uint256 vTokensAmount = vToken(params.vtoken).mint(
            params.nftIds,
            msg.sender,
            address(this)
        );
        vToken(params.vtoken).approve(address(router), vTokensAmount);

        wethReceived = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(params.vtoken),
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
        address vtoken;
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
                tokenOut: address(params.vtoken),
                fee: FEE,
                recipient: address(this),
                deadline: params.deadline,
                amountOut: vTokenAmt,
                amountInMaximum: msg.value,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // unwrap vTokens to tokenIds specified, and send to sender
        vToken(params.vtoken).burn(params.nftIds, address(this), msg.sender);

        // refund ETH
        router.refundETH(msg.sender);
    }

    /**
     * @dev These functions are not gas efficient and should _not_ be called on chain. Instead, optimistically execute
     * the swap and check the amounts in the callback.
     */
    function quoteBuyNFTs(
        address vtoken,
        uint256[] memory nftIds,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 ethRequired) {
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
     * @notice Get deployed pool address for vaultId. `exists` is false if pool doesn't exist
     */
    function getPoolExists(uint256 vaultId)
        external
        view
        returns (address pool, bool exists)
    {
        // TODO: get vToken address from vaultId via NFTXVaultFactory
        address vToken_;
        pool = IUniswapV3Factory(router.factory()).getPool(vToken_, WETH, FEE);

        exists = pool != address(0);
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

    /**
     * @notice Checks if vToken is token0 or not
     */
    function isVToken0(address vtoken) public view returns (bool) {
        return vtoken < WETH;
    }

    // TODO: add function to rescueTokens + ETH

    receive() external payable {}
}
