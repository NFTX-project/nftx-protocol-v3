// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TransferLib} from "@src/lib/TransferLib.sol";

import {IUniswapV3Factory} from "@uni-core/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uni-periphery/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter, SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {IQuoterV2} from "@uni-periphery/interfaces/IQuoterV2.sol";
import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {PoolAddress} from "@uni-periphery/libraries/PoolAddress.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";

import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";
import {INFTXVault} from "@src/v2/interface/INFTXVault.sol";
import {INFTXFeeDistributorV3} from "@src/interfaces/INFTXFeeDistributorV3.sol";

import {INFTXRouter} from "../interfaces/INFTXRouter.sol";

/**
 * @title NFTX Router
 * @author @apoorvlathey
 *
 * @notice Router to facilitate vault tokens minting/burning + addition/removal of concentrated liquidity
 * @dev This router must be excluded from the vault fees, as vault fees handled via custom logic here.
 */
contract NFTXRouter is INFTXRouter, Ownable, ERC721Holder {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    address public immutable override WETH;
    IPermitAllowanceTransfer public immutable override PERMIT2;

    INonfungiblePositionManager public immutable override positionManager;
    SwapRouter public immutable override router;
    IQuoterV2 public immutable override quoter;
    INFTXVaultFactory public immutable override nftxVaultFactory;

    constructor(
        INonfungiblePositionManager positionManager_,
        SwapRouter router_,
        IQuoterV2 quoter_,
        INFTXVaultFactory nftxVaultFactory_,
        IPermitAllowanceTransfer PERMIT2_
    ) {
        positionManager = positionManager_;
        router = router_;
        quoter = quoter_;
        nftxVaultFactory = nftxVaultFactory_;
        PERMIT2 = PERMIT2_;

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
        INFTXVault vToken = INFTXVault(nftxVaultFactory.vault(params.vaultId));

        if (params.vTokensAmount > 0) {
            vToken.transferFrom(
                msg.sender,
                address(this),
                params.vTokensAmount
            );
        }

        return _addLiquidity(params, vToken);
    }

    function addLiquidityWithPermit2(
        AddLiquidityParams calldata params,
        bytes calldata encodedPermit2
    ) external payable override returns (uint256 positionId) {
        INFTXVault vToken = INFTXVault(nftxVaultFactory.vault(params.vaultId));

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

    function removeLiquidity(
        RemoveLiquidityParams calldata params
    ) external payable override {
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

        INFTXVault vToken = INFTXVault(nftxVaultFactory.vault(params.vaultId));

        bool _isVToken0 = isVToken0(address(vToken));
        (uint256 vTokenAmt, uint256 wethAmt) = _isVToken0
            ? (amount0, amount1)
            : (amount1, amount0);

        // No NFTs to redeem, directly withdraw vTokens
        if (params.nftIds.length == 0) {
            vToken.transfer(msg.sender, vTokenAmt);
        } else {
            // distributing vault fees

            // if withdrawn WETH is insufficient to pay for vault fees, user sends ETH (can be excess, as refunded back) along with the transaction
            if (msg.value > 0) {
                IWETH9(WETH).deposit{value: msg.value}();
                wethAmt += msg.value;
            }
            uint256 wethFees = _ethRedeemFees(vToken, params.nftIds);
            _distributeVaultFees(params.vaultId, wethFees, true);
            wethAmt -= wethFees; // if underflow, then revert desired

            // burn vTokens to provided tokenIds array
            vToken.redeemTo(params.nftIds, msg.sender);
            uint256 vTokenBurned = params.nftIds.length * 1 ether;

            // if more vTokens collected than burned
            uint256 vTokenResidue = vTokenAmt - vTokenBurned;

            if (vTokenResidue > 0) {
                vToken.transfer(msg.sender, vTokenResidue);
            }
        }
        // convert remaining WETH to ETH & send to user
        IWETH9(WETH).withdraw(wethAmt);
        (bool success, ) = msg.sender.call{value: wethAmt}("");
        if (!success) revert UnableToSendETH();

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
        INFTXVault vToken = INFTXVault(nftxVaultFactory.vault(params.vaultId));
        address assetAddress = INFTXVault(address(vToken)).assetAddress();

        // tranfer NFTs from user to the vault
        TransferLib.transferFromERC721(
            assetAddress,
            address(vToken),
            params.nftIds
        );

        // mint vToken
        uint256[] memory emptyIds;
        uint256 vTokensAmount = vToken.mint(params.nftIds, emptyIds) * 1 ether;

        TransferLib.maxApprove(address(vToken), address(router), vTokensAmount);

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
        (bool success, ) = msg.sender.call{value: wethRemaining}("");
        if (!success) revert UnableToSendETH();

        emit SellNFTs(params.nftIds.length, wethRemaining);
    }

    function buyNFTs(BuyNFTsParams calldata params) external payable override {
        INFTXVault vToken = INFTXVault(nftxVaultFactory.vault(params.vaultId));
        uint256 vTokenAmt = params.nftIds.length * 1 ether;

        // distributing vault fees
        uint256 ethFees = _ethRedeemFees(vToken, params.nftIds);
        _distributeVaultFees(params.vaultId, ethFees, false);

        // swap remaining ETH to required vTokens amount
        uint256 ethRemaining = msg.value - ethFees; // if underflow, then revert desired
        uint256 ethSpent = router.exactOutputSingle{value: ethRemaining}(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: WETH,
                tokenOut: address(vToken),
                fee: params.fee,
                recipient: address(this),
                deadline: params.deadline,
                amountOut: vTokenAmt,
                amountInMaximum: ethRemaining,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // unwrap vTokens to tokenIds specified, and send to sender
        vToken.redeemTo(params.nftIds, msg.sender);

        // refund ETH
        router.refundETH(msg.sender);

        emit BuyNFTs(params.nftIds.length, ethSpent);
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

    // to avoid stack too deep
    struct TempAdd {
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    function _addLiquidity(
        AddLiquidityParams calldata params,
        INFTXVault vToken
    ) internal returns (uint256 positionId) {
        uint256 vTokensAmount = params.vTokensAmount;

        uint256 ethForLiquidity = msg.value;
        if (params.nftIds.length > 0) {
            address assetAddress = vToken.assetAddress();

            // tranfer NFTs from user to the vault
            TransferLib.transferFromERC721(
                assetAddress,
                address(vToken),
                params.nftIds
            );

            uint256[] memory emptyIds;
            // vault won't charge mintFees here as this contract is on exclude list
            vTokensAmount += vToken.mint(params.nftIds, emptyIds) * 1 ether;

            // distributing vault fees
            uint256 ethFees = _ethMintFees(vToken, params.nftIds.length);
            _distributeVaultFees(params.vaultId, ethFees, false);

            // use remaining ETH for providing liquidity into the pool
            ethForLiquidity -= ethFees; // if underflow, then revert desired
        }

        TransferLib.maxApprove(
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
        TempAdd memory ta;
        if (_isVToken0) {
            ta.amount0Desired = vTokensAmount;
            // have a 5000 wei buffer to account for any dust amounts
            ta.amount0Min = vTokensAmount > 5000 ? vTokensAmount - 5000 : 0;
            ta.amount1Desired = ethForLiquidity;
        } else {
            ta.amount0Desired = ethForLiquidity;
            ta.amount1Desired = vTokensAmount;
            // have a 5000 wei buffer to account for any dust amounts
            ta.amount1Min = vTokensAmount > 5000 ? vTokensAmount - 5000 : 0;
        }

        (positionId, , , ) = positionManager.mint{value: ethForLiquidity}(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: params.fee,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: ta.amount0Desired,
                amount1Desired: ta.amount1Desired,
                amount0Min: ta.amount0Min,
                amount1Min: ta.amount1Min,
                recipient: msg.sender,
                deadline: params.deadline
            })
        );

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

    // TODO: premium for 1155
    // TODO: distribute premium share with the original depositor
    function _getVTokenPremium(
        INFTXVault vToken,
        uint256[] memory nftIds
    ) internal view returns (uint256 vTokenPremium) {
        for (uint256 i; i < nftIds.length; ) {
            uint256 _vTokenPremium;
            (_vTokenPremium, ) = vToken.getVTokenPremium721(nftIds[i]);
            vTokenPremium += _vTokenPremium;

            unchecked {
                ++i;
            }
        }
    }

    function _ethMintFees(
        INFTXVault vToken,
        uint256 nftCount
    ) internal view returns (uint256) {
        return vToken.vTokenToETH(vToken.mintFee() * nftCount);
    }

    function _ethRedeemFees(
        INFTXVault vToken,
        uint256[] memory nftIds
    ) internal view returns (uint256) {
        return
            vToken.vTokenToETH(
                (vToken.targetRedeemFee() * nftIds.length) +
                    _getVTokenPremium(vToken, nftIds)
            );
    }

    receive() external payable {}
}
