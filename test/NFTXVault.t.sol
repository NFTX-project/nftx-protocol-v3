// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {PausableUpgradeable} from "@src/custom/PausableUpgradeable.sol";

import {TestBase} from "@test/TestBase.sol";

contract NFTXVaultTests is TestBase {
    uint256 currentNFTPrice = 10 ether;

    // NFTXVault#mint

    function test_mint_RevertsForNonOwnerIfPaused() external {
        vaultFactory.setIsGuardian(address(this), true);
        vaultFactory.pause(1);

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        vtoken.mint{value: 0}(
            emptyIds,
            emptyAmounts,
            address(this),
            address(this)
        );
    }

    function test_mint_RevertsIfMintNotEnabled() external {
        vtoken.setVaultFeatures(
            false, // enableMint_
            true, // enableRedeem_
            true // enableSwap_
        );

        vm.expectRevert(INFTXVaultV3.MintingDisabled.selector);
        vtoken.mint{value: 0}(
            emptyIds,
            emptyAmounts,
            address(this),
            address(this)
        );
    }

    function test_mint_721_RevertsIfUsingTokenIdAlreadyInHoldings() external {
        uint256[] memory tokenIds = nft.mint(1);
        nft.setApprovalForAll(address(vtoken), true);
        vtoken.mint{value: 0}(
            tokenIds,
            emptyAmounts,
            address(this),
            address(this)
        );

        vm.expectRevert(INFTXVaultV3.NFTAlreadyOwned.selector);
        vtoken.mint{value: 0}(
            tokenIds,
            emptyAmounts,
            address(this),
            address(this)
        );
    }

    function test_mint_721_WhenNFTExternallyTransferred_Success() external {
        uint256 qty = 5;

        uint256[] memory tokenIds = nft.mint(qty);
        for (uint i; i < qty; i++) {
            nft.safeTransferFrom(address(this), address(vtoken), tokenIds[i]);
        }

        vtoken.mint{value: 0}(
            tokenIds,
            emptyAmounts,
            address(this),
            address(this)
        );

        assertEq(
            vtoken.balanceOf(address(this)),
            qty * 1 ether,
            "vTokens not received"
        );

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken), "!ownerOf");

            (uint48 timestamp, address depositor) = vtoken.tokenDepositInfo(
                tokenIds[i]
            );
            assertEq(depositor, address(this), "!depositor");
            assertEq(timestamp, block.timestamp, "!timestamp");
        }
    }

    function test_mint_721_WhenNoPoolExists_Success() external {
        uint256 qty = 5;
        (uint256 mintFee, , ) = vtoken.vaultFees();
        uint256 exactETHPaidIfPoolExisted = (mintFee * qty * currentNFTPrice) /
            1 ether;
        uint256 expectedETHPaidIfPoolExisted = _valueWithError(
            exactETHPaidIfPoolExisted
        );

        uint256 prevETHBal = address(this).balance;

        uint256[] memory tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(vtoken), true);

        // sending ETH to check if all is refunded back
        vtoken.mint{value: expectedETHPaidIfPoolExisted}(
            tokenIds,
            emptyAmounts,
            address(this),
            address(this)
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        assertEq(ethPaid, 0, "ETH Fees deducted");
        assertEq(vtoken.balanceOf(address(this)), qty * 1 ether, "!vTokens");

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken), "!ownerOf");

            (uint48 timestamp, address depositor) = vtoken.tokenDepositInfo(
                tokenIds[i]
            );
            assertEq(depositor, address(this), "!depositor");
            assertEq(timestamp, block.timestamp, "!timestamp");
        }
    }

    function test_mint_721_RevertsWhenLessETHSent() external {
        _mintPositionWithTwap(currentNFTPrice);
        uint256 qty = 5;

        uint256[] memory tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(vtoken), true);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert(INFTXVaultV3.InsufficientETHSent.selector);
        vtoken.mint{value: 0}(tokenIds, amounts, address(this), address(this));
    }

    function test_mint_721_WhenPoolExists_Succcess() external {
        _mintPositionWithTwap(currentNFTPrice);
        uint256 qty = 5;
        (uint256 mintFee, , ) = vtoken.vaultFees();

        uint256 exactETHPaid = (mintFee * qty * currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        uint256[] memory tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(vtoken), true);
        uint256[] memory amounts = new uint256[](0);

        // double ETH value here to check if refund working as well
        vtoken.mint{value: expectedETHPaid * 2}(
            tokenIds,
            amounts,
            address(this),
            address(this)
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken), "!ownerOf");

            (uint48 timestamp, address depositor) = vtoken.tokenDepositInfo(
                tokenIds[i]
            );
            assertEq(depositor, address(this), "!depositor");
            assertEq(timestamp, block.timestamp, "!timestamp");
        }
    }

    // 1155

    function test_mint_1155_RevertsForZeroAmount() external {
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = nft1155.mint(5);
        amounts[0] = 0;

        nft1155.setApprovalForAll(address(vtoken1155), true);

        vm.expectRevert(INFTXVaultV3.TransferAmountIsZero.selector);
        vtoken1155.mint{value: 0}(
            tokenIds,
            amounts,
            address(this),
            address(this)
        );
    }

    function test_mint_1155_WhenPoolExists_Succcess() external {
        _mintPositionWithTwap1155(currentNFTPrice);
        uint256 qty = 5;
        (uint256 mintFee, , ) = vtoken.vaultFees();
        uint256 exactETHPaid = (mintFee * qty * currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        nft1155.setApprovalForAll(address(vtoken1155), true);

        uint256 preDepositLength = vtoken1155.depositInfo1155Length(
            tokenIds[0]
        );
        uint256 prevNFTBal = nft1155.balanceOf(
            address(vtoken1155),
            tokenIds[0]
        );

        // double ETH value here to check if refund working as well
        vtoken1155.mint{value: expectedETHPaid * 2}(
            tokenIds,
            amounts,
            address(this),
            address(this)
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        assertEq(
            nft1155.balanceOf(address(vtoken1155), tokenIds[0]) - prevNFTBal,
            amounts[0]
        );

        assertEq(
            vtoken1155.depositInfo1155Length(tokenIds[0]),
            preDepositLength + 1
        );

        (uint256 _qty, address depositor, uint48 timestamp) = vtoken1155
            .depositInfo1155(
                tokenIds[0],
                vtoken1155.pointerIndex1155(tokenIds[0])
            );
        assertEq(_qty, qty);
        assertEq(depositor, address(this));
        assertEq(timestamp, block.timestamp);
    }

    // NFTXVault#redeem

    function test_redeem_721_NoPremium_Success() external {
        _mintPositionWithTwap(currentNFTPrice);
        uint256 qty = 5;
        (, uint256[] memory tokenIds) = _mintVToken(qty);
        // jump to time such that no premium applicable
        vm.warp(block.timestamp + vaultFactory.premiumDuration() + 1);

        (, uint256 redeemFee, ) = vtoken.vaultFees();
        uint256 exactETHPaid = (redeemFee * qty * currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.redeem{value: expectedETHPaid * 2}(
            tokenIds,
            address(this),
            0,
            MAX_VTOKEN_PREMIUM_LIMIT,
            false
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(this));
        }
    }

    function test_redeem_721_WithPremium_Success() external {
        _mintPositionWithTwap(currentNFTPrice);
        uint256 qty = 5;

        // have a separate depositor address that receives share of premium
        address depositor = makeAddr("depositor");
        startHoax(depositor);
        (uint256 mintedVTokens, uint256[] memory tokenIds) = _mintVToken(
            qty,
            depositor,
            depositor
        );
        vtoken.transfer(address(this), mintedVTokens);
        vm.stopPrank();

        (, uint256 redeemFee, ) = vtoken.vaultFees();
        uint256 exactETHPaid = ((redeemFee + vaultFactory.premiumMax()) *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);
        uint256 expectedDepositorShare = (exactETHPaid *
            vaultFactory.depositorPremiumShare()) / 1 ether;

        uint256 prevETHBal = address(this).balance;
        uint256 prevDepositorBal = weth.balanceOf(depositor);

        // double ETH value here to check if refund working as well
        vtoken.redeem{value: expectedETHPaid * 2}(
            tokenIds,
            address(this),
            0,
            MAX_VTOKEN_PREMIUM_LIMIT,
            false
        );

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

    function test_redeem_721_WithPremium_WhenNoPoolExists_Success() external {
        uint256 qty = 5;
        (, uint256[] memory tokenIds) = _mintVToken(qty);

        (, uint256 redeemFee, ) = vtoken.vaultFees();
        uint256 exactETHPaid = ((redeemFee + vaultFactory.premiumMax()) *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.redeem{value: expectedETHPaid * 2}(
            tokenIds,
            address(this),
            0,
            MAX_VTOKEN_PREMIUM_LIMIT,
            false
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with Premium", ethPaid);
        assertEq(ethPaid, 0);

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(this));
        }
    }

    // 1155

    function test_redeem_1155_NoPremium_Success_pointerIndexUpdates() external {
        _mintPositionWithTwap1155(currentNFTPrice);
        uint256 qty = 5;
        (, uint256[] memory tokenIds) = _mintVTokenFor1155(qty);

        // jump to time such that no premium applicable
        vm.warp(block.timestamp + vaultFactory.premiumDuration() + 1);

        (, uint256 redeemFee, ) = vtoken1155.vaultFees();
        uint256 exactETHPaid = (redeemFee * qty * currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;
        uint256 prevNFTBal = nft1155.balanceOf(
            address(vtoken1155),
            tokenIds[0]
        );
        uint256 prevPointerIndex = vtoken1155.pointerIndex1155(tokenIds[0]);

        // double ETH value here to check if refund working as well
        vtoken1155.redeem{value: expectedETHPaid * 2}(
            tokenIds,
            address(this),
            0,
            MAX_VTOKEN_PREMIUM_LIMIT,
            false
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        assertEq(
            prevNFTBal - nft1155.balanceOf(address(vtoken1155), tokenIds[0]),
            qty
        );
        assertEq(
            vtoken1155.pointerIndex1155(tokenIds[0]) - prevPointerIndex,
            1
        );
    }

    struct RedeemData {
        uint256 qty;
        address depositor;
        uint256 mintedVTokens;
        uint256[] _tokenIds;
        uint256[] tokenIds;
        uint256 redeemFee;
    }
    RedeemData rd;

    function test_redeem_1155_WithPremium_Success_samePointerIndex() external {
        _mintPositionWithTwap1155(currentNFTPrice);
        rd.qty = 5;

        // have a separate depositor address that receives share of premium
        rd.depositor = makeAddr("depositor");
        startHoax(rd.depositor);
        (rd.mintedVTokens, rd._tokenIds) = _mintVTokenFor1155(
            rd.qty,
            rd.depositor,
            rd.depositor
        );

        vtoken1155.transfer(address(this), rd.mintedVTokens);
        vm.stopPrank();

        // decreasing tokenIds length for withdrawal so that same pointerIndex remains
        rd.qty -= 1;
        rd.tokenIds = new uint256[](rd.qty);
        for (uint256 i; i < rd.qty; i++) {
            rd.tokenIds[i] = rd._tokenIds[i];
        }

        (, rd.redeemFee, ) = vtoken1155.vaultFees();
        uint256 exactETHPaid = ((rd.redeemFee + vaultFactory.premiumMax()) *
            rd.qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);
        uint256 expectedDepositorShare = (exactETHPaid *
            vaultFactory.depositorPremiumShare()) / 1 ether;

        uint256 prevETHBal = address(this).balance;
        uint256 prevDepositorBal = weth.balanceOf(rd.depositor);
        uint256 prevNFTBal = nft1155.balanceOf(
            address(vtoken1155),
            rd.tokenIds[0]
        );
        uint256 prevPointerIndex = vtoken1155.pointerIndex1155(rd.tokenIds[0]);

        // double ETH value here to check if refund working as well
        vtoken1155.redeem{value: expectedETHPaid * 2}(
            rd.tokenIds,
            address(this),
            0,
            MAX_VTOKEN_PREMIUM_LIMIT,
            false
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        uint256 ethDepositorReceived = weth.balanceOf(rd.depositor) -
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

        assertEq(
            prevNFTBal - nft1155.balanceOf(address(vtoken1155), rd.tokenIds[0]),
            rd.qty
        );
        assertEq(vtoken1155.pointerIndex1155(rd.tokenIds[0]), prevPointerIndex);
    }

    // NFTXVault#swap

    function test_swap_721_NoPremium_Success() external {
        _mintPositionWithTwap(currentNFTPrice);
        uint256 qty = 5;
        (, uint256[] memory specificIds) = _mintVToken(qty);
        // jump to time such that no premium applicable
        vm.warp(block.timestamp + vaultFactory.premiumDuration() + 1);

        uint256[] memory tokenIds = nft.mint(qty);
        uint256[] memory amounts = new uint256[](0);

        (, , uint256 swapFee) = vtoken.vaultFees();
        uint256 exactETHPaid = (swapFee * qty * currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.swap{value: expectedETHPaid * 2}(
            tokenIds,
            amounts,
            specificIds,
            address(this),
            address(this),
            MAX_VTOKEN_PREMIUM_LIMIT,
            false
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken));
            assertEq(nft.ownerOf(specificIds[i]), address(this));
        }
    }

    function test_swap_721_WithPremium_Success() external {
        _mintPositionWithTwap(currentNFTPrice);
        uint256 qty = 5;

        // have a separate depositor address that receives share of premium
        address depositor = makeAddr("depositor");
        startHoax(depositor);
        (, uint256[] memory specificIds) = _mintVToken(
            qty,
            depositor,
            depositor
        );
        vm.stopPrank();

        uint256[] memory tokenIds = nft.mint(qty);
        uint256[] memory amounts = new uint256[](0);

        (, , uint256 swapFee) = vtoken.vaultFees();
        uint256 exactETHPaid = ((swapFee + vaultFactory.premiumMax()) *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);
        uint256 expectedDepositorShare = (exactETHPaid *
            vaultFactory.depositorPremiumShare()) / 1 ether;

        uint256 prevETHBal = address(this).balance;
        uint256 prevDepositorBal = weth.balanceOf(depositor);

        nft.setApprovalForAll(address(vtoken), true);
        // double ETH value here to check if refund working as well
        vtoken.swap{value: expectedETHPaid * 2}(
            tokenIds,
            amounts,
            specificIds,
            address(this),
            address(this),
            MAX_VTOKEN_PREMIUM_LIMIT,
            false
        );

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

    function test_swap_721_WithPremium_WhenNoPoolExists_Success() external {
        uint256 qty = 5;
        (, uint256[] memory specificIds) = _mintVToken(qty);

        uint256[] memory tokenIds = nft.mint(qty);
        uint256[] memory amounts = new uint256[](0);

        (, , uint256 swapFee) = vtoken.vaultFees();
        uint256 exactETHPaid = ((swapFee + vaultFactory.premiumMax()) *
            qty *
            currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.swap{value: expectedETHPaid * 2}(
            tokenIds,
            amounts,
            specificIds,
            address(this),
            address(this),
            MAX_VTOKEN_PREMIUM_LIMIT,
            false
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertEq(ethPaid, 0);

        for (uint i; i < qty; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken));
            assertEq(nft.ownerOf(specificIds[i]), address(this));
        }
    }

    // 1155

    function test_swap_1155_NoPremium_Success() external {
        _mintPositionWithTwap1155(currentNFTPrice);
        uint256 qty = 5;
        (, uint256[] memory specificIds) = _mintVTokenFor1155(qty);
        // jump to time such that no premium applicable
        vm.warp(block.timestamp + vaultFactory.premiumDuration() + 1);

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        (, , uint256 swapFee) = vtoken.vaultFees();
        uint256 exactETHPaid = (swapFee * qty * currentNFTPrice) / 1 ether;
        uint256 expectedETHPaid = _valueWithError(exactETHPaid);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken1155.swap{value: expectedETHPaid * 2}(
            tokenIds,
            amounts,
            specificIds,
            address(this),
            address(this),
            MAX_VTOKEN_PREMIUM_LIMIT,
            false
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        assertEq(nft1155.balanceOf(address(vtoken1155), tokenIds[0]), qty);
        assertEq(nft1155.balanceOf(address(this), specificIds[0]), qty);
    }
}
