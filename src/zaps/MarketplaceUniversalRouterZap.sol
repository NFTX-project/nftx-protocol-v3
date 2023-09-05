contract MarketplaceUniversalRouterZap is Ownable, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;
    IWETH9 public immutable WETH;
    IPermitAllowanceTransfer public immutable PERMIT2;
    INFTXVaultFactoryV3 public immutable nftxVaultFactory;
    address public immutable inventoryStaking;
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    uint256 constant BASE = 10 ** 18;
    address public universalRouter;
    bool public paused = false;
    uint256 public dustThreshold;
    event Sell(uint256 vaultId, uint256 count, uint256 ethReceived, address to, uint256 netRoyaltyAmount, uint256 wethFees);
    event Swap(uint256 vaultId, uint256[] idsIn, uint256[] idsOut, uint256 ethSpent, address to);
    event Swap(uint256 vaultId, uint256[] idsIn, uint256[] amounts, uint256[] idsOut, uint256 ethSpent, address to);
    event Buy(uint256 vaultId, uint256[] nftIds, uint256 ethSpent, address to, uint256 netRoyaltyAmount);
    event DustReturned(uint256 ethAmount, uint256 vTokenAmount, address to);
    event Paused(bool status);
    event NewUniversalRouter(address universalRouter);
    event NewDustThreshold(uint256 dustThreshold);
    error ZapPaused();
    error SwapFailed();
    error UnableToSendETH();
    error InsufficientWethForVaultFees();
    error WrongVaultType();
    error NotEnoughFundsForRedeem();
    error ZeroAddress();
    constructor(INFTXVaultFactoryV3 nftxVaultFactory_, address universalRouter_, IPermitAllowanceTransfer PERMIT2_, address inventoryStaking_, IWETH9 WETH_) {
        nftxVaultFactory = nftxVaultFactory_;
        universalRouter = universalRouter_;
        PERMIT2 = PERMIT2_;
        inventoryStaking = inventoryStaking_;
        WETH = WETH_;
    }
    function sell721(uint256 vaultId, uint256[] calldata idsIn, bytes calldata executeCallData, address payable to, bool deductRoyalty) external onlyOwnerIfPaused {
        (address vault, address assetAddress) = _mint721(vaultId, idsIn);
        (uint256 wethAmount, ) = _swapTokens(vault, address(WETH), executeCallData);
        uint256 wethFees = _ethMintFees(INFTXVaultV3(vault), idsIn.length);
        if (wethFees < wethAmount) revert InsufficientWethForVaultFees();
        _distributeVaultFees(vaultId, wethFees, true);
        uint256 netRoyaltyAmount;
        if (deductRoyalty) {
            netRoyaltyAmount = _deductRoyalty(assetAddress, idsIn, wethAmount);
        }
        wethAmount -= (wethFees + netRoyaltyAmount);
        _wethToETHResidue(to, wethAmount);
        emit Sell(vaultId, idsIn.length, wethAmount, to, netRoyaltyAmount, wethFees);
    }
    function swap721(uint256 vaultId, uint256[] calldata idsIn, uint256[] calldata idsOut, uint256 vTokenPremiumLimit, address payable to) external payable onlyOwnerIfPaused {
        (address vault, ) = _transferSender721ToVault(vaultId, idsIn);
        uint256[] memory emptyAmounts;
        uint256 ethFees = INFTXVaultV3(vault).swap{value: msg.value}(idsIn, emptyAmounts, idsOut, msg.sender, to, vTokenPremiumLimit, true);
        _sendETHResidue(to);
        emit Swap(vaultId, idsIn, idsOut, ethFees, to);
    }
    function buyNFTsWithETH(uint256 vaultId, uint256[] calldata idsOut, bytes calldata executeCallData, address payable to, uint256 vTokenPremiumLimit, bool deductRoyalty) external payable onlyOwnerIfPaused {
        WETH.deposit{value: msg.value}();
        address vault = nftxVaultFactory.vault(vaultId);
        uint256 wethSpent;
        uint256 vTokenAmount;
        {
            uint256 iniWETHBal = WETH.balanceOf(address(this));
            (vTokenAmount, ) = _swapTokens(
                address(WETH),
                vault,
                executeCallData
            );
            if (vTokenAmount < idsOut.length * BASE)
                revert NotEnoughFundsForRedeem();
            wethSpent = iniWETHBal - WETH.balanceOf(address(this));
        }
        uint256 wethLeft = msg.value - wethSpent;
        TransferLib.unSafeMaxApprove(address(WETH), vault, wethLeft);
        uint256 wethFees = INFTXVaultV3(vault).redeem(idsOut, to, wethLeft, vTokenPremiumLimit, true);
        wethSpent = (wethSpent * idsOut.length * BASE) / vTokenAmount;
        uint256 netRoyaltyAmount;
        if (deductRoyalty) {
            address assetAddress = INFTXVaultV3(vault).assetAddress();
            netRoyaltyAmount = _deductRoyalty(assetAddress, idsOut, wethSpent);
        }
        _transferDust(vault, true);
        emit Buy(vaultId, idsOut, wethSpent + wethFees + netRoyaltyAmount, to, netRoyaltyAmount);
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
    function buyNFTsWithERC20(BuyNFTsWithERC20Params calldata params) external onlyOwnerIfPaused {
        params.tokenIn.safeTransferFrom(msg.sender, address(this), params.amountIn);
        return _buyNFTsWithERC20(params);
    }
    function buyNFTsWithERC20WithPermit2(BuyNFTsWithERC20Params calldata params, bytes calldata encodedPermit2) external onlyOwnerIfPaused {
        if (encodedPermit2.length > 0) {
            (address owner, IPermitAllowanceTransfer.PermitSingle memory permitSingle, bytes memory signature) = abi.decode(encodedPermit2, (address, IPermitAllowanceTransfer.PermitSingle, bytes));
            PERMIT2.permit(owner, permitSingle, signature);
        }
        PERMIT2.transferFrom(msg.sender, address(this), SafeCast.toUint160(params.amountIn), address(params.tokenIn));
        return _buyNFTsWithERC20(params);
    }
    function sell1155(uint256 vaultId, uint256[] calldata idsIn, uint256[] calldata amounts, bytes calldata executeCallData, address payable to, bool deductRoyalty) external onlyOwnerIfPaused {
        (address vault, address assetAddress) = _mint1155(vaultId, idsIn, amounts);
        uint256 totalAmount = _validate1155Ids(idsIn, amounts);
        (uint256 wethAmount, ) = _swapTokens(vault, address(WETH), executeCallData);
        uint256 wethFees = _ethMintFees(INFTXVaultV3(vault), totalAmount);
        if (wethFees < wethAmount) revert InsufficientWethForVaultFees();
        _distributeVaultFees(vaultId, wethFees, true);
        uint256 netRoyaltyAmount;
        if (deductRoyalty) {
            netRoyaltyAmount = _deductRoyalty1155(assetAddress, idsIn, amounts, totalAmount, wethAmount);
        }
        wethAmount -= (wethFees + netRoyaltyAmount); // if underflow, then revert desired
        _wethToETHResidue(to, wethAmount);
        emit Sell(vaultId, totalAmount, wethAmount, to, netRoyaltyAmount, wethFees);
    }
    function swap1155(uint256 vaultId, uint256[] calldata idsIn, uint256[] calldata amounts, uint256[] calldata idsOut, uint256 vTokenPremiumLimit, address payable to) external payable onlyOwnerIfPaused {
        address vault = nftxVaultFactory.vault(vaultId);
        if (!INFTXVaultV3(vault).is1155()) revert WrongVaultType();
        address assetAddress = INFTXVaultV3(vault).assetAddress();
        IERC1155(assetAddress).safeBatchTransferFrom(msg.sender, address(this), idsIn, amounts, "");
        IERC1155(assetAddress).setApprovalForAll(vault, true);
        uint256 ethFees = INFTXVaultV3(vault).swap{value: msg.value}(idsIn, amounts, idsOut, msg.sender, to, vTokenPremiumLimit, true);
        _sendETHResidue(to);
        emit Swap(vaultId, idsIn, amounts, idsOut, ethFees, to);
    }
    modifier onlyOwnerIfPaused() {
        if (paused && msg.sender != owner()) revert ZapPaused();
        _;
    }
    function pause(bool paused_) external onlyOwner {
        paused = paused_;
        emit Paused(paused_);
    }
    function setUniversalRouter(address universalRouter_) external onlyOwner {
        universalRouter = universalRouter_;
        emit NewUniversalRouter(universalRouter_);
    }
    function setDustThreshold(uint256 dustThreshold_) external onlyOwner {
        dustThreshold = dustThreshold_;
        emit NewDustThreshold(dustThreshold_);
    }
    function _buyNFTsWithERC20(BuyNFTsWithERC20Params calldata params) internal {
        _swapTokens(address(params.tokenIn), address(WETH),params.executeToWETHCallData);
        uint256 iniWETHBal = WETH.balanceOf(address(this));
        address vault = nftxVaultFactory.vault(params.vaultId);
        _swapTokens(address(WETH), vault, params.executeToVTokenCallData);
        uint256 wethLeft = WETH.balanceOf(address(this));
        uint256 wethSpent = iniWETHBal - wethLeft;
        TransferLib.unSafeMaxApprove(address(WETH), vault, wethLeft);
        uint256 wethFees = INFTXVaultV3(vault).redeem(params.idsOut, params.to, wethLeft, params.vTokenPremiumLimit, true);
        uint256 netRoyaltyAmount;
        if (params.deductRoyalty) {
            address assetAddress = INFTXVaultV3(vault).assetAddress();
            netRoyaltyAmount = _deductRoyalty(assetAddress, params.idsOut, wethSpent);
        }
        _transferDust(vault, true);

        emit Buy(params.vaultId, params.idsOut, wethSpent + wethFees + netRoyaltyAmount, params.to, netRoyaltyAmount);
    }
    function _mint721(uint256 vaultId, uint256[] calldata ids) internal returns (address vault, address assetAddress) {
        (vault, assetAddress) = _transferSender721ToVault(vaultId, ids);
        uint256[] memory emptyAmounts;
        INFTXVaultV3(vault).mint(ids, emptyAmounts, msg.sender, address(this));
    }
    function _mint1155(uint256 vaultId, uint256[] calldata ids, uint256[] calldata amounts) internal returns (address vault, address assetAddress) {
        vault = nftxVaultFactory.vault(vaultId);
        if (!INFTXVaultV3(vault).is1155()) revert WrongVaultType();
        assetAddress = INFTXVaultV3(vault).assetAddress();
        IERC1155(assetAddress).safeBatchTransferFrom(msg.sender, address(this), ids, amounts, "");
        IERC1155(assetAddress).setApprovalForAll(vault, true);
        INFTXVaultV3(vault).mint(ids, amounts, msg.sender, address(this));
    }
    function _validate1155Ids(uint256[] calldata ids, uint256[] calldata amounts) internal pure returns (uint256 totalAmount) {
        for (uint i; i < ids.length; ) {
            unchecked {
                totalAmount += amounts[i];
                ++i;
            }
        }
    }
    function _transferSender721ToVault(uint256 vaultId, uint256[] calldata ids) internal returns (address vault, address assetAddress) {
        vault = nftxVaultFactory.vault(vaultId);
        assetAddress = INFTXVaultV3(vault).assetAddress();
        TransferLib.transferFromERC721(assetAddress, address(vault), ids);
    }
    function _swapTokens(address sellToken, address buyToken, bytes calldata executeCallData) internal returns (uint256 boughtAmount, uint256 finalBuyTokenBalance) {
        uint256 iniBuyTokenBalance = IERC20(buyToken).balanceOf(address(this));
        _permit2ApproveToken(sellToken, address(universalRouter));
        (bool success, ) = address(universalRouter).call(executeCallData);
        if (!success) revert SwapFailed();
        finalBuyTokenBalance = IERC20(buyToken).balanceOf(address(this));
        boughtAmount = finalBuyTokenBalance - iniBuyTokenBalance;
    }
    function _permit2ApproveToken(address token, address spender) internal {
        (uint160 permitAllowance, , ) = PERMIT2.allowance(address(this), token, spender);
        if (permitAllowance >= uint160(0xf000000000000000000000000000000000000000)) return;
        IERC20(token).safeApprove(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(token, spender, type(uint160).max, type(uint48).max);
    }
    function _ethMintFees(INFTXVaultV3 vToken, uint256 nftCount) internal view returns (uint256) {
        (uint256 mintFee, , ) = vToken.vaultFees();
        return vToken.vTokenToETH(mintFee * nftCount);
    }
    function _distributeVaultFees(uint256 vaultId, uint256 ethAmount, bool isWeth) internal {
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
    function _deductRoyalty(address nft, uint256[] calldata idsIn, uint256 netWethAmount) internal returns (uint256 netRoyaltyAmount) {
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
    function _deductRoyalty1155(address nft, uint256[] calldata idsIn, uint256[] calldata amounts, uint256 totalAmount, uint256 netWethAmount) internal returns (uint256 netRoyaltyAmount) {
        bool success = IERC2981(nft).supportsInterface(_INTERFACE_ID_ERC2981);
        if (success) {
            uint256 salePrice = netWethAmount / totalAmount;
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
    function _allWethToETHResidue(address to) internal returns (uint256 wethAmount) {
        wethAmount = WETH.balanceOf(address(this));
        _wethToETHResidue(to, wethAmount);
    }
    function _wethToETHResidue(address to, uint256 wethAmount) internal {
        if (wethAmount > 0) {
            WETH.withdraw(wethAmount);
        }
        _sendETHResidue(to);
    }
    function _sendETHResidue(address to) internal {
        if (to == address(0)) revert ZeroAddress();
        (bool success, ) = payable(to).call{value: address(this).balance}("");
        if (!success) revert UnableToSendETH();
    }
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
