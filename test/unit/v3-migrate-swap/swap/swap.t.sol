// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {V3MigrateSwap} from "@src/V3MigrateSwap.sol";
import {PausableUpgradeable} from "@src/custom/PausableUpgradeable.sol";

import {V3MigrateSwap_Unit_Test} from "../V3MigrateSwap.t.sol";

contract V3MigrateSwap_swap_Unit_Test is V3MigrateSwap_Unit_Test {
    uint256 constant SWAP_LOCK_ID = 0;

    event Swapped(address v2VToken, uint256 amount);

    modifier givenTheSwapOperationIsPaused() {
        switchPrank(users.owner);
        v3MigrateSwap.setIsGuardian(users.owner, true);
        v3MigrateSwap.pause(SWAP_LOCK_ID);
        switchPrank(users.alice);
        _;
    }

    function test_RevertGiven_TheCallerIsNotTheOwner()
        external
        givenTheSwapOperationIsPaused
    {
        // it should revert
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        v3MigrateSwap.swap(address(v2VToken), 1 ether);
    }

    modifier givenTheSwapOperationIsNotPaused() {
        _;
    }

    function test_RevertGiven_TheSwapIsNotEnabledForTheVaultToken()
        external
        givenTheSwapOperationIsNotPaused
    {
        // it should revert
        vm.expectRevert(V3MigrateSwap.SwapNotEnabledForVault.selector);
        v3MigrateSwap.swap(address(v2VToken), 1 ether);
    }

    function test_GivenTheSwapIsEnabledForTheVaultToken(
        uint256 amount
    ) external givenTheSwapOperationIsNotPaused {
        amount = bound(amount, 1, 1_000 ether);

        // enable swap
        switchPrank(users.owner);
        v3MigrateSwap.setV2ToV3Mapping(address(v2VToken), address(v3VToken));
        // send V3 tokens to the contract
        v3VToken.transfer(address(v3MigrateSwap), amount);
        switchPrank(users.alice);

        // alice holds v2VTokens
        v2VToken.mint(amount);
        v2VToken.approve(address(v3MigrateSwap), amount);

        uint256 preAliceV2VTokenBalance = v2VToken.balanceOf(users.alice);
        uint256 preContractV2VTokenBalance = v2VToken.balanceOf(
            address(v3MigrateSwap)
        );
        uint256 preAliceV3VTokenBalance = v3VToken.balanceOf(users.alice);
        uint256 preContractV3VTokenBalance = v3VToken.balanceOf(
            address(v3MigrateSwap)
        );

        // it should emit {Swapped} event
        vm.expectEmit(false, false, false, true);
        emit Swapped(address(v2VToken), amount);
        v3MigrateSwap.swap(address(v2VToken), amount);

        uint256 postAliceV2VTokenBalance = v2VToken.balanceOf(users.alice);
        uint256 postContractV2VTokenBalance = v2VToken.balanceOf(
            address(v3MigrateSwap)
        );
        uint256 postAliceV3VTokenBalance = v3VToken.balanceOf(users.alice);
        uint256 postContractV3VTokenBalance = v3VToken.balanceOf(
            address(v3MigrateSwap)
        );

        // it should pull v2 vTokens
        assertEq(preAliceV2VTokenBalance - postAliceV2VTokenBalance, amount);
        assertEq(
            postContractV2VTokenBalance - preContractV2VTokenBalance,
            amount
        );
        // it should send back v3 vTokens
        assertEq(postAliceV3VTokenBalance - preAliceV3VTokenBalance, amount);
        assertEq(
            preContractV3VTokenBalance - postContractV3VTokenBalance,
            amount
        );
    }
}
