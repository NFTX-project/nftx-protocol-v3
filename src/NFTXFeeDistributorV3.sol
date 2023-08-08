// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

// inheriting
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// libs
import {TransferLib} from "@src/lib/TransferLib.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import {INFTXRouter} from "@src/interfaces/INFTXRouter.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {IUniswapV3Pool} from "@uni-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uni-core/interfaces/IUniswapV3Factory.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {INFTXInventoryStakingV3} from "@src/interfaces/INFTXInventoryStakingV3.sol";

import {INFTXFeeDistributorV3} from "@src/interfaces/INFTXFeeDistributorV3.sol";

/**
 * @title NFTX Fee Distributor V3
 * @author @apoorvlathey
 *
 * @notice Allows distribution of vault fees between multiple receivers including inventory stakers and NFTX AMM liquidity providers.
 */
contract NFTXFeeDistributorV3 is
    INFTXFeeDistributorV3,
    Ownable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    INFTXVaultFactoryV3 public immutable override nftxVaultFactory;
    IUniswapV3Factory public immutable override ammFactory;
    INFTXInventoryStakingV3 public immutable override inventoryStaking;
    IERC20 public immutable override WETH;

    uint256 constant POOL_DEFAULT_ALLOC = 0.8 ether; // 80%
    uint256 constant INVENTORY_DEFAULT_ALLOC = 0.2 ether; // 20%

    // =============================================================
    //                           VARIABLES
    // =============================================================

    uint24 public override rewardFeeTier;
    INFTXRouter public override nftxRouter;
    address public override treasury;

    // Total of allocation points per feeReceiver.
    uint256 public override allocTotal;
    FeeReceiver[] public override feeReceivers;

    bool public override distributionPaused;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(
        INFTXVaultFactoryV3 nftxVaultFactory_,
        IUniswapV3Factory ammFactory_,
        INFTXInventoryStakingV3 inventoryStaking_,
        INFTXRouter nftxRouter_,
        address treasury_
    ) {
        nftxVaultFactory = nftxVaultFactory_;
        ammFactory = ammFactory_;
        inventoryStaking = inventoryStaking_;
        WETH = IERC20(nftxRouter_.WETH());
        nftxRouter = nftxRouter_;
        treasury = treasury_;

        rewardFeeTier = 10_000;

        FeeReceiver[] memory feeReceivers_ = new FeeReceiver[](2);
        feeReceivers_[0] = FeeReceiver({
            receiver: address(0),
            allocPoint: POOL_DEFAULT_ALLOC,
            receiverType: ReceiverType.POOL
        });
        feeReceivers_[1] = FeeReceiver({
            receiver: address(inventoryStaking_),
            allocPoint: INVENTORY_DEFAULT_ALLOC,
            receiverType: ReceiverType.INVENTORY
        });
        setReceivers(feeReceivers_);
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    /**
     * @inheritdoc INFTXFeeDistributorV3
     */
    function distribute(uint256 vaultId) external override nonReentrant {
        INFTXVaultV3 vault = INFTXVaultV3(nftxVaultFactory.vault(vaultId));

        uint256 wethBalance = WETH.balanceOf(address(this));

        if (distributionPaused || allocTotal == 0) {
            WETH.transfer(treasury, wethBalance);
            return;
        }

        uint256 leftover;
        for (uint256 i; i < feeReceivers.length; ) {
            FeeReceiver storage feeReceiver = feeReceivers[i];

            uint256 wethAmountToSend = leftover +
                (wethBalance * feeReceiver.allocPoint) /
                allocTotal;

            bool tokenSent = _sendForReceiver(
                feeReceiver,
                wethAmountToSend,
                vaultId,
                vault
            );
            leftover += tokenSent ? 0 : wethAmountToSend;

            unchecked {
                ++i;
            }
        }

        if (leftover > 0) {
            WETH.transfer(treasury, leftover);
        }
    }

    /**
     * @inheritdoc INFTXFeeDistributorV3
     */
    function distributeVTokensToPool(
        address pool,
        address vToken,
        uint256 vTokenAmount
    ) external {
        require(msg.sender == address(nftxRouter));

        uint256 liquidity = IUniswapV3Pool(pool).liquidity();
        if (liquidity > 0) {
            IERC20(vToken).transfer(pool, vTokenAmount);
            IUniswapV3Pool(pool).distributeRewards(
                vTokenAmount,
                true // isVToken0
            );
        } else {
            // distribute to inventory stakers if pool doesn't have liquidity
            IERC20(vToken).transfer(address(inventoryStaking), vTokenAmount);
        }
    }

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    function setReceivers(
        FeeReceiver[] memory feeReceivers_
    ) public override onlyOwner {
        delete feeReceivers;

        uint256 _allocTotal;
        uint256 len = feeReceivers_.length;
        for (uint256 i; i < len; ) {
            feeReceivers.push(feeReceivers_[i]);
            _allocTotal += feeReceivers_[i].allocPoint;

            unchecked {
                ++i;
            }
        }

        allocTotal = _allocTotal;
    }

    /**
     * @inheritdoc INFTXFeeDistributorV3
     */
    function changeRewardFeeTier(
        uint24 rewardFeeTier_
    ) external override onlyOwner {
        // check if feeTier enabled
        require(ammFactory.feeAmountTickSpacing(rewardFeeTier_) > 0);

        rewardFeeTier = rewardFeeTier_;
    }

    /**
     * @inheritdoc INFTXFeeDistributorV3
     */
    function setTreasuryAddress(address treasury_) external override onlyOwner {
        if (treasury_ == address(0)) revert AddressIsZero();

        treasury = treasury_;
        emit UpdateTreasuryAddress(treasury_);
    }

    /**
     * @inheritdoc INFTXFeeDistributorV3
     */
    function setNFTXRouter(
        INFTXRouter nftxRouter_
    ) external override onlyOwner {
        nftxRouter = nftxRouter_;
    }

    /**
     * @inheritdoc INFTXFeeDistributorV3
     */
    function pauseFeeDistribution(bool pause) external override onlyOwner {
        distributionPaused = pause;
        emit PauseDistribution(pause);
    }

    /**
     * @inheritdoc INFTXFeeDistributorV3
     */
    function rescueTokens(IERC20 token) external override onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, balance);
    }

    // =============================================================
    //                      INTERNAL / PRIVATE
    // =============================================================

    function _sendForReceiver(
        FeeReceiver storage feeReceiver,
        uint256 wethAmountToSend,
        uint256 vaultId,
        INFTXVaultV3 vault
    ) internal returns (bool tokenSent) {
        if (feeReceiver.receiverType == ReceiverType.INVENTORY) {
            TransferLib.unSafeMaxApprove(
                address(WETH),
                feeReceiver.receiver,
                wethAmountToSend
            );

            // Inventory Staking might not pull tokens in case where `vaultGlobal[vaultId].totalVTokenShares` is zero
            bool pulledTokens = inventoryStaking.receiveWethRewards(
                vaultId,
                wethAmountToSend
            );

            tokenSent = pulledTokens;
        } else if (feeReceiver.receiverType == ReceiverType.POOL) {
            (address pool, bool exists) = nftxRouter.getPoolExists(
                vaultId,
                rewardFeeTier
            );

            if (exists) {
                uint256 liquidity = IUniswapV3Pool(pool).liquidity();

                if (liquidity > 0) {
                    WETH.transfer(pool, wethAmountToSend);
                    IUniswapV3Pool(pool).distributeRewards(
                        wethAmountToSend,
                        address(vault) > address(WETH) // !isVToken0
                    );

                    tokenSent = true;
                }
            }
        } else {
            WETH.transfer(feeReceiver.receiver, wethAmountToSend);
            tokenSent = true;
        }
    }
}
