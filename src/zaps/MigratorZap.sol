// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {INFTXVaultV2} from "@src/v2/interfaces/INFTXVaultV2.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@src/interfaces/external/IUniswapV2Router02.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
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

    IWETH9 public immutable WETH;
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
        INFTXInventoryStakingV2 v2Inventory_,
        IUniswapV2Router02 sushiRouter_,
        INonfungiblePositionManager positionManager_,
        INFTXVaultFactoryV3 v3NFTXFactory_,
        INFTXInventoryStakingV3 v3Inventory_
    ) {
        v2Inventory = v2Inventory_;
        sushiRouter = sushiRouter_;
        positionManager = positionManager_;
        v3NFTXFactory = v3NFTXFactory_;
        v3Inventory = v3Inventory_;
        WETH = IWETH9(positionManager_.WETH9());

        WETH.approve(address(positionManager_), type(uint256).max);
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
        // get lp tokens from the user
        if (params.permitSig.length > 0) {
            _permit(params.sushiPair, params.lpAmount, params.permitSig);
        }
        IUniswapV2Pair(params.sushiPair).transferFrom(
            msg.sender,
            address(this),
            params.lpAmount
        );

        uint256 wethBalance;
        address vTokenV3;
        uint256 vTokenV3Balance;
        {
            // withdraw liquidity from Sushiswap
            uint256 vTokenV2Balance;
            (vTokenV2Balance, wethBalance) = _withdrawFromSushi(
                params.sushiPair,
                params.vTokenV2
            );

            // convert v2 to v3 vault tokens
            uint256 wethReceived;
            (vTokenV3, vTokenV3Balance, wethReceived) = _v2ToV3Vault(
                params.vTokenV2,
                vTokenV2Balance,
                params.idsToRedeem,
                params.vaultIdV3,
                params.is1155
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
        _maxApproveToken(vTokenV3, address(positionManager), vTokenV3Balance);

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
        address vTokenV2,
        uint256 shares,
        uint256[] calldata idsToRedeem,
        bool is1155,
        uint256 vaultIdV3
    ) external returns (uint256 xNFTId) {
        address xToken = v2Inventory.vaultXToken(vaultIdV2);
        IERC20(xToken).transferFrom(msg.sender, address(this), shares);

        v2Inventory.withdraw(vaultIdV2, shares);
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
                is1155
            );
        if (wethReceived > 0) {
            WETH.transfer(msg.sender, wethReceived);
        }

        _maxApproveToken(vTokenV3, address(v3Inventory), vTokenV3Balance);
        xNFTId = v3Inventory.deposit(vaultIdV3, vTokenV3Balance, msg.sender);
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
        uint256 vaultIdV3
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
                is1155
            );
        if (wethReceived > 0) {
            WETH.transfer(msg.sender, wethReceived);
        }

        _maxApproveToken(vTokenV3, address(v3Inventory), vTokenV3Balance);
        xNFTId = v3Inventory.deposit(vaultIdV3, vTokenV3Balance, msg.sender);
    }

    // =============================================================
    //                        INTERNAL HELPERS
    // =============================================================

    function _maxApproveToken(
        address token,
        address spender,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);

        if (amount > allowance) {
            // SafeERC20 not required here as both vToken and WETH follow the ERC20 standard correctly
            IERC20(token).approve(spender, type(uint256).max);
        }
    }

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
        address vTokenV2
    ) internal returns (uint256 vTokenV2Balance, uint256 wethBalance) {
        // burn sushi liquidity to this contract
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
        bool is1155
    )
        internal
        returns (
            address vTokenV3,
            uint256 vTokenV3Balance,
            uint256 wethReceived
        )
    {
        // redeem v2 vTokens
        uint256[] memory idsRedeemed = INFTXVaultV2(vTokenV2).redeem(
            vTokenV2Balance / 1 ether,
            idsToRedeem
        );
        // fractional portion of vToken would be left
        vTokenV2Balance = vTokenV2Balance % 1 ether;

        if (vTokenV2Balance > 0) {
            // sell for WETH
            address[] memory path = new address[](2);
            path[0] = vTokenV2;
            path[1] = address(WETH);

            wethReceived = sushiRouter.swapExactTokensForTokens(
                vTokenV2Balance,
                1,
                path,
                address(this),
                block.timestamp
            )[path.length - 1];
        }

        vTokenV3 = v3NFTXFactory.vault(vaultIdV3);
        // mint v3 vault tokens with the nfts received
        // approve NFT
        (bool success, ) = INFTXVaultV2(vTokenV2).assetAddress().call(
            // same function sig for both ERC721 and ERC1155 NFTs
            abi.encodeWithSignature(
                "setApprovalForAll(address,bool)",
                vTokenV3,
                true
            )
        );
        require(success);

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

        // mint
        vTokenV3Balance = INFTXVaultV3(vTokenV3).mint(idsRedeemed, amounts);
    }
}
