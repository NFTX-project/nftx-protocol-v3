// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {V3MigrateSwap} from "@src/V3MigrateSwap.sol";

import {V3MigrateSwap_Unit_Test} from "../V3MigrateSwap.t.sol";

contract V3MigrateSwap_Init_Unit_Test is V3MigrateSwap_Unit_Test {
    function test_ShouldSetTheOwner() external {
        // it should set the owner
        assertEq(v3MigrateSwap.owner(), users.owner);
    }
}
