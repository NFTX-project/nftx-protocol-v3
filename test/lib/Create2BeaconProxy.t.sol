// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {Create2BeaconProxy} from "@src/proxy/Create2BeaconProxy.sol";

contract Create2BeaconProxyTests {
    function test_GetBeaconCodeHash() external view {
        console.logBytes32(keccak256(type(Create2BeaconProxy).creationCode));
    }
}
