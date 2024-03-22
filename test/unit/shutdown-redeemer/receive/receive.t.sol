// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ShutdownRedeemer_Unit_Test} from "../ShutdownRedeemer.t.sol";

contract ShutdownRedeemer_receive_Unit_Test is ShutdownRedeemer_Unit_Test {
    function test_ShouldAllowSendingETHExternally() external {
        // it should allow sending ETH externally
        (bool success, ) = address(shutdownRedeemer).call{value: 1 ether}("");

        assertEq(success, true);
    }
}
