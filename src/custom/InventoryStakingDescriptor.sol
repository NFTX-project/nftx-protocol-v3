// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {Base64} from "base64-sol/base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {HexStrings} from "@uni-periphery/libraries/HexStrings.sol";

contract InventoryStakingDescriptor {
    using Strings for uint256;
    using HexStrings for uint256;

    // =============================================================
    //                        CONSTANTS
    // =============================================================

    string internal constant PREFIX = "x";

    // =============================================================
    //                        INTERNAL
    // =============================================================

    function renderSVG(
        uint256 tokenId,
        uint256 vaultId,
        address vToken,
        string calldata vTokenSymbol,
        uint256 vTokenBalance,
        uint256 wethBalance,
        uint256 timelockLeft
    ) public pure returns (string memory) {
        return
            string.concat(
                '<svg width="290" height="500" viewBox="0 0 290 500" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">',
                getDefs(
                    tokenToColorHex(uint256(uint160(vToken)), 136),
                    tokenToColorHex(uint256(uint160(vToken)), 100)
                ),
                '<g mask="url(#fade-symbol)">',
                text("32", "70", "200", "32"),
                PREFIX,
                vTokenSymbol,
                "</text>",
                underlyingBalances(vTokenSymbol, vTokenBalance, wethBalance),
                '<rect x="16" y="16" width="258" height="468" rx="26" ry="26" fill="rgba(0,0,0,0)" stroke="rgba(255,255,255,0.2)"/>',
                infoTags(tokenId, vaultId, timelockLeft),
                "</svg>"
            );
    }

    function tokenURI(
        uint256 tokenId,
        uint256 vaultId,
        address vToken,
        string calldata vTokenSymbol,
        uint256 vTokenBalance,
        uint256 wethBalance,
        uint256 timelockedUntil
    ) external view returns (string memory) {
        string memory image = Base64.encode(
            bytes(
                renderSVG(
                    tokenId,
                    vaultId,
                    vToken,
                    vTokenSymbol,
                    vTokenBalance,
                    wethBalance,
                    block.timestamp > timelockedUntil
                        ? 0
                        : timelockedUntil - block.timestamp
                )
            )
        );

        return
            string.concat(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        string.concat(
                            '{"name":"',
                            string.concat(
                                "x",
                                vTokenSymbol,
                                " #",
                                tokenId.toString()
                            ),
                            '", "description":"',
                            "xNFT representing inventory staking position on NFTX",
                            '", "image": "',
                            "data:image/svg+xml;base64,",
                            image,
                            '", "attributes": [{"trait_type": "VaultId", "value": "',
                            vaultId.toString(),
                            '"}]}'
                        )
                    )
                )
            );
    }

    // =============================================================
    //                        PRIVATE
    // =============================================================

    function getDefs(
        string memory color2,
        string memory color3
    ) private pure returns (string memory) {
        return
            string.concat(
                "<defs>",
                '<filter id="f1"><feImage result="p2" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        string.concat(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='16' cy='232' r='120px' fill='#",
                            color2,
                            "'/></svg>"
                        )
                    )
                ),
                '"/><feImage result="p3" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        string.concat(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='20' cy='100' r='130px' fill='#",
                            color3,
                            "'/></svg>"
                        )
                    )
                ),
                '"/><feBlend mode="exclusion" in2="p2"/><feBlend mode="overlay" in2="p3" result="blendOut"/><feGaussianBlur in="blendOut" stdDeviation="42"/></filter><clipPath id="corners"><rect width="290" height="500" rx="42" ry="42"/></clipPath><filter id="top-region-blur"><feGaussianBlur in="SourceGraphic" stdDeviation="24"/></filter><linearGradient id="grad-symbol"><stop offset="0.7" stop-color="white" stop-opacity="1"/><stop offset=".95" stop-color="white" stop-opacity="0"/></linearGradient><mask id="fade-symbol" maskContentUnits="userSpaceOnUse"><rect width="290px" height="200px" fill="url(#grad-symbol)"/></mask></defs>',
                '<g clip-path="url(#corners)"><rect fill="2c9715" x="0px" y="0px" width="290px" height="500px"/><rect style="filter: url(#f1)" x="0px" y="0px" width="290px" height="500px"/><g style="filter:url(#top-region-blur); transform:scale(1.5); transform-origin:center top;"><rect fill="none" x="0px" y="0px" width="290px" height="500px"/><ellipse cx="50%" cy="0px" rx="180px" ry="120px" fill="#000" opacity="0.85"/></g><rect x="0" y="0" width="290" height="500" rx="42" ry="42" fill="rgba(0,0,0,0)" stroke="rgba(255,255,255,0.2)"/></g>'
            );
    }

    function text(
        string memory x,
        string memory y,
        string memory fontWeight,
        string memory fontSize
    ) private pure returns (string memory) {
        return text(x, y, fontWeight, fontSize, false);
    }

    function text(
        string memory x,
        string memory y,
        string memory fontWeight,
        string memory fontSize,
        bool onlyMonospace
    ) private pure returns (string memory) {
        return
            string.concat(
                '<text y="',
                y,
                'px" x="',
                x,
                'px" fill="white" font-family="',
                !onlyMonospace ? "'Courier New', " : "",
                'monospace" font-weight="',
                fontWeight,
                '" font-size="',
                fontSize,
                'px">'
            );
    }

    function tokenToColorHex(
        uint256 token,
        uint256 offset
    ) private pure returns (string memory str) {
        return string((token >> offset).toHexStringNoPrefix(3));
    }

    function balanceTag(
        string memory y,
        uint256 tokenBalance,
        string memory tokenSymbol
    ) private pure returns (string memory) {
        uint256 beforeDecimal = tokenBalance / 1 ether;
        string memory afterDecimals = getAfterDecimals(tokenBalance);

        uint256 leftPadding = 12;
        uint256 beforeDecimalFontSize = 20;
        uint256 afterDecimalFontSize = 16;

        uint256 width = leftPadding +
            ((getDigitsCount(beforeDecimal) + 1) * beforeDecimalFontSize) /
            2 +
            (bytes(afterDecimals).length * afterDecimalFontSize * 100) /
            100;

        return
            string.concat(
                '<g style="transform:translate(29px, ',
                y,
                'px)"><rect width="',
                width.toString(),
                'px" height="30px" rx="8px" ry="8px" fill="rgba(0,0,0,0.6)"/>',
                text(
                    leftPadding.toString(),
                    "21",
                    "100",
                    beforeDecimalFontSize.toString(),
                    true
                ),
                beforeDecimal.toString(),
                '.<tspan font-size="',
                afterDecimalFontSize.toString(),
                'px">',
                afterDecimals,
                '</tspan> <tspan fill="rgba(255,255,255,0.8)">',
                tokenSymbol,
                "</tspan></text></g>"
            );
    }

    function infoTag(
        string memory y,
        string memory label,
        string memory value
    ) private pure returns (string memory) {
        return
            string.concat(
                '<g style="transform:translate(29px, ',
                y,
                'px)"><rect width="98px" height="26px" rx="8px" ry="8px" fill="rgba(0,0,0,0.6)"/>',
                text("12", "17", "100", "12"),
                '<tspan fill="rgba(255,255,255,0.6)">',
                label,
                ": </tspan>",
                value,
                "</text></g>"
            );
    }

    function underlyingBalances(
        string memory vTokenSymbol,
        uint256 vTokenBalance,
        uint256 wethBalance
    ) private pure returns (string memory) {
        return
            string.concat(
                text("32", "160", "200", "16"),
                "Underlying Balance</text></g>",
                balanceTag("180", vTokenBalance, vTokenSymbol),
                balanceTag("220", wethBalance, "WETH")
            );
    }

    function infoTags(
        uint256 tokenId,
        uint256 vaultId,
        uint256 timelockLeft
    ) private pure returns (string memory) {
        return
            string.concat(
                infoTag("384", "ID", tokenId.toString()),
                infoTag("414", "VaultId", vaultId.toString()),
                infoTag(
                    "444",
                    "Timelock",
                    timelockLeft > 0
                        ? string.concat(timelockLeft.toString(), "s left")
                        : "Unlocked"
                )
            );
    }

    function getDigitsCount(uint256 num) private pure returns (uint256 count) {
        if (num == 0) return 1;

        while (num > 0) {
            ++count;
            num /= 10;
        }
    }

    function getAfterDecimals(
        uint256 tokenBalance
    ) private pure returns (string memory afterDecimals) {
        uint256 afterDecimal = (tokenBalance % 1 ether) / 10 ** (18 - 10); // show 10 decimals

        uint256 leadingZeroes;
        if (afterDecimal == 0) {
            leadingZeroes = 0;
        } else {
            leadingZeroes = 10 - getDigitsCount(afterDecimal);
        }

        afterDecimals = afterDecimal.toString();
        for (uint256 i; i < leadingZeroes; ) {
            afterDecimals = string.concat("0", afterDecimals);

            unchecked {
                ++i;
            }
        }
    }
}
