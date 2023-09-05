library TransferLib {
    using SafeERC20 for IERC20;
    address internal constant CRYPTO_PUNKS = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
    address internal constant CRYPTO_KITTIES = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;
    error UnableToSendETH();
    error NotNFTOwner();
    function transferFromERC721(address assetAddress, address to, uint256[] memory nftIds) internal {
        for (uint256 i; i < nftIds.length; ) {
            _transferFromERC721(assetAddress, nftIds[i], to);
            if (assetAddress == CRYPTO_PUNKS) {
                _approveCryptoPunkERC721(nftIds[i], to);
            }
            unchecked {
                ++i;
            }
        }
    }
    function maxApprove(address token, address spender, uint256 amount) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (amount > allowance) {
            IERC20(token).safeApprove(spender, type(uint256).max);
        }
    }
    function unSafeMaxApprove(address token, address spender, uint256 amount) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (amount > allowance) {
            IERC20(token).approve(spender, type(uint256).max);
        }
    }
    function transferETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert UnableToSendETH();
    }
    function _transferFromERC721(address assetAddr, uint256 tokenId, address to) private {
        bytes memory data;
        if (assetAddr != CRYPTO_PUNKS && assetAddr != CRYPTO_KITTIES) {
            data = abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)",
                msg.sender,
                to,
                tokenId
            );
        } else if (assetAddr == CRYPTO_PUNKS) {
            bytes memory punkIndexToAddress = abi.encodeWithSignature(
                "punkIndexToAddress(uint256)",
                tokenId
            );
            (bool checkSuccess, bytes memory result) = CRYPTO_PUNKS.staticcall(
                punkIndexToAddress
            );
            address nftOwner = abi.decode(result, (address));
            if (!checkSuccess || nftOwner != msg.sender) revert NotNFTOwner();
            data = abi.encodeWithSignature("buyPunk(uint256)", tokenId);
        } else {
            data = abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender,
                address(this),
                tokenId
            );
        }
        (bool success, bytes memory resultData) = address(assetAddr).call(data);
        require(success, string(resultData));
    }
    function _approveCryptoPunkERC721(uint256 tokenId, address to) private {
        bytes memory data = abi.encodeWithSignature(
            "offerPunkForSaleToAddress(uint256,uint256,address)",
            tokenId,
            0,
            to
        );
        (bool success, bytes memory resultData) = CRYPTO_PUNKS.call(data);
        require(success, string(resultData));
    }
}
