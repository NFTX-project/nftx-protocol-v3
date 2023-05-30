// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3Factory} from "@uni-core/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uni-periphery/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter, SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {IQuoterV2} from "@uni-periphery/interfaces/IQuoterV2.sol";
import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {PoolAddress} from "@uni-periphery/libraries/PoolAddress.sol";

import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";
import {INFTXVault} from "@src/v2/interface/INFTXVault.sol";

import {INFTXRouter} from "./interfaces/INFTXRouter.sol";

/**
 * @title NFTX Router
 * @author @apoorvlathey
 *
 * @notice Router to facilitate vault tokens minting/burning + addition/removal of concentrated liquidity
 */
contract NFTXRouter is INFTXRouter, Ownable, ERC721Holder {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    address public immutable override WETH;

    // Set a constant address for specific contracts that need special logic
    address public constant override CRYPTO_PUNKS =
        0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;

    INonfungiblePositionManager public immutable override positionManager;
    SwapRouter public immutable override router;
    IQuoterV2 public immutable override quoter;
    INFTXVaultFactory public immutable override nftxVaultFactory;

    // TODO: add events for each operation

    constructor(
        INonfungiblePositionManager positionManager_,
        SwapRouter router_,
        IQuoterV2 quoter_,
        INFTXVaultFactory nftxVaultFactory_
    ) {
        positionManager = positionManager_;
        router = router_;
        quoter = quoter_;
        nftxVaultFactory = nftxVaultFactory_;

        WETH = positionManager_.WETH9();
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    /**
     * @inheritdoc INFTXRouter
     */
    function addLiquidity(
        AddLiquidityParams calldata params
    ) external payable override returns (uint256 positionId) {
        uint256 vTokensAmount = params.vTokensAmount;
        if (vTokensAmount > 0) {
            INFTXVault(params.vtoken).transferFrom(
                msg.sender,
                address(this),
                vTokensAmount
            );
        }

        if (params.nftIds.length > 0) {
            address assetAddress = INFTXVault(params.vtoken).assetAddress();

            // tranfer NFTs from user to the vault
            for (uint256 i; i < params.nftIds.length; ) {
                _transferFromERC721(
                    assetAddress,
                    params.nftIds[i],
                    params.vtoken
                );

                if (assetAddress == CRYPTO_PUNKS) {
                    _approveCryptoPunkERC721(
                        assetAddress,
                        params.nftIds[i],
                        params.vtoken
                    );
                }

                unchecked {
                    ++i;
                }
            }

            uint256[] memory emptyIds;
            vTokensAmount +=
                INFTXVault(params.vtoken).mint(params.nftIds, emptyIds) *
                1 ether;
        }

        INFTXVault(params.vtoken).approve(
            address(positionManager),
            vTokensAmount
        );

        bool _isVToken0 = isVToken0(params.vtoken);
        (address token0, address token1) = _isVToken0
            ? (params.vtoken, WETH)
            : (WETH, params.vtoken);

        positionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            params.fee,
            params.sqrtPriceX96
        );

        // mint position with vtoken and ETH
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        if (_isVToken0) {
            amount0Desired = vTokensAmount;
            // have a 5000 wei buffer to account for any dust amounts
            amount0Min = vTokensAmount > 5000 ? vTokensAmount - 5000 : 0;
            amount1Desired = msg.value;
        } else {
            amount0Desired = msg.value;
            amount1Desired = vTokensAmount;
            // have a 5000 wei buffer to account for any dust amounts
            amount1Min = vTokensAmount > 5000 ? vTokensAmount - 5000 : 0;
        }

        (positionId, , , ) = positionManager.mint{value: msg.value}(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: params.fee,
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
        // refund vTokens dust (if any left)
        uint256 vTokenBalance = INFTXVault(params.vtoken).balanceOf(
            address(this)
        );
        if (vTokenBalance > 0) {
            INFTXVault(params.vtoken).transfer(msg.sender, vTokenBalance);
        }
    }

    function removeLiquidity(
        RemoveLiquidityParams calldata params
    ) external override {
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
        (uint256 vTokenAmt, uint256 wethAmt) = _isVToken0
            ? (amount0, amount1)
            : (amount1, amount0);

        if (params.receiveVTokens) {
            INFTXVault(params.vtoken).transfer(msg.sender, vTokenAmt);
        } else {
            // burn vTokens to provided tokenIds array
            INFTXVault(params.vtoken).redeemTo(params.nftIds, msg.sender);
            uint256 vTokenBurned = params.nftIds.length * 1 ether;

            // if more vTokens collected than burned
            uint256 vTokenResidue = vTokenAmt - vTokenBurned;

            if (vTokenResidue > 0) {
                INFTXVault(params.vtoken).transfer(msg.sender, vTokenResidue);
            }
        }
        // send all ETH to sender
        IWETH9(WETH).withdraw(wethAmt);
        (bool success, ) = msg.sender.call{value: wethAmt}("");
        if (!success) revert UnableToSendETH();
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function sellNFTs(
        SellNFTsParams calldata params
    ) external override returns (uint256 wethReceived) {
        address assetAddress = INFTXVault(params.vtoken).assetAddress();

        // tranfer NFTs from user to the vault
        for (uint256 i; i < params.nftIds.length; ) {
            _transferFromERC721(assetAddress, params.nftIds[i], params.vtoken);

            if (assetAddress == CRYPTO_PUNKS) {
                _approveCryptoPunkERC721(
                    assetAddress,
                    params.nftIds[i],
                    params.vtoken
                );
            }

            unchecked {
                ++i;
            }
        }

        // mint vToken
        uint256[] memory emptyIds;
        uint256 vTokensAmount = INFTXVault(params.vtoken).mint(
            params.nftIds,
            emptyIds
        ) * 1 ether;

        INFTXVault(params.vtoken).approve(address(router), vTokensAmount);

        wethReceived = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(params.vtoken),
                tokenOut: WETH,
                fee: params.fee,
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

    function buyNFTs(BuyNFTsParams calldata params) external payable override {
        uint256 vTokenAmt = params.nftIds.length * 1 ether;

        // swap ETH to required vTokens amount
        router.exactOutputSingle{value: msg.value}(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: WETH,
                tokenOut: address(params.vtoken),
                fee: params.fee,
                recipient: address(this),
                deadline: params.deadline,
                amountOut: vTokenAmt,
                amountInMaximum: msg.value,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // unwrap vTokens to tokenIds specified, and send to sender
        INFTXVault(params.vtoken).redeemTo(params.nftIds, msg.sender);

        // refund ETH
        router.refundETH(msg.sender);
    }

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    /**
     * @inheritdoc INFTXRouter
     */
    function rescueTokens(IERC20 token) external override onlyOwner {
        if (address(token) != address(0)) {
            uint256 balance = token.balanceOf(address(this));
            token.safeTransfer(msg.sender, balance);
        } else {
            uint256 balance = address(this).balance;
            (bool success, ) = msg.sender.call{value: balance}("");
            if (!success) revert UnableToSendETH();
        }
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    /**
     * @inheritdoc INFTXRouter
     */
    function quoteBuyNFTs(
        address vtoken,
        uint256[] memory nftIds,
        uint24 fee,
        uint160 sqrtPriceLimitX96
    ) external override returns (uint256 ethRequired) {
        uint256 vTokenAmt = nftIds.length * 1 ether;

        (ethRequired, , , ) = quoter.quoteExactOutputSingle(
            IQuoterV2.QuoteExactOutputSingleParams({
                tokenIn: WETH,
                tokenOut: address(vtoken),
                amount: vTokenAmt,
                fee: fee,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
        );
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function getPoolExists(
        uint256 vaultId,
        uint24 fee
    ) external view override returns (address pool, bool exists) {
        address vToken_ = nftxVaultFactory.vault(vaultId);
        pool = IUniswapV3Factory(router.factory()).getPool(vToken_, WETH, fee);

        exists = pool != address(0);
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function getPoolExists(
        address vToken_,
        uint24 fee
    ) external view override returns (address pool, bool exists) {
        pool = IUniswapV3Factory(router.factory()).getPool(vToken_, WETH, fee);

        exists = pool != address(0);
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function getPool(
        address vToken_,
        uint24 fee
    ) external view override returns (address pool) {
        pool = IUniswapV3Factory(router.factory()).getPool(vToken_, WETH, fee);
        if (pool == address(0)) revert();
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function computePool(
        address vToken_,
        uint24 fee
    ) external view override returns (address) {
        return
            PoolAddress.computeAddress(
                router.factory(),
                PoolAddress.getPoolKey(vToken_, WETH, fee)
            );
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function isVToken0(address vtoken) public view override returns (bool) {
        return vtoken < WETH;
    }

    // =============================================================
    //                      INTERNAL / PRIVATE
    // =============================================================

    /**
     * @notice Transfers sender's ERC721 tokens to a specified recipient.
     *
     * @param assetAddr Address of the asset being transferred
     * @param tokenId The ID of the token being transferred
     * @param to The address the token is being transferred to
     */

    function _transferFromERC721(
        address assetAddr,
        uint256 tokenId,
        address to
    ) internal virtual {
        bytes memory data;

        if (assetAddr != CRYPTO_PUNKS) {
            // We push to the vault to avoid an unneeded transfer.
            data = abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)",
                msg.sender,
                to,
                tokenId
            );
        } else {
            // Fix here for frontrun attack.
            bytes memory punkIndexToAddress = abi.encodeWithSignature(
                "punkIndexToAddress(uint256)",
                tokenId
            );
            (bool checkSuccess, bytes memory result) = address(assetAddr)
                .staticcall(punkIndexToAddress);
            address nftOwner = abi.decode(result, (address));
            require(
                checkSuccess && nftOwner == msg.sender,
                "Not the NFT owner"
            );
            data = abi.encodeWithSignature("buyPunk(uint256)", tokenId);
        }

        (bool success, bytes memory resultData) = address(assetAddr).call(data);
        require(success, string(resultData));
    }

    /**
     * @notice Approves our Cryptopunk ERC721 tokens to be transferred.
     *
     * @dev This is only required to provide special logic for Cryptopunks.
     *
     * @param assetAddr Address of the asset being transferred
     * @param tokenId The ID of the token being transferred
     * @param to The address the token is being transferred to
     */

    function _approveCryptoPunkERC721(
        address assetAddr,
        uint256 tokenId,
        address to
    ) internal virtual {
        bytes memory data = abi.encodeWithSignature(
            "offerPunkForSaleToAddress(uint256,uint256,address)",
            tokenId,
            0,
            to
        );
        (bool success, bytes memory resultData) = address(assetAddr).call(data);
        require(success, string(resultData));
    }

    receive() external payable {}
}
