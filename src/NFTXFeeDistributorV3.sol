// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";
import {INFTXVault} from "@src/v2/interface/INFTXVault.sol";
import {INFTXInventoryStaking} from "@src/v2/interface/INFTXInventoryStaking.sol";
import {IUniswapV3Pool} from "@uni-core/interfaces/IUniswapV3Pool.sol";
import {INFTXRouter} from "./interfaces/INFTXRouter.sol";

import {INFTXFeeDistributorV3} from "./interfaces/INFTXFeeDistributorV3.sol";

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

    INFTXVaultFactory public immutable override nftxVaultFactory;
    INFTXInventoryStaking public immutable override inventoryStaking;
    IERC20 public immutable override WETH;
    uint24 public constant override REWARD_FEE_TIER = 10000;

    // =============================================================
    //                            STORAGE
    // =============================================================

    INFTXRouter public override nftxRouter;
    address public override treasury;

    // Total of allocation points per feeReceiver.
    uint256 public override allocTotal;
    FeeReceiver[] public feeReceivers;

    bool public override distributionPaused;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(
        INFTXInventoryStaking inventoryStaking_,
        INFTXRouter nftxRouter_,
        address treasury_
    ) {
        nftxVaultFactory = inventoryStaking_.nftxVaultFactory();
        inventoryStaking = inventoryStaking_;
        WETH = IERC20(nftxRouter_.WETH());
        nftxRouter = nftxRouter_;
        treasury = treasury_;

        // set 80% allocation to liquidity providers
        _addReceiver(address(0), 0.8 ether, ReceiverType.POOL);
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    // TODO: modify/remove for new Inventory Staking V3
    function initializeVaultReceivers(uint256 vaultId) external override {
        inventoryStaking.deployXTokenForVault(vaultId);
    }

    function distribute(uint256 vaultId) external override nonReentrant {
        INFTXVault vault = INFTXVault(nftxVaultFactory.vault(vaultId));

        uint256 wethBalance = WETH.balanceOf(address(this));

        if (distributionPaused || allocTotal == 0) {
            WETH.transfer(treasury, wethBalance);
            return;
        }

        uint256 leftover;
        for (uint256 i; i < feeReceivers.length; ) {
            FeeReceiver storage feeReceiver = feeReceivers[i];

            uint256 amountToSend = leftover +
                (wethBalance * feeReceiver.allocPoint) /
                allocTotal;

            bool tokenSent = _sendForReceiver(
                feeReceiver,
                amountToSend,
                vaultId,
                vault
            );
            leftover = tokenSent ? 0 : amountToSend;

            unchecked {
                ++i;
            }
        }

        if (leftover > 0) {
            WETH.transfer(treasury, leftover);
        }
    }

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    function addReceiver(
        address receiver,
        uint256 allocPoint,
        ReceiverType receiverType
    ) external override onlyOwner {
        _addReceiver(receiver, allocPoint, receiverType);
    }

    function changeReceiverAlloc(
        uint256 receiverId,
        uint256 allocPoint
    ) external override onlyOwner {
        if (receiverId >= feeReceivers.length) revert IdOutOfBounds();

        FeeReceiver storage feeReceiver = feeReceivers[receiverId];
        allocTotal -= feeReceiver.allocPoint;
        feeReceiver.allocPoint = allocPoint;
        allocTotal += allocPoint;

        emit UpdateFeeReceiverAlloc(feeReceiver.receiver, allocPoint);
    }

    function changeReceiverAddress(
        uint256 receiverId,
        address receiver,
        ReceiverType receiverType
    ) external override onlyOwner {
        FeeReceiver storage feeReceiver = feeReceivers[receiverId];
        address oldReceiver = feeReceiver.receiver;
        feeReceiver.receiver = receiver;
        feeReceiver.receiverType = receiverType;

        emit UpdateFeeReceiverAddress(oldReceiver, receiver);
    }

    function removeReceiver(uint256 receiverId) external override onlyOwner {
        uint256 arrLength = feeReceivers.length;
        if (receiverId >= arrLength) revert IdOutOfBounds();

        emit RemoveFeeReceiver(feeReceivers[receiverId].receiver);

        allocTotal -= feeReceivers[receiverId].allocPoint;
        // Copy the last element to what is being removed and remove the last element.
        feeReceivers[receiverId] = feeReceivers[arrLength - 1];
        feeReceivers.pop();
    }

    function setTreasuryAddress(address treasury_) external override onlyOwner {
        if (treasury_ == address(0)) revert AddressIsZero();

        treasury = treasury_;
        emit UpdateTreasuryAddress(treasury_);
    }

    function pauseFeeDistribution(bool pause) external override onlyOwner {
        distributionPaused = pause;
        emit PauseDistribution(pause);
    }

    function rescueTokens(IERC20 token) external override onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, balance);
    }

    // =============================================================
    //                      INTERNAL / PRIVATE
    // =============================================================

    function _addReceiver(
        address receiver,
        uint256 allocPoint,
        ReceiverType receiverType
    ) internal {
        FeeReceiver memory feeReceiver = FeeReceiver({
            receiver: receiver,
            allocPoint: allocPoint,
            receiverType: receiverType
        });
        feeReceivers.push(feeReceiver);
        allocTotal += allocPoint;
        emit AddFeeReceiver(receiver, allocPoint);
    }

    function _sendForReceiver(
        FeeReceiver storage feeReceiver,
        uint256 amountToSend,
        uint256 vaultId,
        INFTXVault vault
    ) internal returns (bool tokenSent) {
        if (feeReceiver.receiverType == ReceiverType.INVENTORY) {
            _maxWethApprove(feeReceiver.receiver, amountToSend);

            // Inventory Staking might not pull tokens in case where the xToken contract is not yet deployed or the XToken totalSupply is zero
            // TODO: modify inventory staking to accept rewards in WETH and uncomment this out
            /**
                bool pulledTokens = inventoryStaking.receiveRewards(
                    vaultId,
                    amountToSend
                );
                
                tokenSent = pulledTokens;
             */
        } else if (feeReceiver.receiverType == ReceiverType.POOL) {
            (address pool, bool exists) = nftxRouter.getPoolExists(
                vaultId,
                REWARD_FEE_TIER
            );

            if (exists) {
                WETH.transfer(pool, amountToSend);
                // TODO: add test case to check this doesn't revert if pool has 0 liquidity
                IUniswapV3Pool(pool).distributeRewards(
                    amountToSend,
                    !nftxRouter.isVToken0(address(vault))
                );

                tokenSent = true;
            }
        } else {
            WETH.transfer(feeReceiver.receiver, amountToSend);
            tokenSent = true;
        }
    }

    /**
     * @dev Setting max allowance to save on gas on subsequent calls.
     * As this contract doesn't hold funds, so this is safe. Also the spender address is only provided by owner via addReceiver.
     */
    function _maxWethApprove(address spender, uint256 amount) internal {
        uint256 allowance = WETH.allowance(address(this), spender);

        if (amount > allowance) {
            WETH.approve(spender, type(uint256).max);
        }
    }
}
