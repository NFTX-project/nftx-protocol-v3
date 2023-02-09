// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockNFT is ERC721 {
    uint256 public nextTokenId;

    constructor() ERC721("MOCK", "MOCK") {}

    function mint(uint256 count) external returns (uint256[] memory tokenIds) {
        uint256 _nextTokenId = nextTokenId;

        tokenIds = new uint256[](count);
        for (uint256 i; i < count; i++) {
            uint256 tokenId = _nextTokenId++;
            tokenIds[i] = tokenId;
            _mint(msg.sender, tokenId);
        }

        nextTokenId = _nextTokenId;
    }
}
