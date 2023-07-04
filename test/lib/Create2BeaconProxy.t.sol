// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {Test} from "forge-std/Test.sol";

import {Create2BeaconProxy} from "@src/custom/proxy/Create2BeaconProxy.sol";
import {PoolAddress} from "@uni-periphery/libraries/PoolAddress.sol";

contract Create2BeaconProxyTests is Test {
    function test_GetBeaconCodeHash() external {
        bytes32 expectedBeaconCodeHash = keccak256(
            type(Create2BeaconProxy).creationCode
        );
        console.logBytes32(expectedBeaconCodeHash);
        assertEq(PoolAddress.BEACON_CODE_HASH, expectedBeaconCodeHash);
    }
}
