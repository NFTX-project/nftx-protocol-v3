// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {stdError} from "forge-std/Test.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {ExponentialPremium} from "@src/lib/ExponentialPremium.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract getVTokenPremium1155_Unit_Test is NFTXVaultFactory_Unit_Test {
    uint256 vaultId;
    INFTXVaultV3 vault;
    uint256 tokenId;
    uint256 amount;

    uint256[] depositAmounts;
    uint256 totalDeposited;

    uint256 totalPremium;
    uint256[] premiums;
    address[] depositors;

    function test_RevertGiven_TheVaultIdDoesNotExist() external {
        vm.expectRevert(stdError.indexOOBError);
        vaultFactory.getVTokenPremium1155(vaultId, tokenId, amount);
    }

    modifier givenTheVaultIdExists() {
        (vaultId, vault) = deployVToken1155(vaultFactory);
        _;
    }

    function test_GivenTheTokenIdDoesNotExistInTheVault()
        external
        givenTheVaultIdExists
    {
        (totalPremium, premiums, depositors) = vaultFactory
            .getVTokenPremium1155(vaultId, tokenId, amount);

        // it should return zero total premium
        assertEq(totalPremium, 0);
        // it should return empty premiums array
        assertEq(premiums.length, 0);
        // it should return empty depositors array
        assertEq(depositors.length, 0);
    }

    modifier givenTheTokenIdExistsInTheVault(bool shouldMintVToken) {
        if (shouldMintVToken) {
            uint256 qty = 5;

            tokenId = nft1155.nextId();
            nft1155.setApprovalForAll(address(vault), true);

            nft1155.mint(tokenId, qty);

            uint256[] memory tokenIds = new uint256[](1);
            uint256[] memory amounts = new uint256[](1);
            tokenIds[0] = tokenId;
            amounts[0] = qty;

            vault.mint({
                tokenIds: tokenIds,
                amounts: amounts,
                depositor: users.alice,
                to: users.alice
            });
            totalDeposited += qty;
        }

        _;
    }

    function test_RevertWhen_TheAmountIsZero()
        external
        givenTheVaultIdExists
        givenTheTokenIdExistsInTheVault(true)
    {
        vm.expectRevert(INFTXVaultFactoryV3.ZeroAmountRequested.selector);

        amount = 0;

        vaultFactory.getVTokenPremium1155(vaultId, tokenId, amount);
    }

    modifier whenTheAmountIsGreaterThanZero() {
        _;
    }

    function test_RevertWhen_TheAmountIsGreaterThanQuantityOfNftsInTheVault()
        external
        givenTheVaultIdExists
        givenTheTokenIdExistsInTheVault(true)
        whenTheAmountIsGreaterThanZero
    {
        vm.expectRevert(INFTXVaultFactoryV3.NFTInventoryExceeded.selector);

        amount = totalDeposited + 1;

        vaultFactory.getVTokenPremium1155(vaultId, tokenId, amount);
    }

    function test_WhenTheAmountIsLessThanOrEqualToTheQuantityOfNftsInTheVault(
        uint256[100] memory values,
        uint256 depositCount,
        uint256 _amount
    )
        external
        givenTheVaultIdExists
        givenTheTokenIdExistsInTheVault(false)
        whenTheAmountIsGreaterThanZero
    {
        amount = bound(_amount, 1, 10_000);
        depositCount = bound(depositCount, 1, values.length);

        // To avoid "The `vm.assume` cheatcode rejected too many inputs (65536 allowed)"
        // get 100 random values from depositAmounts, and then create a new array of length depositCount with those values
        depositAmounts = new uint256[](depositCount);
        for (uint256 i; i < depositCount; i++) {
            depositAmounts[i] = values[i];
        }

        tokenId = nft1155.nextId();
        nft1155.setApprovalForAll(address(vault), true);

        for (uint256 i; i < depositAmounts.length; i++) {
            depositAmounts[i] = bound(depositAmounts[i], 1, type(uint64).max);

            totalDeposited += depositAmounts[i];

            nft1155.mint(tokenId, depositAmounts[i]);

            uint256[] memory tokenIds = new uint256[](1);
            uint256[] memory amounts = new uint256[](1);
            tokenIds[0] = tokenId;
            amounts[0] = depositAmounts[i];

            vault.mint({
                tokenIds: tokenIds,
                amounts: amounts,
                depositor: makeAddr(
                    string.concat("depositor", Strings.toString(i))
                ),
                to: users.alice
            });

            totalDeposited += depositAmounts[i];
        }
        // vm.assume doesn't work
        // vm.assume(totalDeposited >= amount);
        if (totalDeposited < amount) {
            vm.expectRevert(INFTXVaultFactoryV3.NFTInventoryExceeded.selector);
        }

        // putting in a separate external call to avoid "EvmError: MemoryLimitOOG"
        // using storage instead to pass values
        // source: https://github.com/foundry-rs/foundry/issues/3971#issuecomment-1698653788
        this.getVTokenPremium1155();

        if (totalDeposited >= amount) {
            // it should return the total premium
            assertGt(totalPremium, 0);
            assertEq(
                totalPremium,
                ExponentialPremium.getPremium(
                    block.timestamp,
                    vaultFactory.premiumMax(),
                    vaultFactory.premiumDuration()
                ) * amount
            );

            // it should return the premiums array
            // it should return the depositors array

            assertEq(premiums.length, depositors.length);

            uint256 netDepositAmountUsed;
            for (uint256 i; i < depositors.length; i++) {
                uint256 depositAmountUsed;
                if (netDepositAmountUsed + depositAmounts[i] >= amount) {
                    depositAmountUsed = amount - netDepositAmountUsed;
                } else {
                    depositAmountUsed = depositAmounts[i];
                }
                netDepositAmountUsed += depositAmountUsed;

                assertEq(
                    premiums[i],
                    ExponentialPremium.getPremium(
                        block.timestamp,
                        vaultFactory.premiumMax(),
                        vaultFactory.premiumDuration()
                    ) * depositAmountUsed
                );
                assertEq(
                    depositors[i],
                    makeAddr(string.concat("depositor", Strings.toString(i)))
                );
            }
            assertEq(netDepositAmountUsed, amount);
        }
    }

    // helpers

    function getVTokenPremium1155() external {
        (totalPremium, premiums, depositors) = vaultFactory
            .getVTokenPremium1155(vaultId, tokenId, amount);
    }
}
