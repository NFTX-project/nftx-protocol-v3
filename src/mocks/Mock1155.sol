// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract Mock1155 is ERC1155 {
    uint256 public nextId = 1;

    constructor() ERC1155("") {}

    function mint(uint256 amount) external returns (uint256 tokenId) {
        tokenId = nextId;
        _mint(msg.sender, nextId++, amount, "");
    }

    function mint(uint256 tokenId, uint256 amount) external {
        _mint(msg.sender, tokenId, amount, "");
    }
}
