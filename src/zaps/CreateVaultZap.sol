// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {TransferLib} from "@src/lib/TransferLib.sol";
import {TickHelpers} from "@src/lib/TickHelpers.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {INFTXRouter} from "@src/interfaces/INFTXRouter.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {IUniswapV3Factory} from "@uni-core/interfaces/IUniswapV3Factory.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {INFTXInventoryStakingV3} from "@src/interfaces/INFTXInventoryStakingV3.sol";
import {INonfungiblePositionManager} from "@uni-periphery/interfaces/INonfungiblePositionManager.sol";

/**
 * @title Create Vault Zap
 * @author @apoorvlathey, Twade
 * @notice  An amalgomation of vault creation steps, merged and optimised in
 * a single contract call in an attempt reduce gas costs to the end-user.
 * @dev This Zap must be excluded from vault fees.
 */
contract CreateVaultZap is ERC1155Holder {
    struct VaultInfo {
        address assetAddress;
        bool is1155;
        bool allowAllItems;
        string name;
        string symbol;
    }

    struct VaultEligibilityStorage {
        uint256 moduleIndex;
        bytes initData;
    }

    struct VaultFees {
        uint256 mintFee;
        uint256 redeemFee;
        uint256 swapFee;
    }

    struct LiquidityParams {
        uint256 lowerNFTPriceInETH;
        uint256 upperNFTPriceInETH;
        uint24 fee;
        // this price is used if new pool needs to be initialized
        uint256 currentNFTPriceInETH;
        uint256 vTokenMin;
        uint256 wethMin;
        uint256 deadline;
    }

    struct CreateVaultParams {
        VaultInfo vaultInfo;
        VaultEligibilityStorage eligibilityStorage;
        uint256[] nftIds;
        uint256[] nftAmounts; // ignored for ERC721
        uint256 vaultFeaturesFlag; // packedBools in the order: `enableMint`, `enableRedeem`, `enableSwap`
        VaultFees vaultFees;
        LiquidityParams liquidityParams;
    }

    // =============================================================
    //                           CONSTANTS
    // =============================================================
    uint256 internal immutable MINIMUM_INVENTORY_LIQUIDITY;

    IWETH9 public immutable WETH;
    INFTXVaultFactoryV3 public immutable vaultFactory;
    INFTXRouter public immutable nftxRouter;
    IUniswapV3Factory public immutable ammFactory;
    INFTXInventoryStakingV3 public immutable inventoryStaking;
    INonfungiblePositionManager internal immutable positionManager;

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InsufficientETHSent();
    error InsufficientVTokensMinted();

    // =============================================================
    //                           INIT
    // =============================================================

    constructor(
        INFTXRouter nftxRouter_,
        IUniswapV3Factory ammFactory_,
        INFTXInventoryStakingV3 inventoryStaking_
    ) {
        nftxRouter = nftxRouter_;
        ammFactory = ammFactory_;
        inventoryStaking = inventoryStaking_;

        WETH = inventoryStaking_.WETH();
        MINIMUM_INVENTORY_LIQUIDITY = inventoryStaking_.MINIMUM_LIQUIDITY();
        vaultFactory = inventoryStaking_.nftxVaultFactory();
        positionManager = nftxRouter_.positionManager();
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    function createVault(
        CreateVaultParams calldata params
    ) external payable returns (uint256 vaultId) {
        // deploy new vault
        vaultId = vaultFactory.createVault(
            params.vaultInfo.name,
            params.vaultInfo.symbol,
            params.vaultInfo.assetAddress,
            params.vaultInfo.is1155,
            params.vaultInfo.allowAllItems
        );
        INFTXVaultV3 vault = INFTXVaultV3(vaultFactory.vault(vaultId));

        // add eligibility storage, if specified
        if (params.vaultInfo.allowAllItems == false) {
            vault.deployEligibilityStorage(
                params.eligibilityStorage.moduleIndex,
                params.eligibilityStorage.initData
            );
        }

        if (params.nftIds.length > 0) {
            if (!params.vaultInfo.is1155) {
                // transfer NFTs to the vault
                TransferLib.transferFromERC721(
                    params.vaultInfo.assetAddress,
                    address(vault),
                    params.nftIds
                );
            } else {
                // transfer NFTs to this address
                IERC1155(params.vaultInfo.assetAddress).safeBatchTransferFrom(
                    msg.sender,
                    address(this),
                    params.nftIds,
                    params.nftAmounts,
                    ""
                );

                // approve vault to pull NFTs from this contract
                IERC1155(params.vaultInfo.assetAddress).setApprovalForAll(
                    address(vault),
                    true
                );
            }

            uint256 vTokensBalance = vault.mint(
                params.nftIds,
                params.nftAmounts,
                msg.sender,
                address(this)
            );

            // set up liquidity, if requested
            if (params.liquidityParams.fee > 0) {
                // Min amounts checks
                if (msg.value < params.liquidityParams.wethMin)
                    revert InsufficientETHSent();
                if (vTokensBalance < params.liquidityParams.vTokenMin)
                    revert InsufficientVTokensMinted();

                TransferLib.unSafeMaxApprove(
                    address(vault),
                    address(nftxRouter),
                    vTokensBalance
                );

                // calculating ticks corresponding to prices provided
                bool isVToken0 = address(vault) < address(WETH);
                (
                    int24 tickLower,
                    int24 tickUpper,
                    uint160 currentSqrtPriceX96
                ) = _getTicks(
                        params.liquidityParams.currentNFTPriceInETH,
                        params.liquidityParams.lowerNFTPriceInETH,
                        params.liquidityParams.upperNFTPriceInETH,
                        params.liquidityParams.fee,
                        isVToken0
                    );

                uint256[] memory emptyIds;
                nftxRouter.addLiquidity{value: msg.value}(
                    INFTXRouter.AddLiquidityParams({
                        vaultId: vaultId,
                        vTokensAmount: vTokensBalance,
                        nftIds: emptyIds,
                        nftAmounts: emptyIds,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        fee: params.liquidityParams.fee,
                        sqrtPriceX96: currentSqrtPriceX96,
                        vTokenMin: params.liquidityParams.vTokenMin,
                        wethMin: params.liquidityParams.wethMin,
                        deadline: params.liquidityParams.deadline
                    })
                );

                // update with any dust left
                vTokensBalance = vault.balanceOf(address(this));
            }

            // vTokens left after providing liquidity are put into inventory staking
            if (vTokensBalance > 0) {
                // if dust above the min allowed value
                if (vTokensBalance > MINIMUM_INVENTORY_LIQUIDITY) {
                    TransferLib.unSafeMaxApprove(
                        address(vault),
                        address(inventoryStaking),
                        vTokensBalance
                    );

                    inventoryStaking.deposit(
                        vaultId,
                        vTokensBalance,
                        msg.sender,
                        true // forceTimelock as we minted the vTokens with NFTs
                    );
                } else {
                    // dust amount worthless for the user, so send to InventoryStaking as reward for future stakers
                    vault.transfer(address(inventoryStaking), vTokensBalance);
                }
            }
        }

        // If vault features other than default (all enabled) requested
        // if all enabled, then packed bits = `111` => `7` in uint256
        if (params.vaultFeaturesFlag < 7) {
            vault.setVaultFeatures(
                _getBoolean(params.vaultFeaturesFlag, 2),
                _getBoolean(params.vaultFeaturesFlag, 1),
                _getBoolean(params.vaultFeaturesFlag, 0)
            );
        }

        vault.setFees(
            params.vaultFees.mintFee,
            params.vaultFees.redeemFee,
            params.vaultFees.swapFee
        );

        // send any extra ETH sent
        uint256 remainingETH = address(this).balance;
        if (remainingETH > 0) {
            TransferLib.transferETH(msg.sender, remainingETH);
        }
    }

    // =============================================================
    //                        INTERNAL HELPERS
    // =============================================================

    function _getTicks(
        uint256 currentNFTPriceInETH,
        uint256 lowerNFTPriceInETH,
        uint256 upperNFTPriceInETH,
        uint24 fee,
        bool isVToken0
    )
        internal
        view
        returns (int24 tickLower, int24 tickUpper, uint160 currentSqrtPriceX96)
    {
        uint256 tickDistance = uint24(ammFactory.feeAmountTickSpacing(fee));
        if (isVToken0) {
            currentSqrtPriceX96 = TickHelpers.encodeSqrtRatioX96(
                currentNFTPriceInETH,
                1 ether
            );
            // price = amount1 / amount0 = 1.0001^tick => tick ∝ price
            tickLower = TickHelpers.getTickForAmounts(
                lowerNFTPriceInETH,
                1 ether,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                upperNFTPriceInETH,
                1 ether,
                tickDistance
            );
        } else {
            currentSqrtPriceX96 = TickHelpers.encodeSqrtRatioX96(
                1 ether,
                currentNFTPriceInETH
            );
            tickLower = TickHelpers.getTickForAmounts(
                1 ether,
                upperNFTPriceInETH,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                1 ether,
                lowerNFTPriceInETH,
                tickDistance
            );
        }
    }

    /**
     * @notice Reads a boolean at a set character index of a uint.
     *
     * @dev 0 and 1 define false and true respectively.
     *
     * @param packedBools A numeric representation of a series of boolean values
     * @param boolNumber The character index of the boolean we are looking up
     *
     * @return bool The representation of the boolean value
     */

    function _getBoolean(
        uint256 packedBools,
        uint256 boolNumber
    ) internal pure returns (bool) {
        uint256 flag = (packedBools >> boolNumber) & uint256(1);
        return (flag == 1 ? true : false);
    }

    receive() external payable {
        // Refund extra ETH from positionManger when called via NFTXRouter
        require(msg.sender == address(positionManager));
    }
}
