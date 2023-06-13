// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {Helpers} from "./lib/Helpers.sol";

import {INFTXVault} from "@src/v2/NFTXVaultUpgradeable.sol";

import {TestBase} from "./TestBase.sol";

contract NFTXVaultTests is TestBase {
    uint256 currentNFTPrice = 10 ether;

    // NFTXVault#mint

    function test_mint_Succcess() external {
        _mintPositionWithTwap(currentNFTPrice);
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

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken));

            (uint48 timestamp, address depositor) = vtoken.tokenDepositInfo(
                tokenIds[i]
            );
            assertEq(depositor, address(this));
            assertEq(timestamp, block.timestamp);
        }
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

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken));
        }
    }

    // NFTXVault#redeem

    function test_redeem_NoPremium_Success() external {
        _mintPositionWithTwap(currentNFTPrice);
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

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(this));
        }
    }

    function test_redeem_WithPremium_Success() external {
        _mintPositionWithTwap(currentNFTPrice);
        uint256 qty = 5;

        // have a separate depositor address that receives share of premium
        address depositor = makeAddr("depositor");
        startHoax(depositor);
        (uint256 mintedVTokens, uint256[] memory tokenIds) = _mintVToken(qty);
        vtoken.transfer(address(this), mintedVTokens);
        vm.stopPrank();

        uint256 exactETHPaid = ((vtoken.targetRedeemFee() +
            vaultFactory.premiumMax()) *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);
        uint256 expectedDepositorShare = (exactETHPaid *
            vaultFactory.depositorPremiumShare()) / 1 ether;

        uint256 prevETHBal = address(this).balance;
        uint256 prevDepositorBal = weth.balanceOf(depositor);

        // double ETH value here to check if refund working as well
        vtoken.redeem{value: expectedETHPaid * 2}(tokenIds);

        uint256 ethPaid = prevETHBal - address(this).balance;
        uint256 ethDepositorReceived = weth.balanceOf(depositor) -
            prevDepositorBal;
        console.log("ethPaid with Premium", ethPaid);
        console.log(
            "ethPremium share received by depositor",
            ethDepositorReceived
        );
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);
        assertGt(
            ethDepositorReceived,
            (_valueWithError(expectedDepositorShare) * 980) / 1000 // TODO: verify why higher precision loss here
        );
        assertLe(ethDepositorReceived, expectedDepositorShare);

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(this));
        }
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

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(this));
        }
    }

    // NFTXVault#swap

    function test_swap_NoPremium_Success() external {
        _mintPositionWithTwap(currentNFTPrice);
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

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken));
            assertEq(nft.ownerOf(specificIds[i]), address(this));
        }
    }

    function test_swap_WithPremium_Success() external {
        _mintPositionWithTwap(currentNFTPrice);
        uint256 qty = 5;

        // have a separate depositor address that receives share of premium
        address depositor = makeAddr("depositor");
        startHoax(depositor);
        (, uint256[] memory specificIds) = _mintVToken(qty);
        vm.stopPrank();

        uint256[] memory tokenIds = nft.mint(qty);
        uint256[] memory amounts = new uint256[](0);

        uint256 exactETHPaid = ((vtoken.targetSwapFee() +
            vaultFactory.premiumMax()) *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);
        uint256 expectedDepositorShare = (exactETHPaid *
            vaultFactory.depositorPremiumShare()) / 1 ether;

        uint256 prevETHBal = address(this).balance;
        uint256 prevDepositorBal = weth.balanceOf(depositor);

        nft.setApprovalForAll(address(vtoken), true);
        // double ETH value here to check if refund working as well
        vtoken.swap{value: expectedETHPaid * 2}(tokenIds, amounts, specificIds);

        uint256 ethPaid = prevETHBal - address(this).balance;
        uint256 ethDepositorReceived = weth.balanceOf(depositor) -
            prevDepositorBal;
        console.log("ethPaid With Premium", ethPaid);
        console.log(
            "ethPremium share received by depositor",
            ethDepositorReceived
        );
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);
        assertGt(
            ethDepositorReceived,
            (_valueWithError(expectedDepositorShare) * 980) / 1000 // TODO: verify why higher precision loss here
        );
        assertLe(ethDepositorReceived, expectedDepositorShare);

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken));
            assertEq(nft.ownerOf(specificIds[i]), address(this));
        }
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

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken));
            assertEq(nft.ownerOf(specificIds[i]), address(this));
        }
    }
}
