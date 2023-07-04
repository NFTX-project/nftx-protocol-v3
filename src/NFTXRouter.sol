// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {TransferLib} from "@src/lib/TransferLib.sol";
import {PoolAddress} from "@uni-periphery/libraries/PoolAddress.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IQuoterV2} from "@uni-periphery/interfaces/IQuoterV2.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {IUniswapV3Factory} from "@uni-core/interfaces/IUniswapV3Factory.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {INFTXFeeDistributorV3} from "@src/interfaces/INFTXFeeDistributorV3.sol";
import {ISwapRouter, SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";
import {INonfungiblePositionManager} from "@uni-periphery/interfaces/INonfungiblePositionManager.sol";

import {INFTXRouter} from "@src/interfaces/INFTXRouter.sol";

/**
 * @title NFTX Router
 * @author @apoorvlathey
 *
 * @notice Router to facilitate vault tokens minting/burning + addition/removal of concentrated liquidity
 * @dev This router must be excluded from the vault fees, as vault fees handled via custom logic here.
 */
contract NFTXRouter is INFTXRouter, Ownable, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    address public immutable override WETH;
    IPermitAllowanceTransfer public immutable override PERMIT2;

    INonfungiblePositionManager public immutable override positionManager;
    SwapRouter public immutable override router;
    IQuoterV2 public immutable override quoter;
    INFTXVaultFactoryV3 public immutable override nftxVaultFactory;

    // =============================================================
    //                           STORAGE
    // =============================================================

    uint256 public override lpTimelock;

    constructor(
        INonfungiblePositionManager positionManager_,
        SwapRouter router_,
        IQuoterV2 quoter_,
        INFTXVaultFactoryV3 nftxVaultFactory_,
        IPermitAllowanceTransfer PERMIT2_,
        uint256 lpTimelock_
    ) {
        positionManager = positionManager_;
        router = router_;
        quoter = quoter_;
        nftxVaultFactory = nftxVaultFactory_;
        PERMIT2 = PERMIT2_;
        lpTimelock = lpTimelock_;

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
        INFTXVaultV3 vToken = INFTXVaultV3(
            nftxVaultFactory.vault(params.vaultId)
        );

        if (params.vTokensAmount > 0) {
            vToken.transferFrom(
                msg.sender,
                address(this),
                params.vTokensAmount
            );
        }

        return _addLiquidity(params, vToken);
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function addLiquidityWithPermit2(
        AddLiquidityParams calldata params,
        bytes calldata encodedPermit2
    ) external payable override returns (uint256 positionId) {
        INFTXVaultV3 vToken = INFTXVaultV3(
            nftxVaultFactory.vault(params.vaultId)
        );

        if (encodedPermit2.length > 0) {
            (
                address owner,
                IPermitAllowanceTransfer.PermitSingle memory permitSingle,
                bytes memory signature
            ) = abi.decode(
                    encodedPermit2,
                    (address, IPermitAllowanceTransfer.PermitSingle, bytes)
                );

            PERMIT2.permit(owner, permitSingle, signature);
        }

        if (params.vTokensAmount > 0) {
            PERMIT2.transferFrom(
                msg.sender,
                address(this),
                uint160(params.vTokensAmount),
                address(vToken)
            );
        }

        return _addLiquidity(params, vToken);
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    ) external payable override {
        INFTXVaultV3 vToken = INFTXVaultV3(
            nftxVaultFactory.vault(params.vaultId)
        );

        if (params.vTokensAmount > 0) {
            vToken.transferFrom(
                msg.sender,
                address(this),
                params.vTokensAmount
            );
        }

        return _increaseLiquidity(params, vToken);
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function increaseLiquidityWithPermit2(
        IncreaseLiquidityParams calldata params,
        bytes calldata encodedPermit2
    ) external payable override {
        INFTXVaultV3 vToken = INFTXVaultV3(
            nftxVaultFactory.vault(params.vaultId)
        );

        if (encodedPermit2.length > 0) {
            (
                address owner,
                IPermitAllowanceTransfer.PermitSingle memory permitSingle,
                bytes memory signature
            ) = abi.decode(
                    encodedPermit2,
                    (address, IPermitAllowanceTransfer.PermitSingle, bytes)
                );

            PERMIT2.permit(owner, permitSingle, signature);
        }

        if (params.vTokensAmount > 0) {
            PERMIT2.transferFrom(
                msg.sender,
                address(this),
                uint160(params.vTokensAmount),
                address(vToken)
            );
        }

        return _increaseLiquidity(params, vToken);
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function removeLiquidity(
        RemoveLiquidityParams calldata params
    ) external payable override {
        // remove liquidity to get vTokens and WETH
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

        INFTXVaultV3 vToken = INFTXVaultV3(
            nftxVaultFactory.vault(params.vaultId)
        );

        bool _isVToken0 = isVToken0(address(vToken));
        (uint256 vTokenAmt, uint256 wethAmt) = _isVToken0
            ? (amount0, amount1)
            : (amount1, amount0);

        // No NFTs to redeem, directly withdraw vTokens
        if (params.nftIds.length == 0) {
            vToken.transfer(msg.sender, vTokenAmt);
        } else {
            // if withdrawn WETH is insufficient to pay for vault fees, user sends ETH (can be excess, as refunded back) along with the transaction
            if (msg.value > 0) {
                IWETH9(WETH).deposit{value: msg.value}();
                wethAmt += msg.value;
            }

            // if the position has completed its timelock, then we shouldn't charge redeem fees.
            bool chargeFees = positionManager.lockedUntil(params.positionId) ==
                0;

            // burn vTokens to provided tokenIds array. Forcing to deduct vault fees
            if (chargeFees) {
                TransferLib.unSafeMaxApprove(WETH, address(vToken), wethAmt);
            }
            uint256 wethFees = vToken.redeem(
                params.nftIds,
                msg.sender,
                wethAmt,
                chargeFees
            );
            wethAmt -= wethFees;

            uint256 vTokenBurned = params.nftIds.length * 1 ether;

            // if more vTokens collected than burned
            uint256 vTokenResidue = vTokenAmt - vTokenBurned;

            if (vTokenResidue > 0) {
                vToken.transfer(msg.sender, vTokenResidue);
            }
        }
        // convert remaining WETH to ETH & send to user
        IWETH9(WETH).withdraw(wethAmt);
        TransferLib.transferETH(msg.sender, wethAmt);

        emit RemoveLiquidity(
            params.positionId,
            params.vaultId,
            vTokenAmt,
            wethAmt
        );
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function sellNFTs(
        SellNFTsParams calldata params
    ) external payable override returns (uint256 wethReceived) {
        INFTXVaultV3 vToken = INFTXVaultV3(
            nftxVaultFactory.vault(params.vaultId)
        );
        address assetAddress = INFTXVaultV3(address(vToken)).assetAddress();

        if (params.nftAmounts.length == 0) {
            // tranfer NFTs from user to the vault
            TransferLib.transferFromERC721(
                assetAddress,
                address(vToken),
                params.nftIds
            );
        } else {
            IERC1155(assetAddress).safeBatchTransferFrom(
                msg.sender,
                address(this),
                params.nftIds,
                params.nftAmounts,
                ""
            );

            IERC1155(assetAddress).setApprovalForAll(address(vToken), true);
        }

        // mint vToken
        uint256 vTokensAmount = vToken.mint(
            params.nftIds,
            params.nftAmounts,
            msg.sender,
            address(this)
        );

        TransferLib.unSafeMaxApprove(
            address(vToken),
            address(router),
            vTokensAmount
        );

        wethReceived = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(vToken),
                tokenOut: WETH,
                fee: params.fee,
                recipient: address(this),
                deadline: params.deadline,
                amountIn: vTokensAmount,
                amountOutMinimum: params.amountOutMinimum,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // if received WETH is insufficient to pay for vault fees, user sends ETH (can be excess, as refunded back) along with the transaction
        if (msg.value > 0) {
            IWETH9(WETH).deposit{value: msg.value}();
            wethReceived += msg.value;
        }
        // distributing vault fees with the wethReceived
        uint256 wethFees = _ethMintFees(vToken, params.nftIds.length);
        _distributeVaultFees(params.vaultId, wethFees, true);
        uint256 wethRemaining = wethReceived - wethFees; // if underflow, then revert desired

        // convert remaining WETH to ETH & send to user
        IWETH9(WETH).withdraw(wethRemaining);
        TransferLib.transferETH(msg.sender, wethRemaining);

        emit SellNFTs(params.nftIds.length, wethRemaining);
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function buyNFTs(BuyNFTsParams calldata params) external payable override {
        INFTXVaultV3 vToken = INFTXVaultV3(
            nftxVaultFactory.vault(params.vaultId)
        );
        uint256 vTokenAmt = params.nftIds.length * 1 ether;

        IWETH9(WETH).deposit{value: msg.value}();
        TransferLib.unSafeMaxApprove(WETH, address(router), msg.value);
        uint256 wethSpent = router.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: WETH,
                tokenOut: address(vToken),
                fee: params.fee,
                recipient: address(this),
                deadline: params.deadline,
                amountOut: vTokenAmt,
                amountInMaximum: msg.value,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // unwrap vTokens to tokenIds specified, and send to sender. Forcing to deduct vault fees
        uint256 wethLeft = msg.value - wethSpent;
        TransferLib.unSafeMaxApprove(WETH, address(vToken), wethLeft);
        uint256 wethFees = vToken.redeem(
            params.nftIds,
            msg.sender,
            wethLeft,
            true
        );

        wethLeft -= wethFees;
        // refund extra ETH
        if (wethLeft > 0) {
            IWETH9(WETH).withdraw(wethLeft);

            TransferLib.transferETH(msg.sender, wethLeft);
        }

        emit BuyNFTs(params.nftIds.length, wethSpent + wethFees);
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
            TransferLib.transferETH(msg.sender, balance);
        }
    }

    /**
     * @inheritdoc INFTXRouter
     */
    function setLpTimelock(uint256 lpTimelock_) external override onlyOwner {
        lpTimelock = lpTimelock_;
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    /**
     * @inheritdoc INFTXRouter
     */
    function quoteBuyNFTs(
        address vtoken,
        uint256 nftsCount,
        uint24 fee,
        uint160 sqrtPriceLimitX96
    ) external override returns (uint256 ethRequired) {
        uint256 vTokenAmt = nftsCount * 1 ether;

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

    function _addLiquidity(
        AddLiquidityParams calldata params,
        INFTXVaultV3 vToken
    ) internal returns (uint256 positionId) {
        uint256 vTokensAmount = params.vTokensAmount;

        if (params.nftIds.length > 0) {
            address assetAddress = vToken.assetAddress();

            if (params.nftAmounts.length == 0) {
                // tranfer NFTs from user to the vault
                TransferLib.transferFromERC721(
                    assetAddress,
                    address(vToken),
                    params.nftIds
                );
            } else {
                IERC1155(assetAddress).safeBatchTransferFrom(
                    msg.sender,
                    address(this),
                    params.nftIds,
                    params.nftAmounts,
                    ""
                );

                IERC1155(assetAddress).setApprovalForAll(address(vToken), true);
            }

            // vault won't charge mintFees here as this contract is on exclude list
            vTokensAmount += vToken.mint(
                params.nftIds,
                params.nftAmounts,
                msg.sender,
                address(this)
            );
        }

        TransferLib.unSafeMaxApprove(
            address(vToken),
            address(positionManager),
            vTokensAmount
        );

        bool _isVToken0 = isVToken0(address(vToken));
        (address token0, address token1) = _isVToken0
            ? (address(vToken), WETH)
            : (WETH, address(vToken));

        positionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            params.fee,
            params.sqrtPriceX96
        );

        // mint position with vtoken and ETH
        (
            uint256 amount0Desired,
            uint256 amount1Desired,
            uint256 amount0Min,
            uint256 amount1Min
        ) = _isVToken0
                ? (vTokensAmount, msg.value, params.vTokenMin, params.wethMin)
                : (msg.value, vTokensAmount, params.wethMin, params.vTokenMin);

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
        if (params.nftIds.length > 0) {
            // vault fees not charged, so instead add timelock to the minted LP NFT
            positionManager.setLockedUntil(
                positionId,
                block.timestamp + lpTimelock
            );
        }

        // refund extra ETH
        positionManager.refundETH(msg.sender);

        // refund vTokens dust (if any left)
        uint256 vTokenBalance = vToken.balanceOf(address(this));
        if (vTokenBalance > 0) {
            vToken.transfer(msg.sender, vTokenBalance);
        }

        emit AddLiquidity(
            params.vaultId,
            params.vTokensAmount,
            params.nftIds.length,
            positionId
        );
    }

    function _increaseLiquidity(
        IncreaseLiquidityParams calldata params,
        INFTXVaultV3 vToken
    ) internal {
        uint256 vTokensAmount = params.vTokensAmount;

        if (params.nftIds.length > 0) {
            address assetAddress = vToken.assetAddress();

            if (params.nftAmounts.length == 0) {
                // tranfer NFTs from user to the vault
                TransferLib.transferFromERC721(
                    assetAddress,
                    address(vToken),
                    params.nftIds
                );
            } else {
                IERC1155(assetAddress).safeBatchTransferFrom(
                    msg.sender,
                    address(this),
                    params.nftIds,
                    params.nftAmounts,
                    ""
                );

                IERC1155(assetAddress).setApprovalForAll(address(vToken), true);
            }

            // vault won't charge mintFees here as this contract is on exclude list
            vTokensAmount += vToken.mint(
                params.nftIds,
                params.nftAmounts,
                msg.sender,
                address(this)
            );
        }

        TransferLib.unSafeMaxApprove(
            address(vToken),
            address(positionManager),
            vTokensAmount
        );

        bool _isVToken0 = isVToken0(address(vToken));
        (
            uint256 amount0Desired,
            uint256 amount1Desired,
            uint256 amount0Min,
            uint256 amount1Min
        ) = _isVToken0
                ? (vTokensAmount, msg.value, params.vTokenMin, params.wethMin)
                : (msg.value, vTokensAmount, params.wethMin, params.vTokenMin);

        positionManager.increaseLiquidity{value: msg.value}(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: params.positionId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: params.deadline
            })
        );
        if (params.nftIds.length > 0) {
            // vault fees not charged, so instead update timelock of the position NFT
            positionManager.setLockedUntil(
                params.positionId,
                block.timestamp + lpTimelock
            );
        }
        // refund extra ETH
        positionManager.refundETH(msg.sender);

        // refund vTokens dust (if any left)
        uint256 vTokenBalance = vToken.balanceOf(address(this));
        if (vTokenBalance > 0) {
            vToken.transfer(msg.sender, vTokenBalance);
        }
    }

    function _distributeVaultFees(
        uint256 vaultId,
        uint256 ethAmount,
        bool isWeth
    ) internal {
        if (ethAmount > 0) {
            INFTXFeeDistributorV3 feeDistributor = INFTXFeeDistributorV3(
                nftxVaultFactory.feeDistributor()
            );
            if (!isWeth) {
                IWETH9(WETH).deposit{value: ethAmount}();
            }
            IWETH9(WETH).transfer(address(feeDistributor), ethAmount);
            feeDistributor.distribute(vaultId);
        }
    }

    function _ethMintFees(
        INFTXVaultV3 vToken,
        uint256 nftCount
    ) internal view returns (uint256) {
        (uint256 mintFee, , ) = vToken.vaultFees();

        return vToken.vTokenToETH(mintFee * nftCount);
    }

    receive() external payable {}
}
