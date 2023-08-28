// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {SafeCast} from "@uni-core/libraries/SafeCast.sol";
import {TransferLib} from "@src/lib/TransferLib.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {INFTXFeeDistributorV3} from "@src/interfaces/INFTXFeeDistributorV3.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";

/**
 * @title Marketplace Universal Router Zap
 * @author @apoorvlathey
 *
 * @notice Marketplace Zap that utilizes Universal Router to facilitate the require token swaps
 * @dev This Zap must be excluded from the vault fees, as vault fees handled via custom logic here.
 */

contract MarketplaceUniversalRouterZap is Ownable, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    IWETH9 public immutable WETH;
    IPermitAllowanceTransfer public immutable PERMIT2;
    INFTXVaultFactoryV3 public immutable nftxVaultFactory;
    address public immutable inventoryStaking;

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    // =============================================================
    //                           VARIABLES
    // =============================================================

    address public universalRouter;

    /// @notice Allows zap to be paused
    bool public paused = false;

    /// @notice The vToken threshold below which dust is sent to InventoryStaking, else back to the user
    uint256 public dustThreshold;

    // =============================================================
    //                            EVENTS
    // =============================================================

    /// @param count The number of tokens affected by the event
    /// @param ethReceived The amount of ETH received in the sell
    /// @param to The user affected by the event
    /// @param netRoyaltyAmount The royalty amount sent
    /// @param wethFees Vault fees paid
    event Sell(
        uint256 count,
        uint256 ethReceived,
        address to,
        uint256 netRoyaltyAmount,
        uint256 wethFees
    );

    /// @param ethSpent The amount of ETH spent in the swap
    /// @param to The user affected by the event
    event Swap(uint256[] idsIn, uint256[] idsOut, uint256 ethSpent, address to);

    event Swap(
        uint256[] idsIn,
        uint256[] amounts,
        uint256[] idsOut,
        uint256 ethSpent,
        address to
    );

    /// @param nftIds The nftIds bought
    /// @param ethSpent The amount of ETH spent in the buy
    /// @param to The user affected by the event
    /// @param netRoyaltyAmount The royalty amount sent
    event Buy(
        uint256[] nftIds,
        uint256 ethSpent,
        address to,
        uint256 netRoyaltyAmount
    );

    /// @notice Emitted when dust is returned after a transaction.
    /// @param ethAmount Amount of ETH returned to user
    /// @param vTokenAmount Amount of vToken returned to user
    /// @param to The user affected by the event
    event DustReturned(uint256 ethAmount, uint256 vTokenAmount, address to);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error ZapPaused();
    error SwapFailed();
    error UnableToSendETH();

    // =============================================================
    //                           INIT
    // =============================================================

    constructor(
        INFTXVaultFactoryV3 nftxVaultFactory_,
        address universalRouter_,
        IPermitAllowanceTransfer PERMIT2_,
        address inventoryStaking_,
        IWETH9 WETH_
    ) {
        nftxVaultFactory = nftxVaultFactory_;
        universalRouter = universalRouter_;
        PERMIT2 = PERMIT2_;
        inventoryStaking = inventoryStaking_;
        WETH = WETH_;
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    /**
     * @notice Sell idsIn to ETH
     *
     * @dev idsIn --{--mint-> [vault] -> vTokens --sell-> [UniversalRouter] --}-> ETH
     *
     * @param vaultId The ID of the NFTX vault
     * @param idsIn An array of token IDs to be deposited
     * @param executeCallData Encoded calldata for Universal Router's `execute` function
     * @param to The recipient of ETH from the tx
     */
    function sell721(
        uint256 vaultId,
        uint256[] calldata idsIn,
        bytes calldata executeCallData,
        address payable to,
        bool deductRoyalty
    ) external onlyOwnerIfPaused {
        // Mint (vault fees not deducted here, as zap is on exclusion list)
        (address vault, address assetAddress) = _mint721(vaultId, idsIn);

        // swap vTokens to WETH
        (uint256 wethAmount, ) = _swapTokens(
            vault,
            address(WETH),
            executeCallData
        );

        // distributing vault fees with the weth received
        uint256 wethFees = _ethMintFees(INFTXVaultV3(vault), idsIn.length);
        _distributeVaultFees(vaultId, wethFees, true);

        uint256 netRoyaltyAmount;
        if (deductRoyalty) {
            netRoyaltyAmount = _deductRoyalty(assetAddress, idsIn, wethAmount);
        }

        wethAmount -= (wethFees + netRoyaltyAmount); // if underflow, then revert desired

        // convert WETH to ETH and send remaining ETH to `to`
        _wethToETHResidue(to, wethAmount);

        // Emit our sale event
        emit Sell(idsIn.length, wethAmount, to, netRoyaltyAmount, wethFees);
    }

    /**
     * @notice Swap idsIn to idsOut
     * Send ETH along as well (via msg.value) to account for swap fees
     */
    function swap721(
        uint256 vaultId,
        uint256[] calldata idsIn,
        uint256[] calldata idsOut,
        uint256 vTokenPremiumLimit,
        address payable to
    ) external payable onlyOwnerIfPaused {
        // Transfer tokens from the message sender to the vault
        (address vault, ) = _transferSender721ToVault(vaultId, idsIn);

        // Swap our tokens. Forcing to deduct vault fees
        uint256[] memory emptyIds;
        uint256 ethFees = INFTXVaultV3(vault).swap{value: msg.value}(
            idsIn,
            emptyIds,
            idsOut,
            msg.sender,
            to,
            vTokenPremiumLimit,
            true
        );

        // send back remaining ETH
        _sendETHResidue(to);

        emit Swap(idsIn, idsOut, ethFees, to);
    }

    /**
     * @notice Buy idsOut with ETH
     *
     * @dev ETH --{-sell-> [UniversalRouter] -> vTokens + ETH --redeem-> [vault] --}-> idsOut
     *
     * @param vaultId The ID of the NFTX vault
     * @param idsOut An array of any token IDs to be redeemed
     * @param executeCallData Encoded calldata for Universal Router's `execute` function
     * @param to The recipient of the token IDs from the tx
     */
    function buyNFTsWithETH(
        uint256 vaultId,
        uint256[] calldata idsOut,
        bytes calldata executeCallData,
        address payable to,
        uint256 vTokenPremiumLimit,
        bool deductRoyalty
    ) external payable onlyOwnerIfPaused {
        // Wrap ETH into WETH for our contract
        WETH.deposit{value: msg.value}();

        // swap WETH to vTokens
        uint256 iniWETHBal = WETH.balanceOf(address(this));
        address vault = nftxVaultFactory.vault(vaultId);
        _swapTokens(address(WETH), vault, executeCallData);
        uint256 wethSpent = iniWETHBal - WETH.balanceOf(address(this));

        uint256 wethLeft = msg.value - wethSpent;

        // redeem NFTs. Forcing to deduct vault fees
        TransferLib.unSafeMaxApprove(address(WETH), vault, wethLeft);
        uint256 wethFees = INFTXVaultV3(vault).redeem(
            idsOut,
            to,
            wethLeft,
            vTokenPremiumLimit,
            true
        );

        uint256 netRoyaltyAmount;
        if (deductRoyalty) {
            address assetAddress = INFTXVaultV3(vault).assetAddress();
            netRoyaltyAmount = _deductRoyalty(assetAddress, idsOut, wethSpent);
        }

        // transfer vToken dust and remaining WETH balance
        _transferDust(vault, true);

        emit Buy(
            idsOut,
            wethSpent + wethFees + netRoyaltyAmount,
            to,
            netRoyaltyAmount
        );
    }

    struct BuyNFTsWithERC20Params {
        IERC20 tokenIn; // Input ERC20 token
        uint256 amountIn; // Input ERC20 amount
        uint256 vaultId; // The ID of the NFTX vault
        uint256[] idsOut; // An array of any token IDs to be redeemed
        uint256 vTokenPremiumLimit;
        bytes executeToWETHCallData; // Encoded calldata for "ERC20 to WETH swap" for Universal Router's `execute` function
        bytes executeToVTokenCallData; // Encoded calldata for "WETH to vToken swap" for Universal Router's `execute` function
        address payable to; // The recipient of the token IDs from the tx
        bool deductRoyalty;
    }

    /**
     * @notice Buy idsOut with ERC20
     *
     * @dev ERC20 --{-sell-> [UniversalRouter] -> ETH -> [UniversalRouter] -> vTokens + ETH --redeem-> [vault] --}-> idsOut
     */
    function buyNFTsWithERC20(
        BuyNFTsWithERC20Params calldata params
    ) external onlyOwnerIfPaused {
        params.tokenIn.safeTransferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );

        return _buyNFTsWithERC20(params);
    }

    function buyNFTsWithERC20WithPermit2(
        BuyNFTsWithERC20Params calldata params,
        bytes calldata encodedPermit2
    ) external onlyOwnerIfPaused {
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

        PERMIT2.transferFrom(
            msg.sender,
            address(this),
            SafeCast.toUint160(params.amountIn),
            address(params.tokenIn)
        );

        return _buyNFTsWithERC20(params);
    }

    /**
     * @notice Sell idsIn to ETH
     *
     * @dev idsIn --{--mint-> [vault] -> vTokens --sell-> [UniversalRouter] --}-> ETH
     *
     * @param vaultId The ID of the NFTX vault
     * @param idsIn An array of token IDs to be deposited
     * @param executeCallData Encoded calldata for Universal Router's `execute` function
     * @param to The recipient of ETH from the tx
     */
    function sell1155(
        uint256 vaultId,
        uint256[] calldata idsIn,
        uint256[] calldata amounts,
        bytes calldata executeCallData,
        address payable to,
        bool deductRoyalty
    ) external onlyOwnerIfPaused {
        // Mint (vault fees not deducted here, as zap is on exclusion list)
        (address vault, address assetAddress) = _mint1155(
            vaultId,
            idsIn,
            amounts
        );

        uint256 totalAmount = _validate1155Ids(idsIn, amounts);

        // swap vTokens to WETH
        (uint256 wethAmount, ) = _swapTokens(
            vault,
            address(WETH),
            executeCallData
        );

        // distributing vault fees with the weth received
        uint256 wethFees = _ethMintFees(INFTXVaultV3(vault), totalAmount);
        _distributeVaultFees(vaultId, wethFees, true);

        uint256 netRoyaltyAmount;
        if (deductRoyalty) {
            netRoyaltyAmount = _deductRoyalty1155(
                assetAddress,
                idsIn,
                amounts,
                wethAmount
            );
        }

        wethAmount -= (wethFees + netRoyaltyAmount); // if underflow, then revert desired

        // convert WETH to ETH and send remaining ETH to `to`
        _wethToETHResidue(to, wethAmount);

        // Emit our sale event
        emit Sell(totalAmount, wethAmount, to, netRoyaltyAmount, wethFees);
    }

    /**
     * @notice Swap idsIn to idsOut
     * Send ETH along as well (via msg.value) to account for swap fees
     */
    function swap1155(
        uint256 vaultId,
        uint256[] calldata idsIn,
        uint256[] calldata amounts,
        uint256[] calldata idsOut,
        uint256 vTokenPremiumLimit,
        address payable to
    ) external payable onlyOwnerIfPaused {
        address vault = nftxVaultFactory.vault(vaultId);

        address assetAddress = INFTXVaultV3(vault).assetAddress();
        IERC1155(assetAddress).safeBatchTransferFrom(
            msg.sender,
            address(this),
            idsIn,
            amounts,
            ""
        );

        IERC1155(assetAddress).setApprovalForAll(vault, true);

        // Swap our tokens. Forcing to deduct vault fees
        uint256 ethFees = INFTXVaultV3(vault).swap{value: msg.value}(
            idsIn,
            amounts,
            idsOut,
            msg.sender,
            to,
            vTokenPremiumLimit,
            true
        );

        // send back remaining ETH
        _sendETHResidue(to);

        emit Swap(idsIn, amounts, idsOut, ethFees, to);
    }

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    /**
     * @notice A modifier that only allows the owner to interact with the function
     * if the contract is paused. If the contract is not paused then anyone can
     * interact with the function.
     */

    modifier onlyOwnerIfPaused() {
        if (paused && msg.sender != owner()) revert ZapPaused();
        _;
    }

    /**
     * @notice Allows our zap to be paused to prevent any processing.
     *
     * @param paused_ New pause state
     */

    function pause(bool paused_) external onlyOwner {
        paused = paused_;
    }

    function setUniversalRouter(address universalRouter_) external onlyOwner {
        universalRouter = universalRouter_;
    }

    function setDustThreshold(uint256 dustThreshold_) external onlyOwner {
        dustThreshold = dustThreshold_;
    }

    // =============================================================
    //                      INTERNAL / PRIVATE
    // =============================================================

    function _buyNFTsWithERC20(
        BuyNFTsWithERC20Params calldata params
    ) internal {
        // swap tokenIn to WETH
        _swapTokens(
            address(params.tokenIn),
            address(WETH),
            params.executeToWETHCallData
        );

        // swap some WETH to vTokens
        uint256 iniWETHBal = WETH.balanceOf(address(this));
        address vault = nftxVaultFactory.vault(params.vaultId);

        _swapTokens(address(WETH), vault, params.executeToVTokenCallData);

        uint256 wethLeft = WETH.balanceOf(address(this));
        uint256 wethSpent = iniWETHBal - wethLeft;

        // redeem NFTs
        TransferLib.unSafeMaxApprove(address(WETH), vault, wethLeft);
        uint256 wethFees = INFTXVaultV3(vault).redeem(
            params.idsOut,
            params.to,
            wethLeft,
            params.vTokenPremiumLimit,
            true
        );

        uint256 netRoyaltyAmount;
        if (params.deductRoyalty) {
            address assetAddress = INFTXVaultV3(vault).assetAddress();
            netRoyaltyAmount = _deductRoyalty(
                assetAddress,
                params.idsOut,
                wethSpent
            );
        }

        // transfer vToken dust and remaining WETH balance
        _transferDust(vault, true);

        emit Buy(
            params.idsOut,
            wethSpent + wethFees + netRoyaltyAmount,
            params.to,
            netRoyaltyAmount
        );
    }

    /**
     * @param vaultId The ID of the NFTX vault
     * @param ids An array of token IDs to be minted
     */
    function _mint721(
        uint256 vaultId,
        uint256[] calldata ids
    ) internal returns (address vault, address assetAddress) {
        // Transfer tokens from the message sender to the vault
        (vault, assetAddress) = _transferSender721ToVault(vaultId, ids);

        // Mint our tokens from the vault to this contract
        uint256[] memory emptyIds;
        INFTXVaultV3(vault).mint(ids, emptyIds, msg.sender, address(this));
    }

    function _mint1155(
        uint256 vaultId,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) internal returns (address vault, address assetAddress) {
        vault = nftxVaultFactory.vault(vaultId);

        assetAddress = INFTXVaultV3(vault).assetAddress();
        IERC1155(assetAddress).safeBatchTransferFrom(
            msg.sender,
            address(this),
            ids,
            amounts,
            ""
        );
        IERC1155(assetAddress).setApprovalForAll(vault, true);

        // Mint our tokens from the vault to this contract
        INFTXVaultV3(vault).mint(ids, amounts, msg.sender, address(this));
    }

    function _validate1155Ids(
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) internal pure returns (uint256 totalAmount) {
        // Sum the amounts for our emitted events
        for (uint i; i < ids.length; ) {
            unchecked {
                // simultaneously verifies that lengths of `ids` and `amounts` match.
                totalAmount += amounts[i];
                ++i;
            }
        }
    }

    function _transferSender721ToVault(
        uint256 vaultId,
        uint256[] calldata ids
    ) internal returns (address vault, address assetAddress) {
        // Get our vault address information
        vault = nftxVaultFactory.vault(vaultId);

        assetAddress = INFTXVaultV3(vault).assetAddress();

        // Transfer tokens from the message sender to the vault
        TransferLib.transferFromERC721(assetAddress, address(vault), ids);
    }

    /**
     * @notice Swaps ERC20->ERC20 tokens using Universal Router.
     *
     * @param executeCallData Encoded calldata for Universal Router's `execute` function
     */
    function _swapTokens(
        address sellToken,
        address buyToken,
        bytes calldata executeCallData
    ) internal returns (uint256 boughtAmount, uint256 finalBuyTokenBalance) {
        // Track our balance of the buyToken to determine how much we've bought.
        uint256 iniBuyTokenBalance = IERC20(buyToken).balanceOf(address(this));

        _permit2ApproveToken(sellToken, address(universalRouter));

        // execute swap
        (bool success, ) = address(universalRouter).call(executeCallData);
        if (!success) revert SwapFailed();

        // Use our current buyToken balance to determine how much we've bought.
        finalBuyTokenBalance = IERC20(buyToken).balanceOf(address(this));
        boughtAmount = finalBuyTokenBalance - iniBuyTokenBalance;
    }

    function _permit2ApproveToken(address token, address spender) internal {
        (uint160 permitAllowance, , ) = PERMIT2.allowance(
            address(this),
            token,
            spender
        );
        if (
            permitAllowance >=
            uint160(0xf000000000000000000000000000000000000000) // sufficiently large value
        ) return;

        IERC20(token).safeApprove(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(token, spender, type(uint160).max, type(uint48).max);
    }

    function _ethMintFees(
        INFTXVaultV3 vToken,
        uint256 nftCount
    ) internal view returns (uint256) {
        (uint256 mintFee, , ) = vToken.vaultFees();

        return vToken.vTokenToETH(mintFee * nftCount);
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
                WETH.deposit{value: ethAmount}();
            }
            WETH.transfer(address(feeDistributor), ethAmount);
            feeDistributor.distribute(vaultId);
        }
    }

    function _deductRoyalty(
        address nft,
        uint256[] calldata idsIn,
        uint256 netWethAmount
    ) internal returns (uint256 netRoyaltyAmount) {
        bool success = IERC2981(nft).supportsInterface(_INTERFACE_ID_ERC2981);
        if (success) {
            uint256 salePrice = netWethAmount / idsIn.length;

            for (uint256 i; i < idsIn.length; ) {
                (address receiver, uint256 royaltyAmount) = IERC2981(nft)
                    .royaltyInfo(idsIn[i], salePrice);
                netRoyaltyAmount += royaltyAmount;

                if (royaltyAmount > 0) {
                    WETH.transfer(receiver, royaltyAmount);
                }

                unchecked {
                    ++i;
                }
            }
        }
    }

    function _deductRoyalty1155(
        address nft,
        uint256[] calldata idsIn,
        uint256[] calldata amounts,
        uint256 netWethAmount
    ) internal returns (uint256 netRoyaltyAmount) {
        bool success = IERC2981(nft).supportsInterface(_INTERFACE_ID_ERC2981);
        if (success) {
            uint256 salePrice = netWethAmount / idsIn.length;

            for (uint256 i; i < idsIn.length; ) {
                (address receiver, uint256 royaltyAmount) = IERC2981(nft)
                    .royaltyInfo(idsIn[i], salePrice);

                uint256 royaltyToPay = royaltyAmount * amounts[i];
                netRoyaltyAmount += royaltyToPay;

                if (royaltyToPay > 0) {
                    WETH.transfer(receiver, royaltyToPay);
                }

                unchecked {
                    ++i;
                }
            }
        }
    }

    function _allWethToETHResidue(
        address to
    ) internal returns (uint256 wethAmount) {
        wethAmount = WETH.balanceOf(address(this));
        _wethToETHResidue(to, wethAmount);
    }

    function _wethToETHResidue(address to, uint256 wethAmount) internal {
        if (wethAmount > 0) {
            // Unwrap our WETH into ETH and transfer it to the recipient
            WETH.withdraw(wethAmount);
        }
        _sendETHResidue(to);
    }

    function _sendETHResidue(address to) internal {
        // sending entire ETH balance (hence accounting for the unused msg.value)
        (bool success, ) = payable(to).call{value: address(this).balance}("");
        if (!success) revert UnableToSendETH();
    }

    /**
     * @notice Transfers remaining ETH to msg.sender.
     * And transfers vault token dust to feeDistributor if below dustThreshold, else to msg.sender
     *
     * @param vault Address of the vault token
     * @param hasWETHDust Checks and transfers WETH dust if boolean is true
     */
    function _transferDust(address vault, bool hasWETHDust) internal {
        uint256 wethRemaining;
        if (hasWETHDust) {
            wethRemaining = _allWethToETHResidue(msg.sender);
        }

        uint256 dustBalance = IERC20(vault).balanceOf(address(this));
        address dustRecipient;
        if (dustBalance > 0) {
            if (dustBalance > dustThreshold) {
                dustRecipient = msg.sender;
            } else {
                dustRecipient = inventoryStaking;
            }

            IERC20(vault).transfer(dustRecipient, dustBalance);
        }

        emit DustReturned(wethRemaining, dustBalance, dustRecipient);
    }

    receive() external payable {}
}
