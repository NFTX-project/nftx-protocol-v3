// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;
import {ERC721Royalty, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";

contract MockRoyaltyNFT is ERC721Royalty {
    uint256 public nextTokenId;

    constructor() ERC721("RoyaltyV2", "RV2") {
        _setDefaultRoyalty(msg.sender, 500);
    }

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
