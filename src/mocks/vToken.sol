// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {LowGasSafeMath} from "@uni-core/libraries/LowGasSafeMath.sol";

/**
 * @notice wrap ERC721 into fungible ERC20
 */
contract vToken is ERC20, IERC721Receiver {
    using LowGasSafeMath for uint256;

    IERC721 public nft;

    constructor(IERC721 nft_) ERC20("vToken", "vToken") {
        nft = nft_;
    }

    /**
     * @param from address to transfer NFTs from
     * @param to address to receive newly minted ERC20
     * @param amount amount of ERC20 minted
     */
    function mint(
        uint256[] calldata nftIds,
        address from,
        address to
    ) external returns (uint256 amount) {
        uint256 count = nftIds.length;
        for (uint256 i; i < count; ++i) {
            nft.safeTransferFrom(from, address(this), nftIds[i]);
        }

        amount = count.mul(1 ether);
        _mint(to, amount);
    }

    /**
     * @param from address to burn their ERC20
     * @param to address to transfer NFTs to
     */
    function burn(
        uint256[] calldata nftIds,
        address from,
        address to
    ) external {
        uint256 count = nftIds.length;
        uint256 amount = count.mul(1 ether);
        // check if sender is approved to perform this burn
        require(
            msg.sender == from || allowance(from, msg.sender) >= amount,
            "Not Approved"
        );
        _burn(from, amount);

        for (uint256 i; i < count; ++i) {
            nft.safeTransferFrom(address(this), to, nftIds[i]);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
