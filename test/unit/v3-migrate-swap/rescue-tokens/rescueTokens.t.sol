// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {V3MigrateSwap} from "@src/V3MigrateSwap.sol";

import {V3MigrateSwap_Unit_Test} from "../V3MigrateSwap.t.sol";

contract V3MigrateSwap_rescueTokens_Unit_Test is V3MigrateSwap_Unit_Test {
    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        // it should revert
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        v3MigrateSwap.rescueTokens(v2VToken);
    }

    function test_WhenTheCallerIsTheOwner(uint256 amount) external {
        switchPrank(users.owner);

        // transfer vTokens to the contract
        amount = bound(amount, 1, 1_000 ether);
        v2VToken.transfer(address(v3MigrateSwap), amount);

        uint256 preV2VTokenBalance = v2VToken.balanceOf(users.owner);
        v3MigrateSwap.rescueTokens(v2VToken);
        uint256 postV2VTokenBalance = v2VToken.balanceOf(users.owner);

        // it should send all the tokens to the caller
        assertEq(postV2VTokenBalance - preV2VTokenBalance, amount);
        assertEq(v2VToken.balanceOf(address(v3MigrateSwap)), 0);
    }
}
