// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";
import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";
import {INFTXVault} from "@src/v2/interface/INFTXVault.sol";
import {INFTXFeeDistributorV3} from "@src/interfaces/INFTXFeeDistributorV3.sol";
import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";

/**
 * @title Marketplace Universal Router Zap
 * @author @apoorvlathey
 *
 * @notice Marketplace Zap that utilizes Universal Router to facilitate the require token swaps
 * @dev This Zap must be excluded from the vault fees, as vault fees handled via custom logic here.
 */

contract MarketplaceUniversalRouterZap is Ownable, ERC721Holder {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    // Set a constant address for specific contracts that need special logic
    address public constant CRYPTO_PUNKS =
        0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
    IWETH9 public immutable WETH;
    IPermitAllowanceTransfer public immutable PERMIT2;
    INFTXVaultFactory public immutable nftxVaultFactory;
    address public immutable inventoryStaking;

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    // =============================================================
    //                            STORAGE
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
    event Sell(uint256 count, uint256 ethReceived, address to);

    /// @param count The number of tokens affected by the event
    /// @param ethSpent The amount of ETH spent in the swap
    /// @param to The user affected by the event
    event Swap(uint256 count, uint256 ethSpent, address to);

    /// @param count The number of tokens affected by the event
    /// @param ethSpent The amount of ETH spent in the buy
    /// @param to The user affected by the event
    event Buy(uint256 count, uint256 ethSpent, address to);

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
        INFTXVaultFactory nftxVaultFactory_,
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
        // Mint
        (address vault, address assetAddress) = _mint721(vaultId, idsIn);

        // swap vTokens to WETH
        (uint256 wethAmount, ) = _swapTokens(
            vault,
            address(WETH),
            executeCallData
        );

        // distributing vault fees with the weth received
        uint256 wethFees = _ethMintFees(INFTXVault(vault), idsIn.length);
        _distributeVaultFees(vaultId, wethFees, true);

        uint256 netRoyaltyAmount;
        if (deductRoyalty) {
            netRoyaltyAmount = _deductRoyalty(assetAddress, idsIn, wethAmount);
        }

        wethAmount -= (wethFees + netRoyaltyAmount); // if underflow, then revert desired

        // convert WETH to ETH and send remaining ETH to `to`
        _wethToETHResidue(to, wethAmount);

        // Emit our sale event
        emit Sell(idsIn.length, wethAmount, to);
    }

    /**
     * @notice Swap idsIn to idsOut
     * Send ETH along as well (via msg.value) to account for swap fees
     */
    function swap721(
        uint256 vaultId,
        uint256[] calldata idsIn,
        uint256[] calldata idsOut,
        address payable to
    ) external payable onlyOwnerIfPaused {
        // Transfer tokens from the message sender to the vault
        (address vault, ) = _transferSender721ToVault(vaultId, idsIn);

        // Swap our tokens
        uint256[] memory emptyIds;
        INFTXVault(vault).swapTo(idsIn, emptyIds, idsOut, to);

        uint256 ethFees = _ethSwapFees(INFTXVault(vault), idsOut);
        _distributeVaultFees(vaultId, ethFees, false);

        // send back remaining ETH
        _sendETHResidue(to);

        emit Swap(idsOut.length, ethFees, to);
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
        bool deductRoyalty
    ) external payable onlyOwnerIfPaused {
        // Wrap ETH into WETH for our contract
        WETH.deposit{value: msg.value}();

        // swap WETH to vTokens
        uint256 iniWETHBal = WETH.balanceOf(address(this));
        address vault = nftxVaultFactory.vault(vaultId);
        _swapTokens(address(WETH), vault, executeCallData);
        uint256 wethSpent = iniWETHBal - WETH.balanceOf(address(this));

        // redeem NFTs
        INFTXVault(vault).redeemTo(idsOut, to);

        // distribute vault fees with remaining weth
        uint256 wethFees = _ethRedeemFees(INFTXVault(vault), idsOut);
        _distributeVaultFees(vaultId, wethFees, true);

        uint256 netRoyaltyAmount;
        if (deductRoyalty) {
            address assetAddress = INFTXVault(vault).assetAddress();
            netRoyaltyAmount = _deductRoyalty(assetAddress, idsOut, wethSpent);
        }

        // transfer vToken dust and remaining WETH balance
        _transferDust(vault, true);

        emit Buy(idsOut.length, wethSpent + wethFees + netRoyaltyAmount, to);
    }

    /**
     * @notice Buy idsOut with ERC20
     *
     * @dev ERC20 --{-sell-> [UniversalRouter] -> ETH -> [UniversalRouter] -> vTokens + ETH --redeem-> [vault] --}-> idsOut
     *
     * @param tokenIn Input ERC20 token
     * @param amountIn Input ERC20 amount
     * @param vaultId The ID of the NFTX vault
     * @param idsOut An array of any token IDs to be redeemed
     * @param executeToWETHCallData Encoded calldata for "ERC20 to WETH swap" for Universal Router's `execute` function
     * @param executeToVTokenCallData Encoded calldata for "WETH to vToken swap" for Universal Router's `execute` function
     * @param to The recipient of the token IDs from the tx
     */
    function buyNFTsWithERC20(
        IERC20 tokenIn,
        uint256 amountIn,
        uint256 vaultId,
        uint256[] calldata idsOut,
        bytes calldata executeToWETHCallData,
        bytes calldata executeToVTokenCallData,
        address payable to,
        bool deductRoyalty
    ) external onlyOwnerIfPaused {
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);

        // swap tokenIn to WETH
        _swapTokens(address(tokenIn), address(WETH), executeToWETHCallData);

        // swap some WETH to vTokens
        uint256 iniWETHBal = WETH.balanceOf(address(this));
        address vault = nftxVaultFactory.vault(vaultId);
        _swapTokens(address(WETH), vault, executeToVTokenCallData);
        uint256 wethSpent = iniWETHBal - WETH.balanceOf(address(this));

        // redeem NFTs
        INFTXVault(vault).redeemTo(idsOut, to);

        // distribute vault fees with remaining weth
        uint256 wethFees = _ethRedeemFees(INFTXVault(vault), idsOut);
        _distributeVaultFees(vaultId, wethFees, true);

        uint256 netRoyaltyAmount;
        if (deductRoyalty) {
            address assetAddress = INFTXVault(vault).assetAddress();
            netRoyaltyAmount = _deductRoyalty(assetAddress, idsOut, wethSpent);
        }

        // transfer vToken dust and remaining WETH balance
        _transferDust(vault, true);

        emit Buy(idsOut.length, wethSpent + wethFees + netRoyaltyAmount, to);
    }

    // TODO: add sell1155

    // TODO: add swap1155

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    /**
     * @notice A modifier that only allows the owner to interact with the function
     * if the contract is paused. If the contract is not paused then anyone can
     * interact with the function.
     */

    modifier onlyOwnerIfPaused() {
        if (paused || msg.sender != owner()) revert ZapPaused();
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

    /**
     * @param vaultId The ID of the NFTX vault
     * @param ids An array of token IDs to be minted
     */
    function _mint721(
        uint256 vaultId,
        uint256[] memory ids
    ) internal returns (address vault, address assetAddress) {
        // Transfer tokens from the message sender to the vault
        (vault, assetAddress) = _transferSender721ToVault(vaultId, ids);

        // Mint our tokens from the vault to this contract
        uint256[] memory emptyIds;
        INFTXVault(vault).mint(ids, emptyIds);
    }

    function _transferSender721ToVault(
        uint256 vaultId,
        uint256[] memory ids
    ) internal returns (address vault, address assetAddress) {
        // Get our vault address information
        vault = nftxVaultFactory.vault(vaultId);

        // Transfer tokens from the message sender to the vault
        assetAddress = INFTXVault(vault).assetAddress();
        uint256 length = ids.length;

        for (uint256 i; i < length; ) {
            _transferFromERC721(assetAddress, ids[i], vault);

            if (assetAddress == CRYPTO_PUNKS) {
                _approveERC721(assetAddress, ids[i], vault);
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Transfers our ERC721 tokens to a specified recipient.
     *
     * @param assetAddr Address of the asset being transferred
     * @param tokenId The ID of the token being transferred
     * @param to The address the token is being transferred to
     */
    function _transferFromERC721(
        address assetAddr,
        uint256 tokenId,
        address to
    ) internal {
        bytes memory data;

        if (assetAddr == CRYPTO_PUNKS) {
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
        } else {
            // We push to the vault to avoid an unneeded transfer.
            data = abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)",
                msg.sender,
                to,
                tokenId
            );
        }

        (bool success, bytes memory resultData) = address(assetAddr).call(data);
        require(success, string(resultData));
    }

    /**
     * @notice Approves our ERC721 tokens to be transferred.
     *
     * @dev This is only required to provide special logic for Cryptopunks.
     *
     * @param assetAddr Address of the asset being transferred
     * @param tokenId The ID of the token being transferred
     * @param to The address the token is being transferred to
     */
    function _approveERC721(
        address assetAddr,
        uint256 tokenId,
        address to
    ) internal virtual {
        if (assetAddr != CRYPTO_PUNKS) {
            return;
        }

        bytes memory data = abi.encodeWithSignature(
            "offerPunkForSaleToAddress(uint256,uint256,address)",
            tokenId,
            0,
            to
        );
        (bool success, bytes memory resultData) = address(assetAddr).call(data);
        require(success, string(resultData));
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
        INFTXVault vToken,
        uint256 nftCount
    ) internal view returns (uint256) {
        return vToken.vTokenToETH(vToken.mintFee() * nftCount);
    }

    function _ethSwapFees(
        INFTXVault vToken,
        uint256[] memory nftIds
    ) internal view returns (uint256) {
        return
            vToken.vTokenToETH(
                (vToken.targetSwapFee() * nftIds.length) +
                    _getVTokenPremium(vToken, nftIds)
            );
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

    function _getVTokenPremium(
        INFTXVault vToken,
        uint256[] memory nftIds
    ) internal view returns (uint256 vTokenPremium) {
        for (uint256 i; i < nftIds.length; ) {
            vTokenPremium += vToken.getVTokenPremium(nftIds[i]);

            unchecked {
                ++i;
            }
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
                WETH.deposit{value: ethAmount}();
            }
            WETH.transfer(address(feeDistributor), ethAmount);
            feeDistributor.distribute(vaultId);
        }
    }

    function _deductRoyalty(
        address nft,
        uint256[] memory idsIn,
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
