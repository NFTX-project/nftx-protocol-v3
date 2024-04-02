// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {V3MigrateSwap} from "@src/V3MigrateSwap.sol";

import {V3MigrateSwap_Unit_Test} from "../V3MigrateSwap.t.sol";

contract V3MigrateSwap_setV2ToV3Mapping_Unit_Test is V3MigrateSwap_Unit_Test {
    event V2ToV3MappingSet(address v2VToken, address v3VToken);

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        // it should revert
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        v3MigrateSwap.setV2ToV3Mapping(address(v2VToken), address(v3VToken));
    }

    function test_WhenTheCallerIsTheOwner() external {
        switchPrank(users.owner);

        // it should emit {V2ToV3MappingSet} event
        vm.expectEmit(false, false, false, true);
        emit V2ToV3MappingSet(address(v2VToken), address(v3VToken));
        v3MigrateSwap.setV2ToV3Mapping(address(v2VToken), address(v3VToken));

        // it should set v2 to v3 mapping value
        assertEq(
            v3MigrateSwap.v2ToV3VToken(address(v2VToken)),
            address(v3VToken)
        );
    }
}
