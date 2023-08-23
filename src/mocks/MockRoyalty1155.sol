// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

contract MockRoyalty1155 is ERC1155, ERC2981 {
    uint256 public nextId = 1;

    constructor() ERC1155("") {
        _setDefaultRoyalty(msg.sender, 500);
    }

    function mint(uint256 amount) external returns (uint256 tokenId) {
        tokenId = nextId;
        _mint(msg.sender, nextId++, amount, "");
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
