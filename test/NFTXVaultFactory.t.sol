// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {TestBase} from "@test/TestBase.sol";

contract NFTXVaultFactoryTests is TestBase {
    // NFTXVaultFactory#setTwapInterval

    function test_setTwapInterval_RevertsForNonOwner() external {
        uint32 newTwapInterval = 60 minutes;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setTwapInterval(newTwapInterval);
    }

    function test_setTwapInterval_Success() external {
        uint32 newTwapInterval = 60 minutes;

        uint32 preTwapInterval = vaultFactory.twapInterval();
        assertTrue(preTwapInterval != newTwapInterval);

        vaultFactory.setTwapInterval(newTwapInterval);
        assertEq(vaultFactory.twapInterval(), newTwapInterval);
    }

    // NFTXVaultFactory#setPremiumDuration

    function test_setPremiumDuration_RevertsForNonOwner() external {
        uint256 newPremiumDuration = 20 hours;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setPremiumDuration(newPremiumDuration);
    }

    function test_setPremiumDuration_Success() external {
        uint256 newPremiumDuration = 20 hours;

        uint256 prePremiumDuration = vaultFactory.premiumDuration();
        assertTrue(prePremiumDuration != newPremiumDuration);

        vaultFactory.setPremiumDuration(newPremiumDuration);
        assertEq(vaultFactory.premiumDuration(), newPremiumDuration);
    }

    // NFTXVaultFactory#setPremiumMax

    function test_setPremiumMax_RevertsForNonOwner() external {
        uint256 newPremiumMax = 10 ether;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setPremiumMax(newPremiumMax);
    }

    function test_setPremiumMax_Success() external {
        uint256 newPremiumMax = 10 ether;

        uint256 prePremiumMax = vaultFactory.premiumMax();
        assertTrue(prePremiumMax != newPremiumMax);

        vaultFactory.setPremiumMax(newPremiumMax);
        assertEq(vaultFactory.premiumMax(), newPremiumMax);
    }

    // NFTXVaultFactory#getVTokenPremium1155
    function test_getVTokenPremium1155_Success() external {
        uint256 qty = 1;

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        nft1155.setApprovalForAll(address(vtoken1155), true);

        vtoken1155.mint(tokenIds, amounts, address(this), address(this));

        (uint256 vTokenPremium, , ) = vaultFactory.getVTokenPremium1155(
            VAULT_ID_1155,
            tokenIds[0],
            qty
        );

        console.log("vTokenPremium: %s", vTokenPremium);
        assertGt(vTokenPremium, 0);
    }
}
