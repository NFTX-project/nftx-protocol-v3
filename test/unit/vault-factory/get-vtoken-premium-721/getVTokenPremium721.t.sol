// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {stdError} from "forge-std/Test.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {ExponentialPremium} from "@src/lib/ExponentialPremium.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract getVTokenPremium721_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint256 vaultId;
    uint256 tokenId;

    function test_RevertGiven_TheVaultIdDoesNotExist() external {
        vm.expectRevert(stdError.indexOOBError);
        vaultFactory.getVTokenPremium721(vaultId, tokenId);
    }

    modifier givenTheVaultIdExists() {
        (vaultId, ) = deployVToken721(vaultFactory);
        _;
    }

    function test_GivenTheTokenIdDoesNotExistInTheVault()
        external
        givenTheVaultIdExists
    {
        (uint256 vTokenPremium, address depositor) = vaultFactory
            .getVTokenPremium721(vaultId, tokenId);

        // it should return zero premium
        assertEq(vTokenPremium, 0);
        // it should return zero address for depositor
        assertEq(depositor, address(0));
    }

    modifier givenTheTokenIdExistsInTheVault() {
        uint256[] memory tokenIds = nft721.mint(1);
        tokenId = tokenIds[0];

        INFTXVaultV3 vault = INFTXVaultV3(vaultFactory.vault(vaultId));

        nft721.setApprovalForAll(address(vault), true);
        vault.mint({
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            depositor: users.alice,
            to: users.alice
        });

        _;
    }

    function test_GivenTheTokenIdWasJustDeposited()
        external
        givenTheVaultIdExists
        givenTheTokenIdExistsInTheVault
    {
        (uint256 vTokenPremium, address depositor) = vaultFactory
            .getVTokenPremium721(vaultId, tokenId);

        // it should return max premium
        // account for exponential approximations in the contract
        uint256 minExpectedPremium = valueWithError({
            value: vaultFactory.premiumMax(),
            errorBps: 10
        });
        assertGt(vTokenPremium, minExpectedPremium);
        // it should return the depositor address
        assertEq(depositor, users.alice);
    }

    function test_GivenTheTokenIdWasDepositedAWhileAgoButStillInPremiumDuration(
        uint256 warpBy
    ) external givenTheVaultIdExists givenTheTokenIdExistsInTheVault {
        vm.assume(warpBy > 0 && warpBy <= vaultFactory.premiumDuration());
        // let some time pass after the token id was deposited
        vm.warp(block.timestamp + warpBy);

        // calculate expected value
        (uint48 timestamp, ) = INFTXVaultV3(vaultFactory.vault(vaultId))
            .tokenDepositInfo(tokenId);
        uint256 expectedPremium = ExponentialPremium.getPremium(
            timestamp,
            vaultFactory.premiumMax(),
            vaultFactory.premiumDuration()
        );

        (uint256 vTokenPremium, address depositor) = vaultFactory
            .getVTokenPremium721(vaultId, tokenId);

        // it should return the premium
        assertEq(vTokenPremium, expectedPremium);
        // it should return the depositor address
        assertEq(depositor, users.alice);
    }

    function test_GivenTheTokenIdWasDepositedAWhileAgoAndNotInPremiumDuration()
        external
        givenTheVaultIdExists
        givenTheTokenIdExistsInTheVault
    {
        vm.warp(block.timestamp + vaultFactory.premiumDuration());

        (uint256 vTokenPremium, address depositor) = vaultFactory
            .getVTokenPremium721(vaultId, tokenId);

        // it should return zero premium
        assertEq(vTokenPremium, 0);
        // it should return the depositor address
        assertEq(depositor, users.alice);
    }
}
