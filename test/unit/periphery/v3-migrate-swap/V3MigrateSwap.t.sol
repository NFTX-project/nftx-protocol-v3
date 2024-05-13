// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {V3MigrateSwap} from "@src/periphery/V3MigrateSwap.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {NewTestBase} from "@test/NewTestBase.sol";

contract V3MigrateSwap_Unit_Test is NewTestBase {
    V3MigrateSwap v3MigrateSwap;
    MockERC20 v2VToken;
    MockERC20 v3VToken;

    function setUp() public virtual override {
        super.setUp();

        switchPrank(users.owner);
        v3MigrateSwap = new V3MigrateSwap();
        v2VToken = new MockERC20(1_000 ether);
        v3VToken = new MockERC20(1_000 ether);
        switchPrank(users.alice);
    }
}
