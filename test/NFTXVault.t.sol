// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {Helpers} from "./lib/Helpers.sol";

import {TestBase} from "./TestBase.sol";

contract NFTXVaultTests is TestBase {
    uint256 currentNFTPrice = 10 ether;

    // NFTXVault#mint

    function test_mint_Succcess() external {
        _mintPositionWithTwap();
        uint256 qty = 5;

        uint256 exactETHPaid = (vtoken.mintFee() * qty * currentNFTPrice) /
            1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        uint256[] memory tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(vtoken), true);
        uint256[] memory amounts = new uint256[](0);

        // double ETH value here to check if refund working as well
        vtoken.mint{value: expectedETHPaid * 2}(tokenIds, amounts);

        uint256 ethPaid = prevETHBal - address(this).balance;
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);
    }

    function test_mint_WhenNoPoolExists_Success() external {
        uint256 qty = 5;

        uint256 exactETHPaid = (vtoken.mintFee() * qty * currentNFTPrice) /
            1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        uint256[] memory tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(vtoken), true);
        uint256[] memory amounts = new uint256[](0);

        // double ETH value here to check if refund working as well
        vtoken.mint{value: expectedETHPaid * 2}(tokenIds, amounts);

        uint256 ethPaid = prevETHBal - address(this).balance;
        assertEq(ethPaid, 0);
    }

    // NFTXVault#redeem

    function test_redeem_NoPremium_Success() external {
        _mintPositionWithTwap();
        uint256 qty = 5;
        (, uint256[] memory tokenIds) = _mintVToken(qty);
        // jump to time such that no premium applicable
        vm.warp(block.timestamp + vaultFactory.premiumDuration() + 1);

        uint256 exactETHPaid = (vtoken.targetRedeemFee() *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.redeem{value: expectedETHPaid * 2}(tokenIds);

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);
    }

    function test_redeem_WithPremium_Success() external {
        _mintPositionWithTwap();
        uint256 qty = 5;
        (, uint256[] memory tokenIds) = _mintVToken(qty);

        uint256 exactETHPaid = ((vtoken.targetRedeemFee() +
            vaultFactory.premiumMax()) *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.redeem{value: expectedETHPaid * 2}(tokenIds);

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);
    }

    function test_redeem_WithPremium_WhenNoPoolExists_Success() external {
        uint256 qty = 5;
        (, uint256[] memory tokenIds) = _mintVToken(qty);

        uint256 exactETHPaid = ((vtoken.targetRedeemFee() +
            vaultFactory.premiumMax()) *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.redeem{value: expectedETHPaid * 2}(tokenIds);

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with Premium", ethPaid);
        assertEq(ethPaid, 0);
    }

    // NFTXVault#swap

    function test_swap_NoPremium_Success() external {
        _mintPositionWithTwap();
        uint256 qty = 5;
        (, uint256[] memory specificIds) = _mintVToken(qty);
        // jump to time such that no premium applicable
        vm.warp(block.timestamp + vaultFactory.premiumDuration() + 1);

        uint256[] memory tokenIds = nft.mint(qty);
        uint256[] memory amounts = new uint256[](0);

        uint256 exactETHPaid = (vtoken.targetSwapFee() *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.swap{value: expectedETHPaid * 2}(tokenIds, amounts, specificIds);

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);
    }

    function test_swap_WithPremium_Success() external {
        _mintPositionWithTwap();
        uint256 qty = 5;
        (, uint256[] memory specificIds) = _mintVToken(qty);

        uint256[] memory tokenIds = nft.mint(qty);
        uint256[] memory amounts = new uint256[](0);

        uint256 exactETHPaid = ((vtoken.targetSwapFee() +
            vaultFactory.premiumMax()) *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.swap{value: expectedETHPaid * 2}(tokenIds, amounts, specificIds);

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);
    }

    function test_swap_WithPremium_WhenNoPoolExists_Success() external {
        uint256 qty = 5;
        (, uint256[] memory specificIds) = _mintVToken(qty);

        uint256[] memory tokenIds = nft.mint(qty);
        uint256[] memory amounts = new uint256[](0);

        uint256 exactETHPaid = ((vtoken.targetSwapFee() +
            vaultFactory.premiumMax()) *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.swap{value: expectedETHPaid * 2}(tokenIds, amounts, specificIds);

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertEq(ethPaid, 0);
    }

    // Helpers
    function _mintPositionWithTwap() internal {
        _mintPosition(
            1,
            currentNFTPrice,
            currentNFTPrice - 0.5 ether,
            currentNFTPrice + 0.5 ether,
            DEFAULT_FEE_TIER
        );
        vm.warp(block.timestamp + 1);
    }

    // the actual value can be off by few decimals so accounting for 0.1% error.
    function _valueWithError(uint256 value) internal pure returns (uint256) {
        return (value * (10_000 - 10)) / 10_000;
    }
}
