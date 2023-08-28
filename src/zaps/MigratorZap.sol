// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {TransferLib} from "@src/lib/TransferLib.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {INFTXVaultV2} from "@src/v2/interfaces/INFTXVaultV2.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@src/interfaces/external/IUniswapV2Router02.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {INFTXVaultFactoryV2} from "@src/v2/interfaces/INFTXVaultFactoryV2.sol";
import {INFTXInventoryStakingV2} from "@src/v2/interfaces/INFTXInventoryStakingV2.sol";
import {INFTXInventoryStakingV3} from "@src/interfaces/INFTXInventoryStakingV3.sol";
import {INonfungiblePositionManager} from "@uni-periphery/interfaces/INonfungiblePositionManager.sol";

/**
 * @title NFTX Migrator Zap
 * @author @apoorvlathey
 * @notice Migrates positions from NFTX v2 to v3
 * @dev This Zap must be excluded from vault fees in both NFTX v2 & v3.
 */
contract MigratorZap {
    struct SushiToNFTXAMMParams {
        // Sushiswap pool address for vTokenV2 <> WETH pair
        address sushiPair;
        // LP balance to withdraw from sushiswap
        uint256 lpAmount;
        // Vault address in NFTX v2
        address vTokenV2;
        // NFT tokenIds to redeem from v2 vault
        uint256[] idsToRedeem;
        // If underlying vault NFT is ERC1155
        bool is1155;
        // Encoded permit signature for sushiPair
        bytes permitSig;
        // Vault id in NFTX v3
        uint256 vaultIdV3;
        // Add liquidity params for NFTX AMM:
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
        // this price is used if new pool needs to be initialized
        uint160 sqrtPriceX96;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    uint256 private constant DEADLINE =
        0xf000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant DUST_THRESHOLD = 0.005 ether;

    IWETH9 public immutable WETH;
    INFTXVaultFactoryV2 public immutable v2NFTXFactory;
    INFTXInventoryStakingV2 public immutable v2Inventory;
    IUniswapV2Router02 public immutable sushiRouter;
    INonfungiblePositionManager public immutable positionManager;
    INFTXVaultFactoryV3 public immutable v3NFTXFactory;
    INFTXInventoryStakingV3 public immutable v3Inventory;

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidSignatureLength();

    // =============================================================
    //                           INIT
    // =============================================================

    constructor(
        IWETH9 WETH_,
        INFTXVaultFactoryV2 v2NFTXFactory_,
        INFTXInventoryStakingV2 v2Inventory_,
        IUniswapV2Router02 sushiRouter_,
        INonfungiblePositionManager positionManager_,
        INFTXVaultFactoryV3 v3NFTXFactory_,
        INFTXInventoryStakingV3 v3Inventory_
    ) {
        WETH = WETH_;
        v2NFTXFactory = v2NFTXFactory_;
        v2Inventory = v2Inventory_;
        sushiRouter = sushiRouter_;
        positionManager = positionManager_;
        v3NFTXFactory = v3NFTXFactory_;
        v3Inventory = v3Inventory_;

        WETH_.approve(address(positionManager_), type(uint256).max);
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    /**
     * @notice Migrates liquidity from Sushiswap to NFTX AMM
     */
    function sushiToNFTXAMM(
        SushiToNFTXAMMParams calldata params
    ) external returns (uint256 positionId) {
        if (params.permitSig.length > 0) {
            _permit(params.sushiPair, params.lpAmount, params.permitSig);
        }

        uint256 wethBalance;
        address vTokenV3;
        uint256 vTokenV3Balance;
        {
            // withdraw liquidity from Sushiswap
            uint256 vTokenV2Balance;
            (vTokenV2Balance, wethBalance) = _withdrawFromSushi(
                params.sushiPair,
                params.lpAmount,
                params.vTokenV2
            );

            // convert v2 to v3 vault tokens
            uint256 wethReceived;
            (vTokenV3, vTokenV3Balance, wethReceived) = _v2ToV3Vault(
                params.vTokenV2,
                vTokenV2Balance,
                params.idsToRedeem,
                params.vaultIdV3,
                params.is1155,
                0 // passing zero here as `positionManager.mint` takes this into account via `amount0Min` or `amount1Min`
            );
            wethBalance += wethReceived;
        }

        bool isVTokenV30 = vTokenV3 < address(WETH);
        (
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1
        ) = isVTokenV30
                ? (vTokenV3, address(WETH), vTokenV3Balance, wethBalance)
                : (address(WETH), vTokenV3, wethBalance, vTokenV3Balance);

        // deploy new pool if it doesn't yet exist
        positionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            params.fee,
            params.sqrtPriceX96
        );

        // give vToken approval to positionManager
        TransferLib.unSafeMaxApprove(
            vTokenV3,
            address(positionManager),
            vTokenV3Balance
        );

        // provide liquidity to NFTX AMM
        uint256 newAmount0;
        uint256 newAmount1;
        (positionId, , newAmount0, newAmount1) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: params.fee,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: msg.sender,
                deadline: params.deadline
            })
        );

        // refund any dust left
        if (newAmount0 < amount0) {
            IERC20(token0).transfer(msg.sender, amount0 - newAmount0);
        }
        if (newAmount1 < amount1) {
            IERC20(token1).transfer(msg.sender, amount1 - newAmount1);
        }
    }

    /**
     * @notice Move vTokens from v2 Inventory to v3 Inventory (minting xNFT)
     * @dev Must give xToken approval before calling this function
     */
    function v2InventoryToXNFT(
        uint256 vaultIdV2,
        uint256 shares,
        uint256[] calldata idsToRedeem,
        bool is1155,
        uint256 vaultIdV3,
        uint256 minWethToReceive
    ) external returns (uint256 xNFTId) {
        address xToken = v2Inventory.vaultXToken(vaultIdV2);
        IERC20(xToken).transferFrom(msg.sender, address(this), shares);

        v2Inventory.withdraw(vaultIdV2, shares);
        address vTokenV2 = v2NFTXFactory.vault(vaultIdV2);
        uint256 vTokenV2Balance = IERC20(vTokenV2).balanceOf(address(this));

        (
            address vTokenV3,
            uint256 vTokenV3Balance,
            uint256 wethReceived
        ) = _v2ToV3Vault(
                vTokenV2,
                vTokenV2Balance,
                idsToRedeem,
                vaultIdV3,
                is1155,
                minWethToReceive
            );
        if (wethReceived > 0) {
            WETH.transfer(msg.sender, wethReceived);
        }

        TransferLib.unSafeMaxApprove(
            vTokenV3,
            address(v3Inventory),
            vTokenV3Balance
        );
        xNFTId = v3Inventory.deposit(
            vaultIdV3,
            vTokenV3Balance,
            msg.sender,
            "",
            false,
            false
        );
    }

    /**
     * @notice Move v2 vTokens to v3 Inventory (minting xNFT)
     * @dev Must give v2 VToken approval before calling this function
     */
    function v2VaultToXNFT(
        address vTokenV2,
        uint256 vTokenV2Balance,
        uint256[] calldata idsToRedeem,
        bool is1155,
        uint256 vaultIdV3,
        uint256 minWethToReceive
    ) external returns (uint256 xNFTId) {
        IERC20(vTokenV2).transferFrom(
            msg.sender,
            address(this),
            vTokenV2Balance
        );

        (
            address vTokenV3,
            uint256 vTokenV3Balance,
            uint256 wethReceived
        ) = _v2ToV3Vault(
                vTokenV2,
                vTokenV2Balance,
                idsToRedeem,
                vaultIdV3,
                is1155,
                minWethToReceive
            );
        if (wethReceived > 0) {
            WETH.transfer(msg.sender, wethReceived);
        }

        TransferLib.unSafeMaxApprove(
            vTokenV3,
            address(v3Inventory),
            vTokenV3Balance
        );
        xNFTId = v3Inventory.deposit(
            vaultIdV3,
            vTokenV3Balance,
            msg.sender,
            "",
            false,
            false
        );
    }

    // =============================================================
    //                        INTERNAL HELPERS
    // =============================================================

    function _permit(
        address sushiPair,
        uint256 lpAmount,
        bytes memory permitSig
    ) internal {
        if (permitSig.length != 65) revert InvalidSignatureLength();

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(permitSig, 32))
            s := mload(add(permitSig, 64))
            v := byte(0, mload(add(permitSig, 96)))
        }
        IUniswapV2Pair(sushiPair).permit(
            msg.sender,
            address(this),
            lpAmount,
            DEADLINE,
            v,
            r,
            s
        );
    }

    function _withdrawFromSushi(
        address sushiPair,
        uint256 lpAmount,
        address vTokenV2
    ) internal returns (uint256 vTokenV2Balance, uint256 wethBalance) {
        // burn sushi liquidity to this contract
        IUniswapV2Pair(sushiPair).transferFrom(msg.sender, sushiPair, lpAmount);
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(sushiPair).burn(
            address(this)
        );

        bool isVTokenV20 = vTokenV2 < address(WETH);

        (vTokenV2Balance, wethBalance) = isVTokenV20
            ? (amount0, amount1)
            : (amount1, amount0);
    }

    function _v2ToV3Vault(
        address vTokenV2,
        uint256 vTokenV2Balance,
        uint256[] calldata idsToRedeem,
        uint256 vaultIdV3,
        bool is1155,
        uint256 minWethToReceive
    )
        internal
        returns (
            address vTokenV3,
            uint256 vTokenV3Balance,
            uint256 wethReceived
        )
    {
        vTokenV3 = v3NFTXFactory.vault(vaultIdV3);

        // redeem v2 vTokens. Directly transferring to the v3 vault
        uint256[] memory idsRedeemed = INFTXVaultV2(vTokenV2).redeemTo(
            vTokenV2Balance / 1 ether,
            idsToRedeem,
            is1155 ? address(this) : vTokenV3
        );
        if (is1155) {
            IERC1155(INFTXVaultV3(vTokenV3).assetAddress()).setApprovalForAll(
                vTokenV3,
                true
            );
        }

        // fractional portion of vToken would be left
        vTokenV2Balance = vTokenV2Balance % 1 ether;

        // sell fractional portion for WETH
        if (vTokenV2Balance > DUST_THRESHOLD) {
            address[] memory path = new address[](2);
            path[0] = vTokenV2;
            path[1] = address(WETH);

            TransferLib.unSafeMaxApprove(
                vTokenV2,
                address(sushiRouter),
                vTokenV2Balance
            );
            wethReceived = sushiRouter.swapExactTokensForTokens(
                vTokenV2Balance,
                minWethToReceive,
                path,
                address(this),
                block.timestamp
            )[path.length - 1];
        } else if (vTokenV2Balance > 0) {
            // send back the vTokens as not worth the swap gas fees
            IERC20(vTokenV2).transfer(msg.sender, vTokenV2Balance);
        }

        // mint v3 vault tokens with the nfts received
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
        vTokenV3Balance = INFTXVaultV3(vTokenV3).mint(
            idsRedeemed,
            amounts,
            msg.sender,
            address(this)
        );
    }
}
