// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library TransferLib {
    using SafeERC20 for IERC20;

    address internal constant CRYPTO_PUNKS =
        0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;

    error UnableToSendETH();

    function transferFromERC721(
        address assetAddress,
        address to,
        uint256[] memory nftIds
    ) internal {
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

    /// @dev Setting max allowance to save gas on subsequent calls.
    function maxApprove(
        address token,
        address spender,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);

        if (amount > allowance) {
            IERC20(token).safeApprove(spender, type(uint256).max);
        }
    }

    function transferETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert UnableToSendETH();
    }

    /**
     * @notice Transfers sender's ERC721 tokens to a specified recipient.
     *
     * @param assetAddr Address of the asset being transferred
     * @param tokenId The ID of the token being transferred
     * @param to The address the token is being transferred to
     */

    function _transferFromERC721(
        address assetAddr,
        uint256 tokenId,
        address to
    ) private {
        bytes memory data;

        if (assetAddr != CRYPTO_PUNKS) {
            // We push to the vault to avoid an unneeded transfer.
            data = abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)",
                msg.sender,
                to,
                tokenId
            );
        } else {
            // Fix here for frontrun attack.
            bytes memory punkIndexToAddress = abi.encodeWithSignature(
                "punkIndexToAddress(uint256)",
                tokenId
            );
            (bool checkSuccess, bytes memory result) = CRYPTO_PUNKS.staticcall(
                punkIndexToAddress
            );
            address nftOwner = abi.decode(result, (address));
            require(
                checkSuccess && nftOwner == msg.sender,
                "Not the NFT owner"
            );
            data = abi.encodeWithSignature("buyPunk(uint256)", tokenId);
        }

        (bool success, bytes memory resultData) = address(assetAddr).call(data);
        require(success, string(resultData));
    }

    /**
     * @notice Approves our Cryptopunk ERC721 tokens to be transferred.
     *
     * @dev This is only required to provide special logic for Cryptopunks.
     *
     * @param tokenId The ID of the token being transferred
     * @param to The address the token is being transferred to
     */

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
